//
//  BonjourManager.swift
//  Synapse Server
//
//  Manages Bonjour service publishing and browsing using Network.framework.
//

import Foundation
import Network
import Combine
import os.log

/// Manages mDNS/Bonjour service advertising and discovery.
final class BonjourManager: ObservableObject {

    private let logger = Logger(subsystem: "com.serkantkn.synapse-server", category: "Bonjour")

    /// Service type matching the Android side exactly.
    static let serviceType = "_synapse._tcp"

    private var listener: NWListener?
    private var browser: NWBrowser?

    @Published var discoveredDevices: [Device] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false

    /// The port this listener is bound to.
    var listenerPort: UInt16? {
        listener?.port?.rawValue
    }

    private(set) lazy var deviceId: String = {
        if let id = UserDefaults.standard.string(forKey: "synapse_device_id") {
            return id
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "synapse_device_id")
        return id
    }()

    // MARK: - Service Publishing

    /// Start advertising this Mac as a Synapse server on the local network.
    func startAdvertising(port: UInt16) {
        logger.info("Starting advertising on port \(port) with type '\(BonjourManager.serviceType)'")

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        // Create a listener on the given port
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("❌ Failed to create listener: \(error.localizedDescription)")
            return
        }

        // Advertise via Bonjour
        let deviceName = Host.current().localizedName ?? "Mac"
        let txtRecord = NWTXTRecord([
            "device_id": deviceId,
            "device_type": "macOS",
            "device_name": deviceName
        ])

        listener?.service = NWListener.Service(
            name: "Synapse-Mac",
            type: BonjourManager.serviceType,
            txtRecord: txtRecord
        )

        logger.info("Service configured: name='Synapse-Mac', type='\(BonjourManager.serviceType)', deviceName='\(deviceName)'")

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let actualPort = self?.listener?.port?.rawValue ?? 0
                self?.logger.info("✅ Listener ready on port \(actualPort)")
                DispatchQueue.main.async { self?.isAdvertising = true }
            case .failed(let error):
                self?.logger.error("❌ Listener failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.isAdvertising = false }
            case .cancelled:
                self?.logger.info("Listener cancelled")
                DispatchQueue.main.async { self?.isAdvertising = false }
            case .waiting(let error):
                self?.logger.warning("⚠️ Listener waiting: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    /// Stop advertising.
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isAdvertising = false }
    }

    // MARK: - Service Browsing

    /// Start browsing for other Synapse devices on the network.
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: BonjourManager.serviceType, domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }

            var devices: [Device] = []
            for result in results {
                if case .service(let name, let type, _, _) = result.endpoint {
                    // We'll resolve later via NWConnection
                    let device = Device(
                        id: name,
                        name: name,
                        deviceType: "unknown",
                        ipAddress: "",
                        port: 0
                    )
                    devices.append(device)
                    self.logger.info("Found service: \(name) (\(type))")
                }
            }

            DispatchQueue.main.async {
                self.discoveredDevices = devices
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Browser ready")
                DispatchQueue.main.async { self?.isBrowsing = true }
            case .failed(let error):
                self?.logger.error("Browser failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.isBrowsing = false }
            case .cancelled:
                DispatchQueue.main.async { self?.isBrowsing = false }
            default:
                break
            }
        }

        browser?.start(queue: .global(qos: .userInitiated))
    }

    /// Stop browsing.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async {
            self.isBrowsing = false
            self.discoveredDevices = []
        }
    }

    /// Get the NWListener for incoming connections (used by TcpConnectionManager).
    func getListener() -> NWListener? {
        return listener
    }

    deinit {
        stopAdvertising()
        stopBrowsing()
    }
}
