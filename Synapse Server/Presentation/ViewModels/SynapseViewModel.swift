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
import WidgetKit

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

struct RemotePhoto: Identifiable {
    let id: String
    let name: String
    let date: Date
    let size: Int64
    let thumbnail: NSImage?
    var fullImage: NSImage?
}

@MainActor
final class SynapseViewModel: ObservableObject {
    static let shared = SynapseViewModel()

    private let logger = Logger(subsystem: "com.serkantkn.synapse-server", category: "ViewModel")

    // Managers
    let bonjourManager = BonjourManager()
    let tcpManager = TcpConnectionManager()
    let clipboardMonitor = ClipboardMonitor()
    
    @Published var isClipboardSyncEnabled: Bool = UserDefaults.standard.bool(forKey: "isClipboardSyncEnabled") {
        didSet {
            UserDefaults.standard.set(isClipboardSyncEnabled, forKey: "isClipboardSyncEnabled")
            if isClipboardSyncEnabled && connectionStatus == .connected {
                startClipboardMonitoring()
            } else {
                clipboardMonitor.stopMonitoring()
            }
        }
    }

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
    @Published var remotePhotos: [RemotePhoto] = []
    @Published var isRemoteAccessibilityEnabled = false
    
    private var wasPlayingBeforeCall = false


    private var cancellables = Set<AnyCancellable>()
    private let serverPort: UInt16 = 9876
    private var heartbeatTimer: Timer?
    private let heartbeatTimeout: TimeInterval = 18 // seconds

    // SettingsManager.shared is now used for known devices and settings

    init() {
        // Pano senkronizasyonunun varsayılan olarak açık gelmesini sağla
        UserDefaults.standard.register(defaults: ["isClipboardSyncEnabled": true])
        self.isClipboardSyncEnabled = UserDefaults.standard.bool(forKey: "isClipboardSyncEnabled")
        
        generatePairingCode()
        observeIncomingPackets()
        setupClipboardCallback()
        setupDisconnectCallback()
        requestNotificationPermission()
        
        // Automatically start discovery/advertising on launch
        startDiscovery()
        updateWidgetData() // Initial widget state
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
        
        updateWidgetData() // Update widget to show disconnected
        
        logger.info("♻️ Restarting discovery after disconnect...")
        startDiscovery()
    }

    private var lastWidgetUpdateHash: String = ""

    private func updateWidgetData() {
        let suiteName = "group.com.serkantkn.Synapse-Server"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            logger.error("❌ App Group not found: \(suiteName)")
            return
        }
        
        let name = connectedDeviceName ?? "Bağlı Değil"
        let connected = (connectionStatus == .connected)
        let battery = batteryLevel ?? 0
        
        // WidgetKit Rate Limit Koruması: Sadece veri değiştiyse güncelle
        let currentHash = "\(name)_\(connected)_\(battery)"
        if currentHash == lastWidgetUpdateHash {
            return // Aynı veri, widget'ı tekrar tetiklemeye gerek yok
        }
        lastWidgetUpdateHash = currentHash
        
        defaults.set(name, forKey: "deviceName")
        defaults.set(connected, forKey: "isConnected")
        defaults.set(battery, forKey: "batteryLevel")
        defaults.set(Date(), forKey: "lastUpdate")
        
        defaults.synchronize()
        
        // Minor delay to ensure disk write before widget refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WidgetCenter.shared.reloadAllTimelines()
            self.logger.info("📡 Widget sync: \(name), Connected: \(connected), Battery: \(battery)")
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        guard connectionStatus != .connected else { return }
        if connectionStatus != .pairing {
            connectionStatus = .discovering
        }

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
        let deviceName = incoming.payload["device_name"]?.value as? String ?? "Bilinmeyen Android Cihaz"
        SettingsManager.shared.addKnownDevice(id: incoming.senderId, name: deviceName)
        logger.info("📝 Saved device \(incoming.senderId) (\(deviceName)) as known")
        
