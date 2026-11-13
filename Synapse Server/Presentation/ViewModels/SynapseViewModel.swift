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
    /// Android notification key; used to answer the notification from the Mac.
    var key: String = ""
    var canReply: Bool = false
}

/// What is playing on the phone right now.
struct PhoneMediaState: Equatable {
    var title: String
    var artist: String
    var album: String
    var appName: String
    var isPlaying: Bool
    var volume: Int
    var maxVolume: Int
    var art: NSImage?
}

enum ReplyStatus: Equatable { case sending, sent, failed }

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

    // Companion features
    @Published var media: PhoneMediaState? = nil
    @Published var isFindingPhone = false
    @Published var replyStatus: [String: ReplyStatus] = [:]
    @Published var transferMessage: String? = nil
    private var findPhoneResetWork: DispatchWorkItem?
    private var transferMessageWork: DispatchWorkItem?
    private lazy var notificationDelegate = NotificationActionHandler(viewModel: self)

    /// Frames are capped at 10 MB and files travel base64-encoded and encrypted inside one frame.
    static let maxFileSize = 7_000_000
    
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
        notificationDelegate.register()
        
        #if DEBUG
        // UI screenshots without a phone. Skips discovery so a real phone can't connect meanwhile.
        if let demo = ProcessInfo.processInfo.environment["SYNAPSE_DEBUG_DEMO"] {
            loadDemoSession(withData: demo != "empty")
            return
        }
        #endif

        // Automatically start discovery/advertising on launch
        startDiscovery()
        updateWidgetData() // Initial widget state
    }

    #if DEBUG
    /// Fake session for UI screenshots: "SYNAPSE_DEBUG_DEMO=1" (with data), "=empty" or "=pairing".
    private func loadDemoSession(withData: Bool) {
        if ProcessInfo.processInfo.environment["SYNAPSE_DEBUG_DEMO"] == "pairing" {
            connectionStatus = .discovering
            return
        }
        connectedDeviceName = "Galaxy S24 FE"
        batteryLevel = 82
        connectionStatus = .connected
        guard withData else { return }
        let now = Date()
        calls = [
            CallRecord(number: "+90 532 418 22 10", state: "RINGING", timestamp: now.addingTimeInterval(-120)),
            CallRecord(number: "+90 541 220 19 87", state: "IDLE", timestamp: now.addingTimeInterval(-3_600))
        ]
        messages = [
            SmsRecord(sender: "Ayşe Yılmaz", body: "Akşam 8 gibi orada olurum, masayı ayırttım.", timestamp: now.addingTimeInterval(-300)),
            SmsRecord(sender: "+90 850 222 00 00", body: "Kargonuz bugün teslim edilecek. Takip no: TR4821", timestamp: now.addingTimeInterval(-7_200))
        ]
        var whatsapp = NotificationRecord(appName: "WhatsApp", title: "Burak Demir", body: "Yarınki toplantı 10:00'a alındı, haberin olsun.",
                                          icon: nil, packageName: "com.whatsapp", timestamp: now.addingTimeInterval(-60))
        whatsapp.key = "demo-1"
        whatsapp.canReply = true
        notifications = [
            whatsapp,
            NotificationRecord(appName: "Takvim", title: "Diş hekimi", body: "Yarın 14:30 · Kadıköy",
                               icon: nil, packageName: "com.google.android.calendar", timestamp: now.addingTimeInterval(-1_800))
        ]
        media = PhoneMediaState(title: "Gece Yolculuğu", artist: "Mavi Kuşlar", album: "Şehir Işıkları",
                                appName: "Spotify", isPlaying: true, volume: 9, maxVolume: 15, art: nil)
        lastSentClipboard = "https://synapse.example/davet/8f2c"
        lastReceivedClipboard = "Kapı kodu: 4821#"
        remotePhotos = []
    }
    #endif

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.logger.info("✅ Notification permission granted")
            } else if let error = error {
                self.logger.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Connection Monitoring

    private func setupDisconnectCallback() {
        tcpManager.onDisconnected = { [weak self] in
            guard let self = self else { return }
            self.logger.info("🔌 Connection lost detected by TCP manager")
            self.pendingPake = nil // a PAKE exchange can't continue on another connection
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
        resetCompanionState()
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
        pendingPake = nil // an exchange started with the old PIN must not complete
        pairingCode = String(format: "%06d", Int.random(in: 100000...999999))
        #if DEBUG
        // Automated tests can't read the PIN off the screen; Debug builds only.
        if let fixed = ProcessInfo.processInfo.environment["SYNAPSE_DEBUG_PIN"], fixed.count == 6 {
            pairingCode = fixed
        }
        #endif
        self.updateQRCodeString()
    }

    private func updateQRCodeString() {
        let ip = getLocalIPAddress() ?? "0.0.0.0"
        let actualPort = bonjourManager.listenerPort ?? serverPort
        self.qrCodeString = "synapse://connect?ip=\(ip)&port=\(actualPort)&code=\(pairingCode)"
        logger.info("📱 Generated pairing QR (port: \(actualPort))") // never log the PIN
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

    // MARK: - Handshake verification
    //
    // First pairing runs a PAKE on the PIN shown here (Pake.swift), so the PIN can't be recovered
    // from a captured exchange. Reconnects prove the token both sides derived from that first
    // session. The PAKE key or the token is mixed into the session key, so an impostor that
    // copies a known device id still can't read or send encrypted packets.

    private var pinAttempts = 0
    private var pinLockoutUntil: Date?
    private let maxPinAttempts = 5
    private let pinLockoutDuration: TimeInterval = 30

    /// A PAKE exchange waiting for the phone's confirmation (message 3).
    private struct PendingPake {
        let request: Packet
        let peerKey: String
        let responderKey: String
        let key: Data
    }
    private var pendingPake: PendingPake?

    private func handleHandshakeRequest(_ packet: Packet) {
        guard connectionStatus != .connected else {
            logger.warning("⛔ Handshake while already connected, ignoring")
            return
        }
        guard let peerKey = packet.payload["public_key"]?.value as? String,
              let mode = packet.payload["auth_mode"]?.value as? String else {
            rejectHandshake(code: "OUTDATED_CLIENT", reason: "Uygulama sürümü uyumsuz")
            return
        }
        pendingPake = nil

        switch mode {
        case CryptoManager.authModeToken:
            if SettingsManager.shared.requirePinForKnownDevices {
                rejectHandshake(code: "PIN_REQUIRED", reason: "PIN gerekli")
                return
            }
            guard let proof = packet.payload["auth_proof"]?.value as? String,
                  let tokenB64 = SettingsManager.shared.pairingToken(for: packet.senderId),
                  let token = Data(base64Encoded: tokenB64),
                  CryptoManager.verifyAuthProof(proof, secret: token, mode: mode, publicKeyBase64: peerKey) else {
                logger.warning("⛔ Token check failed for \(packet.senderId)")
                rejectHandshake(code: "UNKNOWN_DEVICE", reason: "Cihaz tanınmadı")
                return
            }
            completePairing(packet, peerKey: peerKey, secret: token, isNewPairing: false)

        case Pake.authMode:
            startPake(packet, peerKey: peerKey)

        default:
            // Includes the old "pin" mode, whose proof could be brute-forced offline.
            rejectHandshake(code: "OUTDATED_CLIENT", reason: "Desteklenmeyen doğrulama")
        }
    }

    /// Message 2: answer the phone's PAKE share with ours and our confirmation.
    private func startPake(_ packet: Packet, peerKey: String) {
        if let until = pinLockoutUntil, until > Date() {
            rejectHandshake(code: "BAD_PIN", reason: "Çok fazla hatalı deneme, biraz bekleyin")
            return
        }
        // Each exchange is one PIN guess, so count it now: a guesser could otherwise drop the
        // connection after checking our confirmation and never reach the failure path.
        guard pinAttempts < maxPinAttempts else {
            pinAttempts = 0
            pinLockoutUntil = Date().addingTimeInterval(pinLockoutDuration)
            generatePairingCode() // burn the PIN
            rejectHandshake(code: "BAD_PIN", reason: "Çok fazla hatalı deneme, biraz bekleyin")
            return
        }
        pinAttempts += 1

        guard let shareB64 = packet.payload["pake_share"]?.value as? String,
              let peerShare = Data(base64Encoded: shareB64) else {
            rejectHandshake(code: "OUTDATED_CLIENT", reason: "Uygulama sürümü uyumsuz")
            return
        }
        let responderKey = tcpManager.cryptoManager.publicKeyBase64()
        let party: Pake.Party
        let key: Data
        do {
            party = try Pake.Party(role: .responder, pin: pairingCode, initiatorKey: peerKey)
            key = try party.sharedKey(peerShare: peerShare, responderKey: responderKey)
        } catch {
            logger.error("PAKE failed: \(error.localizedDescription)")
            rejectHandshake(code: "BAD_KEY", reason: "Anahtar değişimi başarısız")
            return
        }
        pendingPake = PendingPake(request: packet, peerKey: peerKey, responderKey: responderKey, key: key)

        let challenge = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_RESPONSE,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "status": AnyCodable("CHALLENGE"),
                "public_key": AnyCodable(responderKey),
                "pake_share": AnyCodable(party.share.base64EncodedString()),
                "pake_confirm": AnyCodable(Pake.confirmation(key: key, role: .responder).base64EncodedString())
            ]
        )
        tcpManager.send(packet: challenge, encrypt: false)
    }

    /// Message 3: the phone's confirmation shows it used the same PIN.
    private func handleHandshakeConfirm(_ packet: Packet) {
        guard connectionStatus != .connected,
              let pending = pendingPake, pending.request.senderId == packet.senderId else {
            logger.warning("⛔ Unexpected HANDSHAKE_CONFIRM, ignoring")
            return
        }
        pendingPake = nil
        guard let confirmB64 = packet.payload["pake_confirm"]?.value as? String,
              let confirmation = Data(base64Encoded: confirmB64),
              Pake.verifyConfirmation(confirmation, key: pending.key, role: .initiator) else {
            logger.warning("⛔ Wrong PIN (\(self.pinAttempts)/\(self.maxPinAttempts))")
            rejectHandshake(code: "BAD_PIN", reason: "PIN kodu hatalı")
            return
        }
        // Our key pair must still be the one the PAKE transcript covered.
        guard tcpManager.cryptoManager.publicKeyBase64() == pending.responderKey else {
            rejectHandshake(code: "BAD_KEY", reason: "Anahtar değişimi başarısız")
            return
        }
        pinAttempts = 0
        completePairing(pending.request, peerKey: pending.peerKey, secret: pending.key, isNewPairing: true)
        generatePairingCode() // a PIN is single-use
    }

    private func completePairing(_ incoming: Packet, peerKey: String, secret: Data, isNewPairing: Bool) {
        do {
            let key = try tcpManager.cryptoManager.decodePeerPublicKey(peerKey)
            try tcpManager.cryptoManager.deriveSharedSecret(peerPublicKey: key, authSecret: secret)
        } catch {
            logger.error("Key exchange failed: \(error.localizedDescription)")
            rejectHandshake(code: "BAD_KEY", reason: "Anahtar değişimi başarısız")
            return
        }

        // Response stays plaintext (the phone needs our public key to derive the same session key).
        let response = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_RESPONSE,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "status": AnyCodable("ACCEPTED"),
                "public_key": AnyCodable(tcpManager.cryptoManager.publicKeyBase64()),
                "device_name": AnyCodable(Host.current().localizedName ?? "Mac")
            ]
        )
        tcpManager.send(packet: response, encrypt: false)

        let deviceName = incoming.payload["device_name"]?.value as? String ?? "Bilinmeyen Android Cihaz"
        connectedDeviceName = deviceName
        connectionStatus = .connected
        errorMessage = nil

        let token = isNewPairing ? tcpManager.cryptoManager.deriveDeviceToken() : nil
        SettingsManager.shared.addKnownDevice(id: incoming.senderId, name: deviceName, token: token)
        logger.info("✅ Paired with \(incoming.senderId) (\(isNewPairing ? "PIN" : "token"))")

        updateWidgetData()
        startClipboardMonitoring()
        startHeartbeatMonitoring()

        // Bağlantı kurulduğunda hemen duvar kağıdını iste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestWallpaper()
        }
    }

    private func rejectHandshake(code: String, reason: String) {
        logger.warning("⛔ Handshake rejected: \(code)")
        let response = Packet(
            packetId: UUID().uuidString,
            type: .HANDSHAKE_RESPONSE,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "status": AnyCodable("REJECTED"),
                "reason_code": AnyCodable(code),
                "reason": AnyCodable(reason)
            ]
        )
        tcpManager.send(packet: response, encrypt: false)
        errorMessage = reason
        // Give the response a moment to flush, then free the slot for the next attempt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.connectionStatus != .connected else { return }
            self.tcpManager.disconnect()
            self.connectionStatus = .discovering
        }
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
        logger.info("Sent clipboard (\(text.count) chars)")
    }

    // MARK: - Incoming Packet Handling

    private func observeIncomingPackets() {
        tcpManager.$lastReceivedPacket
            .compactMap { $0 }
            .receive(on: DispatchQueue.main) // RunLoop.main stalls while menus are open or the user scrolls
            .sink { [weak self] packet in
                self?.handlePacket(packet)
            }
            .store(in: &cancellables)
    }

    private func handlePacket(_ packet: Packet) {
        logger.info("📩 Received packet type: \(packet.type.rawValue)")
        // Everything except the handshake requires an authenticated session.
        if !packet.type.isHandshake && connectionStatus != .connected {
            logger.warning("⛔ Ignoring \(packet.type.rawValue): not connected")
            return
        }
        switch packet.type {
        case .HANDSHAKE_REQUEST:
            handleHandshakeRequest(packet)

        case .HANDSHAKE_CONFIRM:
            handleHandshakeConfirm(packet)

        case .HANDSHAKE_RESPONSE:
            // The Mac only accepts sessions; it never sends a HANDSHAKE_REQUEST.
            logger.warning("⛔ Unexpected HANDSHAKE_RESPONSE, ignoring")

        case .CLIPBOARD_TRANSFER:
            // Android sends "content" (same key the Mac sends); "text" kept for older clients.
            if let content = (packet.payload["content"] ?? packet.payload["text"])?.value as? String {
                if isClipboardSyncEnabled {
                    DispatchQueue.main.async {
                        self.lastReceivedClipboard = content
                        self.clipboardMonitor.setClipboardContent(content)
                        self.logger.info("Received clipboard (\(content.count) chars)")
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

        case .FIND_PHONE, .MEDIA_COMMAND:
            break // Mac -> phone only

        case .MEDIA_STATE:
            handleMediaState(packet.payload)

        case .NOTIFICATION_REPLY:
            handleReplyResult(packet.payload)

        case .LINK_SHARE:
            handleIncomingLink(packet.payload)
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
        guard case .connected = connectionStatus else {
            showTransferMessage("Telefon bağlı değil")
            return
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            showTransferMessage("Klasör gönderilemez, dosya seçin")
            return
        }
        if let size = values?.fileSize, size > Self.maxFileSize {
            showTransferMessage("\(url.lastPathComponent) çok büyük (en fazla 7 MB)")
            return
        }
        let name = url.lastPathComponent
        showTransferMessage("Gönderiliyor: \(name)", autoHide: false)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= Self.maxFileSize else {
                    Task { @MainActor in self.showTransferMessage("\(name) çok büyük (en fazla 7 MB)") }
                    return
                }
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
                Task { @MainActor in self.showTransferMessage("Telefona gönderildi: \(name)") }
            } catch {
                self.logger.error("Failed to read file for transfer: \(error.localizedDescription)")
                Task { @MainActor in self.showTransferMessage("\(name) okunamadı") }
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
        let key = payload["key"]?.value as? String ?? ""
        let canReply = (payload["can_reply"]?.value as? Bool ?? false) && !key.isEmpty
        
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
            timestamp: Date(),
            key: key,
            canReply: canReply
        )
        notifications.insert(record, at: 0)
        if notifications.count > 200 { notifications.removeLast() }
        
        // Trigger native macOS notification
        triggerNativeNotification(appName: appName, title: title, body: body, replyKey: canReply ? key : nil)
        
        logger.info("🔔 Notification from \(appName)")
    }

    private func triggerNativeNotification(appName: String, title: String, body: String, replyKey: String? = nil) {
        if SettingsManager.shared.muteNotifications {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = appName
        content.subtitle = title
        content.body = body
        content.sound = .default
        if let replyKey = replyKey {
            content.categoryIdentifier = NotificationActionHandler.replyCategory
            content.userInfo = [NotificationActionHandler.keyInfo: replyKey]
        }
        
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

    // MARK: - Companion features

    private func sendToPhone(_ type: PacketType, _ payload: [String: Any] = [:]) {
        guard case .connected = connectionStatus else { return }
        let packet = Packet(
            packetId: UUID().uuidString,
            type: type,
            senderId: bonjourManager.deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload.mapValues { AnyCodable($0) }
        )
        tcpManager.send(packet: packet)
    }

    private func resetCompanionState() {
        media = nil
        isFindingPhone = false
        findPhoneResetWork?.cancel()
        replyStatus = [:]
    }

    /// Rings the phone (or stops it). The phone stops by itself after 30 s.
    func toggleFindPhone() {
        guard case .connected = connectionStatus else { return }
        isFindingPhone.toggle()
        sendToPhone(.FIND_PHONE, ["action": isFindingPhone ? "START" : "STOP"])
        findPhoneResetWork?.cancel()
        if isFindingPhone {
            let work = DispatchWorkItem { [weak self] in self?.isFindingPhone = false }
            findPhoneResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }

    func sendMediaCommand(_ action: String) {
        sendToPhone(.MEDIA_COMMAND, ["action": action])
    }

    private func handleMediaState(_ payload: [String: AnyCodable]) {
        let hasSession = payload["has_session"]?.value as? Bool ?? false
        guard hasSession else {
            media = nil
            return
        }
        func int(_ key: String) -> Int {
            let v = payload[key]?.value
            return (v as? Int) ?? (v as? Double).map(Int.init) ?? 0
        }
        // Art is only sent when the track changes; an empty string means "no art".
        var art = media?.art
        if let artB64 = payload["art"]?.value as? String {
            art = artB64.isEmpty ? nil : Data(base64Encoded: artB64).flatMap(NSImage.init(data:))
        }
        logger.info("🎵 Media state from phone (playing: \(payload["is_playing"]?.value as? Bool ?? false))")
        media = PhoneMediaState(
            title: payload["title"]?.value as? String ?? "",
            artist: payload["artist"]?.value as? String ?? "",
            album: payload["album"]?.value as? String ?? "",
            appName: payload["app_name"]?.value as? String ?? "",
            isPlaying: payload["is_playing"]?.value as? Bool ?? false,
            volume: int("volume"),
            maxVolume: int("max_volume"),
            art: art
        )
    }

    /// Answers a phone notification (from the app's list or the macOS banner).
    func replyToNotification(key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmed.isEmpty, case .connected = connectionStatus else { return }
        replyStatus[key] = .sending
        sendToPhone(.NOTIFICATION_REPLY, ["key": key, "text": trimmed])
    }

    private func handleReplyResult(_ payload: [String: AnyCodable]) {
        guard let key = payload["key"]?.value as? String else { return }
        let ok = (payload["status"]?.value as? String) == "SENT"
        logger.info("💬 Notification reply \(ok ? "delivered" : "failed") on phone")
        replyStatus[key] = ok ? .sent : .failed
        if ok {
            if let index = notifications.firstIndex(where: { $0.key == key }) {
                notifications[index].canReply = false // the phone allows one reply per notification
            }
        } else {
            triggerNativeNotification(appName: "Synapse", title: "Yanıt gönderilemedi", body: "Bildirim telefonda artık yok veya yanıtlanamıyor.")
        }
    }

    private static func webURL(_ string: String) -> URL? {
        guard string.count <= 4096,
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    /// The phone shared a link: open it in the default browser.
    private func handleIncomingLink(_ payload: [String: AnyCodable]) {
        guard let raw = payload["url"]?.value as? String, let url = Self.webURL(raw) else {
            logger.warning("⛔ Ignoring non-web link from phone")
            return
        }
        logger.info("🔗 Opening link from phone")
        NSWorkspace.shared.open(url)
    }

    /// Link from the Mac clipboard, if it holds one.
    var clipboardLink: URL? {
        NSPasteboard.general.string(forType: .string).flatMap(Self.webURL)
    }

    func sendLinkToPhone(_ string: String) {
        guard let url = Self.webURL(string) else {
            showTransferMessage("Geçerli bir http(s) linki değil")
            return
        }
        sendToPhone(.LINK_SHARE, ["url": url.absoluteString])
        showTransferMessage("Link telefona gönderildi")
    }

    func sendClipboardLinkToPhone() {
        guard let url = clipboardLink else {
            showTransferMessage("Panoda link yok")
            return
        }
        sendLinkToPhone(url.absoluteString)
    }

    func pickAndSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Telefona Gönder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(sendFile(url:))
    }

    /// Drop handler shared by the main window and the menu bar popover.
    func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                Task { @MainActor in
                    if url.isFileURL { self.sendFile(url: url) } else { self.sendLinkToPhone(url.absoluteString) }
                }
            }
        }
        return true
    }

    func showTransferMessage(_ message: String, autoHide: Bool = true) {
        transferMessage = message
        transferMessageWork?.cancel()
        guard autoHide else { return }
        let work = DispatchWorkItem { [weak self] in self?.transferMessage = nil }
        transferMessageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - Disconnect

    func disconnect() {
        clipboardMonitor.stopMonitoring()
        stopHeartbeatMonitoring()
        tcpManager.disconnect()
        connectionStatus = .disconnected
        connectedDeviceName = nil
        lastReceivedClipboard = nil
        resetCompanionState()
    }

    func clearError() {
        errorMessage = nil
    }
}
