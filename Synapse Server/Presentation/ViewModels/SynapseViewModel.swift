//
//  SynapseViewModel.swift
//  Synapse Server
//
//  Central ViewModel orchestrating discovery, pairing, encryption, and clipboard sync.
//

import Foundation
import Combine
import os.log
import AppKit
import UserNotifications

// Models for Telephony
struct CallRecord: Identifiable {
    let id = UUID()
    let number: String
    let state: String
    let timestamp: Date
}

struct SmsRecord: Identifiable {
    let id = UUID()
    let sender: String
    let body: String
    let timestamp: Date
}

struct NotificationRecord: Identifiable {
    let id = UUID()
    let appName: String
    let title: String
    let body: String
    let icon: NSImage?
    let packageName: String
    let timestamp: Date
}

@MainActor
final class SynapseViewModel: ObservableObject {
    static let shared = SynapseViewModel()

    private let logger = Logger(subsystem: "com.serkantkn.synapse-server", category: "ViewModel")

    // Managers
    let bonjourManager = BonjourManager()
    let tcpManager = TcpConnectionManager()
    let clipboardMonitor = ClipboardMonitor()

    // State
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var connectedDeviceName: String?
    @Published var pairingCode: String = ""
    @Published var lastSentClipboard: String = ""
    @Published var lastReceivedClipboard: String?
    @Published var errorMessage: String?
    @Published var showPairingRequest = false
    @Published var incomingPairingPacket: Packet?
    @Published var qrCodeString: String = ""

    // Telephony State
    @Published var calls: [CallRecord] = []
    @Published var messages: [SmsRecord] = []
    @Published var activeCallNumber: String? = nil
    @Published var deviceWallpaper: NSImage? = nil
    @Published var notifications: [NotificationRecord] = []
    @Published var batteryLevel: Int? = nil
    @Published var screenFrame: NSImage? = nil
    @Published var isMirroring = false
    private var wasPlayingBeforeCall = false


    private var cancellables = Set<AnyCancellable>()
    private let serverPort: UInt16 = 9876
    private var heartbeatTimer: Timer?
    private let heartbeatTimeout: TimeInterval = 18 // seconds

