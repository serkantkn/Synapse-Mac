//
//  TcpConnectionManager.swift
//  Synapse Server
//
//  Handles TCP connections using NWConnection with 4-byte length-prefixed framing.
//

import Foundation
import Network
import Combine
import os.log

/// Manages TCP connections for sending and receiving Synapse packets.
final class TcpConnectionManager: ObservableObject {

    private let logger = Logger(subsystem: "com.serkantkn.synapse-server", category: "TCP")

    private var connection: NWConnection?

    let cryptoManager = CryptoManager()

    /// Published incoming packets for UI observation.
    @Published var lastReceivedPacket: Packet?
    @Published var isConnected = false

    /// Timestamp of the last received packet (any type).
    @Published var lastPacketReceivedAt: Date?

    /// Callback fired when the connection is lost.
    var onDisconnected: (() -> Void)?

    /// Guard to prevent re-entrant disconnect calls.
    private var isDisconnecting = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Server

    /// Accept incoming connections from the NWListener.
    func acceptConnections(from bonjourListener: NWListener) {
        bonjourListener.newConnectionHandler = { [weak self] newConnection in
            self?.logger.info("📥 Incoming connection from \(String(describing: newConnection.endpoint))")
            self?.setupConnection(newConnection)
        }
    }

    // MARK: - Client

    /// Actively connect to a remote device.
    func connect(to host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let params = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: params)
        setupConnection(conn)
    }

    // MARK: - Connection Lifecycle

    private func setupConnection(_ conn: NWConnection) {
        // Clean up old connection if any
        if let old = self.connection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        
        self.connection = conn
        self.isDisconnecting = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.info("✅ Connection ready")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.lastPacketReceivedAt = Date()
                }
                self.receiveNextPacket()
            case .failed(let error):
                self.logger.error("❌ Connection failed: \(error.localizedDescription)")
                self.handleConnectionLost()
            case .cancelled:
                self.logger.info("Connection cancelled")
                // Don't call handleConnectionLost here - cancellation is deliberate
            case .waiting(let error):
                self.logger.warning("⚠️ Connection waiting: \(error.localizedDescription)")
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    /// Called when the connection is lost unexpectedly.
    private func handleConnectionLost() {
        // Guard against re-entrant calls
        guard !isDisconnecting else { return }
        isDisconnecting = true
        
        logger.info("🔌 Handling connection loss...")
        
        // Nullify the state handler to prevent further callbacks
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        cryptoManager.resetSharedSecret()
        
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.lastPacketReceivedAt = nil
            self?.onDisconnected?()
        }
    }

    // MARK: - Sending

    /// Send a Packet to the connected peer.
    func send(packet: Packet, encrypt: Bool = true) {
        guard let conn = connection else {
            logger.warning("⚠️ Cannot send: no active connection")
            return
        }

        do {
            let jsonData = try encoder.encode(packet)

            let dataToSend: Data
            if encrypt, cryptoManager.sharedSymmetricKey != nil {
                dataToSend = try cryptoManager.encrypt(jsonData)
            } else {
                dataToSend = jsonData
            }

            // 4-byte big-endian length prefix
            let length = UInt32(dataToSend.count).bigEndian
            let frameData = withUnsafeBytes(of: length) { Data($0) }
            var finalData = frameData
            finalData.append(dataToSend)

            conn.send(content: finalData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.logger.error("❌ Send error: \(error.localizedDescription)")
                } else {
                    let icon = encrypt ? (self?.cryptoManager.sharedSymmetricKey != nil ? "🔒" : "🔓") : "🔓"
                    self?.logger.info("\(icon) Sent: \(packet.type.rawValue) (\(dataToSend.count) bytes)")
                }
            })
        } catch {
            logger.error("❌ Encode/encrypt error: \(error.localizedDescription)")
        }
    }

    // MARK: - Receiving

    private func receiveNextPacket() {
        guard let conn = connection, !isDisconnecting else { return }

        // Read 4-byte length header
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] headerData, _, isComplete, error in
            guard let self = self, !self.isDisconnecting else { return }

            if let error = error {
                self.logger.error("Receive header error: \(error.localizedDescription)")
                self.handleConnectionLost()
                return
            }

            // If no data AND isComplete → remote closed
            guard let headerData = headerData, headerData.count == 4 else {
                if isComplete {
                    self.logger.info("🔌 Remote side closed the connection")
                    self.handleConnectionLost()
                } else {
                    self.logger.error("Invalid header data — retrying...")
                    self.receiveNextPacket()
                }
                return
            }

            let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            guard length > 0, length < 10_000_000 else {
                self.logger.error("Invalid packet length: \(length)")
                self.receiveNextPacket()
                return
            }

            // Read the payload
            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payloadData, _, _, error in
                guard let self = self, !self.isDisconnecting else { return }

                if let error = error {
                    self.logger.error("Receive payload error: \(error.localizedDescription)")
                    self.handleConnectionLost()
                    return
                }

                guard let payloadData = payloadData else {
                    self.logger.error("No payload data received")
                    self.receiveNextPacket()
                    return
                }

                // Try to decrypt/decode, with plaintext fallback
                var jsonData: Data
                do {
                    if self.cryptoManager.sharedSymmetricKey != nil {
                        jsonData = try self.cryptoManager.decrypt(payloadData)
                    } else {
                        jsonData = payloadData
                    }
                } catch {
                    // Decrypt failed — try plaintext fallback (e.g. heartbeat sent before key was ready)
                    self.logger.warning("⚠️ Decrypt failed, trying plaintext fallback: \(error.localizedDescription)")
                    jsonData = payloadData
                }

                DispatchQueue.main.async {
                    // Update timestamp regardless to prevent heartbeat timeout
                    self.lastPacketReceivedAt = Date()
                    
                    do {
                        let packet = try self.decoder.decode(Packet.self, from: jsonData)
                        self.logger.info("⬇️ Received: \(packet.type.rawValue)")
                        self.lastReceivedPacket = packet
                    } catch {
                        self.logger.error("Decode error: \(error.localizedDescription)")
                    }
                }

                // Continue listening
                self.receiveNextPacket()
            }
        }
    }

    // MARK: - Disconnect

    /// Deliberately disconnect (user-initiated).
    func disconnect() {
        isDisconnecting = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        cryptoManager.resetSharedSecret()
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastPacketReceivedAt = nil
        }
    }

    deinit {
        disconnect()
    }
}