        startClipboardMonitoring()
        startHeartbeatMonitoring()
        
        // Bağlantı kurulduğunda hemen duvar kağıdını iste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestWallpaper()
        }
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
        if isClipboardSyncEnabled {
            clipboardMonitor.startMonitoring()
        }
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
            
            // Auto-accept if this device was previously approved AND requirePin is false
            let isKnown = SettingsManager.shared.isDeviceKnown(id: packet.senderId)
            let requirePin = SettingsManager.shared.requirePinForKnownDevices
            
            if isKnown && !requirePin {
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
                if let deviceName = packet.payload["deviceName"]?.value as? String {
                    self.connectedDeviceName = deviceName
                }
                updateWidgetData() // Update widget to show connected with name
                startClipboardMonitoring()
                startHeartbeatMonitoring()
            } else {
                connectionStatus = .disconnected
                errorMessage = "Eşleşme reddedildi"
            }

        case .CLIPBOARD_TRANSFER:
            if let content = packet.payload["text"]?.value as? String {
                if isClipboardSyncEnabled {
                    DispatchQueue.main.async {
                        self.lastReceivedClipboard = content
                        self.clipboardMonitor.setClipboardContent(content)
                        self.logger.info("Received clipboard: \(content.prefix(50))...")
                    }
                }
            }

        case .HEARTBEAT:
            if let val = packet.payload["battery_level"]?.value {
                let level = (val as? Int) ?? (val as? Double).map(Int.init) ?? (val as? Int64).map(Int.init)
                if let level = level {
                    DispatchQueue.main.async {
                        self.batteryLevel = level
                        self.updateWidgetData() // Update widget with new battery
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
        
        case .WALLPAPER_REQUEST:
            break // Mac hiçbir zaman wallpaper isteği almaz, Android gönderir
            
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
            
        case .FILE_TRANSFER:
            break // Currently Mac -> Android only

        case .PHOTO_LIBRARY_REQ, .PHOTO_DOWNLOAD_REQ:
            break // Handled on Android

        case .PHOTO_LIBRARY_RESP:
            if let photosArray = packet.payload["photos"]?.value as? [[String: Any]] {
                var loadedPhotos: [RemotePhoto] = []
                for p in photosArray {
                    guard let id = p["id"] as? String,
                          let name = p["name"] as? String else {
                        self.logger.warning("Skipping a photo due to missing id or name")
                        continue 
                    }
                    
                    let dateMs = (p["date"] as? Int).map { Int64($0) } ?? (p["date"] as? Int64) ?? 0
                    let size = (p["size"] as? Int).map { Int64($0) } ?? (p["size"] as? Int64) ?? 0
                    
                    var thumbImage: NSImage? = nil
                    if let thumbB64 = p["thumbnail"] as? String,
                       let data = Data(base64Encoded: thumbB64) {
                        thumbImage = NSImage(data: data)
                    }
                    
                    let date = Date(timeIntervalSince1970: TimeInterval(dateMs) / 1000.0)
                    loadedPhotos.append(RemotePhoto(id: id, name: name, date: date, size: size, thumbnail: thumbImage))
                }
                DispatchQueue.main.async {
                    self.remotePhotos = loadedPhotos
                }
            }

        case .PHOTO_DOWNLOAD_RESP:
            if let id = packet.payload["photo_id"]?.value as? String,
               let dataB64 = packet.payload["data"]?.value as? String,
               let data = Data(base64Encoded: dataB64),
               let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    if let index = self.remotePhotos.firstIndex(where: { $0.id == id }) {
                        self.remotePhotos[index].fullImage = image
                        let opened = self.openInPreview(image: image, filename: self.remotePhotos[index].name)
                        NotificationCenter.default.post(
                            name: Notification.Name("PhotoDownloaded"),
                            object: nil,
                            userInfo: ["id": id, "openedInPreview": opened]
                        )
                    }
                }
            }
        case .PHOTO_DELETE_REQ:
            break // Handled on Android
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

    func sendKeyboardInput(key: String, type: String = "STRING") {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .REMOTE_INPUT,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "action": AnyCodable("KEYBOARD"),
                "key": AnyCodable(key),
                "key_type": AnyCodable(type)
            ]
        )
        tcpManager.send(packet: packet)
    }

    func sendFile(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let base64String = data.base64EncodedString()
                let packet = Packet(
                    packetId: UUID().uuidString,
                    type: .FILE_TRANSFER,
                    senderId: "mac-server",
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    payload: [
                        "file_name": AnyCodable(url.lastPathComponent),
                        "file_size": AnyCodable(data.count),
                        "file_data": AnyCodable(base64String)
                    ]
                )
                self.tcpManager.send(packet: packet)
                self.logger.info("Sent file \(url.lastPathComponent) (\(data.count) bytes) to Android.")
            } catch {
                self.logger.error("Failed to read file for transfer: \(error.localizedDescription)")
            }
        }
    }

    func requestPhotoLibrary() {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .PHOTO_LIBRARY_REQ,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [:]
        )
        tcpManager.send(packet: packet)
    }

    func downloadFullPhoto(id: String) {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .PHOTO_DOWNLOAD_REQ,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["photo_id": AnyCodable(id)]
        )
        tcpManager.send(packet: packet)
    }

    func deletePhotoFromPhone(id: String) {
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .PHOTO_DELETE_REQ,
            senderId: "mac-server",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["photo_id": AnyCodable(id)]
        )
        tcpManager.send(packet: packet)
        
        // Optimistically remove from remotePhotos local list
        DispatchQueue.main.async {
            self.remotePhotos.removeAll(where: { $0.id == id })
        }
    }

    func openInPreview(image: NSImage, filename: String) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        var finalFilename = filename
        if !filename.lowercased().hasSuffix(".jpg") && !filename.lowercased().hasSuffix(".jpeg") {
            finalFilename += ".jpg"
        }
        let fileUrl = tempDir.appendingPathComponent(finalFilename)
        
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let data = bitmap.representation(using: .jpeg, properties: [:]) {
            do {
                try data.write(to: fileUrl)
                return NSWorkspace.shared.open(fileUrl)
            } catch {
                self.logger.error("Failed to write/open temp file in Preview: \(error.localizedDescription)")
                return false
            }
        }
        return false
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
        
        let isAcc = payload["accessibility_enabled"]?.value as? Bool ?? false
        
        DispatchQueue.main.async {
            self.screenFrame = image
            self.isRemoteAccessibilityEnabled = isAcc
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

    func requestWallpaper() {
        guard case .connected = connectionStatus else { return }
        let packet = Packet(
            packetId: UUID().uuidString,
            type: .WALLPAPER_REQUEST,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [:]
        )
        tcpManager.send(packet: packet)
        logger.info("🖼️ Wallpaper requested from Android")
    }

    private func handleWallpaperTransfer(_ payload: [String: AnyCodable]) {
        logger.info("🖼️ handleWallpaperTransfer called. Payload keys: \(payload.keys.joined(separator: ", "))")
        
        guard let base64String = payload["image"]?.value as? String else {
            logger.error("❌ Wallpaper: 'image' key not found or wrong type. Keys: \(payload.keys.joined(separator: ", "))")
            return
        }
        
        logger.info("🖼️ Base64 string length: \(base64String.count)")
        
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            logger.error("❌ Wallpaper: Base64 decode failed (string len=\(base64String.count))")
            return
        }
        
        logger.info("🖼️ Decoded data size: \(data.count) bytes")
        
        guard let image = NSImage(data: data) else {
            logger.error("❌ Wallpaper: NSImage creation failed from \(data.count) bytes")
            return
        }
        
        DispatchQueue.main.async {
            self.deviceWallpaper = image
            self.logger.info("🖼️ Wallpaper updated (\(Int(image.size.width))x\(Int(image.size.height)))")
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
        if SettingsManager.shared.muteNotifications {
            return
        }

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