    /// Known (previously approved) device IDs for auto-accept.
    private var knownDeviceIds: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "knownDeviceIds") ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "knownDeviceIds")
        }
    }

    init() {
        generatePairingCode()
        observeIncomingPackets()
        setupClipboardCallback()
        setupDisconnectCallback()
        requestNotificationPermission()
        
        // Automatically start discovery/advertising on launch
        startDiscovery()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.logger.info("✅ Notification permission granted")
            } else if let error = error {
                self.logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Connection Monitoring

    private func setupDisconnectCallback() {
        tcpManager.onDisconnected = { [weak self] in
            guard let self = self else { return }
            self.logger.info("🔌 Connection lost detected by TCP manager")
            self.handleRemoteDisconnect()
        }
    }

    /// Start a timer to check for heartbeat timeouts.
    private func startHeartbeatMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkHeartbeatTimeout()
            }
        }
    }

    private func stopHeartbeatMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func checkHeartbeatTimeout() {
        guard case .connected = connectionStatus else { return }
        guard let lastReceived = tcpManager.lastPacketReceivedAt else {
            logger.warning("⚠️ No packet timestamp available, triggering disconnect")
            handleRemoteDisconnect()
            return
        }

        let elapsed = Date().timeIntervalSince(lastReceived)
        if elapsed > heartbeatTimeout {
            logger.warning("⏱️ Heartbeat timeout (\(Int(elapsed))s elapsed). Disconnecting.")
            handleRemoteDisconnect()
        }
    }

    /// Called when the remote side disconnects (either detected by NWConnection or timeout).
    private func handleRemoteDisconnect() {
        guard case .connected = connectionStatus else { return }
        
        logger.info("🔌 Remote disconnect handling...")
        clipboardMonitor.stopMonitoring()
        stopHeartbeatMonitoring()
        
        // TcpConnectionManager already cleaned up if this was triggered by onDisconnected callback,
        // but calling disconnect() again is safe due to its internal guard.
        tcpManager.disconnect()
        
        connectionStatus = .disconnected
        connectedDeviceName = nil
        lastReceivedClipboard = nil
        errorMessage = "Bağlantı kesildi"
        
        logger.info("♻️ Restarting discovery after disconnect...")
        startDiscovery()
    }

    // MARK: - Discovery

    func startDiscovery() {
        connectionStatus = .discovering

        // Start listener and advertising
        bonjourManager.startAdvertising(port: serverPort)

        // Accept incoming TCP connections via the listener
        if let listener = bonjourManager.getListener() {
            tcpManager.acceptConnections(from: listener)
        }

        // Browse for other devices
        bonjourManager.startBrowsing()
    }

    func stopDiscovery() {
        bonjourManager.stopBrowsing()
        bonjourManager.stopAdvertising()
        if case .discovering = connectionStatus {
            connectionStatus = .disconnected
        }
    }

    // MARK: - Pairing

    func generatePairingCode() {
        pairingCode = String(format: "%06d", Int.random(in: 100000...999999))
        self.updateQRCodeString()
    }

    private func updateQRCodeString() {
        let ip = getLocalIPAddress() ?? "0.0.0.0"
        let actualPort = bonjourManager.listenerPort ?? serverPort
        self.qrCodeString = "synapse://connect?ip=\(ip)&port=\(actualPort)&code=\(pairingCode)"
        logger.info("📱 Generated QR String: \(self.qrCodeString) (port: \(actualPort))")
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name == "en1" { // Wi-Fi interfaces
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    func connectToDevice(host: String, port: UInt16) {
        connectionStatus = .pairing
        tcpManager.connect(to: host, port: port)

        // Send handshake
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_REQUEST,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "device_name": AnyCodable(Host.current().localizedName ?? "Mac"),
                "device_type": AnyCodable("macOS"),
                "public_key": AnyCodable(tcpManager.cryptoManager.publicKeyBase64()),
                "pairing_code": AnyCodable(pairingCode)
            ]
        )

        // Small delay to allow connection to establish
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.tcpManager.send(packet: packet, encrypt: false)
        }
    }

    func acceptPairing() {
        guard let incoming = incomingPairingPacket else { return }

        // Extract peer public key and derive shared secret
        if let publicKeyStr = incoming.payload["public_key"]?.value as? String {
            do {
                let peerKey = try tcpManager.cryptoManager.decodePeerPublicKey(publicKeyStr)
                try tcpManager.cryptoManager.deriveSharedSecret(peerPublicKey: peerKey)
            } catch {
                logger.error("Key exchange failed: \(error.localizedDescription)")
            }
        }

        // Send acceptance with our public key
        let response = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_RESPONSE,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "status": AnyCodable("ACCEPTED"),
                "public_key": AnyCodable(tcpManager.cryptoManager.publicKeyBase64())
            ]
        )
        tcpManager.send(packet: response, encrypt: false)

        connectedDeviceName = incoming.payload["device_name"]?.value as? String
        connectionStatus = .connected
        showPairingRequest = false
        
        // Remember this device for auto-accept next time
        var ids = knownDeviceIds
        ids.insert(incoming.senderId)
        knownDeviceIds = ids
        logger.info("📝 Saved device \(incoming.senderId) as known")
        
        startClipboardMonitoring()
        startHeartbeatMonitoring()
    }

    func rejectPairing() {
        let response = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_RESPONSE,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "status": AnyCodable("REJECTED"),
                "reason": AnyCodable("Kullanıcı eşleşmeyi reddetti")
            ]
        )
        tcpManager.send(packet: response, encrypt: false)
        showPairingRequest = false
        connectionStatus = .disconnected
    }

    // MARK: - Clipboard

    private func setupClipboardCallback() {
        clipboardMonitor.onClipboardChanged = { [weak self] text in
            self?.sendClipboard(text)
        }
    }

    func startClipboardMonitoring() {
        clipboardMonitor.startMonitoring()
    }

    private func sendClipboard(_ text: String) {
        guard case .connected = connectionStatus else { return }

        DispatchQueue.main.async {
            self.lastSentClipboard = text
        }

        let packet = Packet(
            packetId: UUID().uuidString,
            type: .CLIPBOARD_TRANSFER,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "content_type": AnyCodable("TEXT"),
                "content": AnyCodable(text),
                "metadata": AnyCodable([
                    "origin_app": "macOS",
                    "size": text.count
                ] as [String : Any])
            ]
        )
        tcpManager.send(packet: packet)
        logger.info("Sent clipboard: \(text.prefix(50))...")
    }

    // MARK: - Incoming Packet Handling

    private func observeIncomingPackets() {
        tcpManager.$lastReceivedPacket
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] packet in
                self?.handlePacket(packet)
            }
            .store(in: &cancellables)
    }

    private func handlePacket(_ packet: Packet) {
        logger.info("📩 Received packet type: \(packet.type.rawValue)")
        switch packet.type {
        case .HANDSHAKE_REQUEST:
            incomingPairingPacket = packet
            connectionStatus = .pairing
            
            // Auto-accept if this device was previously approved
            if knownDeviceIds.contains(packet.senderId) {
                logger.info("✅ Auto-accepting known device: \(packet.senderId)")
                acceptPairing()
            } else {
                showPairingRequest = true
            }

        case .HANDSHAKE_RESPONSE:
            let status = packet.payload["status"]?.value as? String
            if status == "ACCEPTED" {
                // Complete key exchange
                if let publicKeyStr = packet.payload["public_key"]?.value as? String {
                    do {
                        let peerKey = try tcpManager.cryptoManager.decodePeerPublicKey(publicKeyStr)
                        try tcpManager.cryptoManager.deriveSharedSecret(peerPublicKey: peerKey)
                    } catch {
                        logger.error("Key exchange failed: \(error.localizedDescription)")
                    }
                }
                connectionStatus = .connected
                startClipboardMonitoring()
                startHeartbeatMonitoring()
            } else {
                connectionStatus = .disconnected
                errorMessage = "Eşleşme reddedildi"
            }

        case .CLIPBOARD_TRANSFER:
            if let content = packet.payload["content"]?.value as? String {
                lastReceivedClipboard = content
                clipboardMonitor.setClipboardContent(content)
                logger.info("Received clipboard: \(content.prefix(50))...")
            }

        case .HEARTBEAT:
            if let val = packet.payload["battery_level"]?.value {
                let level = (val as? Int) ?? (val as? Double).map(Int.init) ?? (val as? Int64).map(Int.init)
                if let level = level {
                    DispatchQueue.main.async {
                        self.batteryLevel = level
                    }
                    logger.info("🔋 Battery level updated: \(level)%")
                }
            }
            logger.info("Heartbeat from \(packet.senderId)")
            
        case .CALL_EVENT:
            handleCallEvent(packet.payload)
            
        case .SMS_EVENT:
            handleSmsEvent(packet.payload)
            
        case .WALLPAPER_TRANSFER:
            handleWallpaperTransfer(packet.payload)
            
        case .NOTIFICATION_EVENT:
            handleNotificationEvent(packet.payload)
            
        case .CALL_COMMAND, .SMS_COMMAND, .REMOTE_INPUT:
            break // Handled on Android side
            
        case .SCREEN_FRAME:
            handleScreenFrame(packet.payload)
            
        case .SCREEN_STREAM_COMMAND:
            if let command = packet.payload["command"]?.value as? String, command == "STOP" {
                DispatchQueue.main.async { self.isMirroring = false }
            }
        }
    }

    func toggleScreenMirroring() {
        let command = isMirroring ? "STOP" : "START"
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .SCREEN_STREAM_COMMAND,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["command": AnyCodable(command)]
        )
        tcpManager.send(packet: packet)
        isMirroring.toggle()
        
        if !isMirroring {
            screenFrame = nil
        }
    }

    func sendRemoteInput(x: Double, y: Double, action: String) {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .REMOTE_INPUT,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "x": AnyCodable(x),
                "y": AnyCodable(y),
                "action": AnyCodable(action)
            ]
        )
        tcpManager.send(packet: packet)
    }

    private func handleScreenFrame(_ payload: [String: AnyCodable]) {
        guard let base64String = payload["image"]?.value as? String,
              let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else { return }
        
        DispatchQueue.main.async {
            self.screenFrame = image
        }
    }

    private func handleCallEvent(_ payload: [String: AnyCodable]) {
        guard let state = payload["state"]?.value as? String,
              let number = payload["number"]?.value as? String else { return }
        
        DispatchQueue.main.async {
            let record = CallRecord(number: number, state: state, timestamp: Date())
            self.calls.insert(record, at: 0)
            
            if state == "RINGING" {
                self.activeCallNumber = number
                self.pauseMedia()
            } else if state == "IDLE" {
                self.activeCallNumber = nil
                self.resumeMedia()
            }
        }
    }

    private func handleSmsEvent(_ payload: [String: AnyCodable]) {
        guard let sender = payload["sender"]?.value as? String,
              let body = payload["body"]?.value as? String else { return }
        
        let record = SmsRecord(sender: sender, body: body, timestamp: Date())
        messages.insert(record, at: 0)
        if messages.count > 100 { messages.removeLast() }
    }

    private func handleWallpaperTransfer(_ payload: [String: AnyCodable]) {
        guard let base64String = payload["image"]?.value as? String else {
            logger.error("❌ Wallpaper transfer failed: No image string in payload")
            return
        }
        
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            logger.error("❌ Wallpaper transfer failed: Invalid Base64 data")
            return
        }
        
        guard let image = NSImage(data: data) else {
            logger.error("❌ Wallpaper transfer failed: Could not create NSImage from data (\(data.count) bytes)")
            return
        }
        
        DispatchQueue.main.async {
            self.deviceWallpaper = image
            self.logger.info("🖼️ New device wallpaper received and updated (\(Int(image.size.width))x\(Int(image.size.height)))")
        }
    }

    func getIPAddress() -> String {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name == "en1" || name == "en2" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address ?? "IP Tespit Edilemedi"
    }

    private func handleNotificationEvent(_ payload: [String: AnyCodable]) {
        let appName = payload["app_name"]?.value as? String ?? "Bilinmeyen"
        let title = payload["title"]?.value as? String ?? ""
        let body = payload["text"]?.value as? String ?? ""
        let packageName = payload["package_name"]?.value as? String ?? ""
        
        // Decode app icon
        var icon: NSImage? = nil
        if let iconBase64 = payload["icon"]?.value as? String,
           let data = Data(base64Encoded: iconBase64) {
            icon = NSImage(data: data)
        }
        
        let record = NotificationRecord(
            appName: appName,
            title: title,
            body: body,
            icon: icon,
            packageName: packageName,
            timestamp: Date()
        )
        notifications.insert(record, at: 0)
        if notifications.count > 200 { notifications.removeLast() }
        
        // Trigger native macOS notification
        triggerNativeNotification(appName: appName, title: title, body: body)
        
        logger.info("🔔 Notification from \(appName): \(title)")
    }

    private func triggerNativeNotification(appName: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.subtitle = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Commands

    private func pauseMedia() {
        let script = """
        tell application "Music" to pause
        tell application "Spotify" to pause
        """
        executeAppleScript(script)
        wasPlayingBeforeCall = true
    }

    private func resumeMedia() {
        if wasPlayingBeforeCall {
            let script = """
            tell application "Music" to play
            tell application "Spotify" to play
            """
            executeAppleScript(script)
        }
    }

    private func executeAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }

    // MARK: - Actions

    func sendCall(number: String) {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .CALL_COMMAND,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["number": AnyCodable(number)]
        )
        tcpManager.send(packet: packet)
    }

    func sendSms(number: String, body: String) {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .SMS_COMMAND,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "number": AnyCodable(number),
                "body": AnyCodable(body)
            ]
        )
        tcpManager.send(packet: packet)
    }

    // MARK: - Disconnect

    func disconnect() {
        clipboardMonitor.stopMonitoring()
        stopHeartbeatMonitoring()
        tcpManager.disconnect()
        connectionStatus = .disconnected
        connectedDeviceName = nil
        lastReceivedClipboard = nil
    }

    func clearError() {
        errorMessage = nil
    }
}
