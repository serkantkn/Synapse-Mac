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

    /// Frames in a row that failed to decrypt (reset on success and on a new connection).
    private var consecutiveDecryptFailures = 0

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Server

    /// Accept incoming connections from the NWListener.
    func acceptConnections(from bonjourListener: NWListener) {
        bonjourListener.newConnectionHandler = { [weak self] newConnection in
            guard let self = self else { newConnection.cancel(); return }
            self.logger.info("📥 Incoming connection from \(String(describing: newConnection.endpoint))")
            // One peer at a time: don't let a second LAN host silently replace the active session.
            // A dead peer is dropped by the heartbeat timeout, which frees the slot.
            if self.connection != nil && !self.isDisconnecting {
                self.logger.warning("⚠️ Connection already active. Rejecting new one.")
                newConnection.cancel()
                return
            }
            self.setupConnection(newConnection)
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
        self.consecutiveDecryptFailures = 0

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
                // An unauthenticated peer must not hold the single connection slot forever.
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak conn] in
                    guard let self = self, let conn = conn, self.connection === conn,
                          self.cryptoManager.sharedSymmetricKey == nil else { return }
                    self.logger.warning("⏱️ No completed handshake within 10s — dropping connection")
                    self.handleConnectionLost()
                }
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
            if encrypt {
                // Never fall back to plaintext: without a session key the packet is not sent.
                guard cryptoManager.sharedSymmetricKey != nil else {
                    logger.warning("⛔ Not sending \(packet.type.rawValue): no secure session yet")
                    return
                }
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
                    let icon = encrypt ? "🔒" : "🔓"
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
                    // Stream is out of sync; continuing would misread every later frame.
                    self.logger.error("Invalid header data — dropping connection")
                    self.handleConnectionLost()
                }
                return
            }

            let length = headerData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }

            guard length > 0, length <= 10_000_000 else {
                self.logger.error("Invalid packet length: \(length) — dropping connection")
                self.handleConnectionLost()
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

                guard let payloadData = payloadData, payloadData.count == Int(length) else {
                    self.logger.error("Incomplete payload — dropping connection")
                    self.handleConnectionLost()
                    return
                }

                let jsonData: Data
                let isEncrypted = self.cryptoManager.sharedSymmetricKey != nil
                do {
                    if isEncrypted {
                        jsonData = try self.cryptoManager.decrypt(payloadData)
                    } else {
                        jsonData = payloadData
                    }
                    self.consecutiveDecryptFailures = 0
                } catch {
                    self.consecutiveDecryptFailures += 1
                    if self.consecutiveDecryptFailures >= 3 {
                        // A peer that keeps sending undecryptable frames doesn't share our key.
                        self.logger.error("⛔ Repeated decrypt failures — dropping connection")
                        self.handleConnectionLost()
                        return
                    }
                    // Never treat an undecryptable frame as plaintext: that would let anyone inject
                    // unencrypted packets into an encrypted session. Skip it (framing is still intact;
                    // e.g. a packet the peer sent before it received our handshake response).
                    self.logger.warning("⚠️ Decrypt failed, dropping frame: \(error.localizedDescription)")
                    self.receiveNextPacket()
                    return
                }

                DispatchQueue.main.async {
                    // Update timestamp regardless to prevent heartbeat timeout
                    self.lastPacketReceivedAt = Date()
                    
                    do {
                        let packet = try self.decoder.decode(Packet.self, from: jsonData)
                        // Plaintext is only allowed for the handshake itself.
                        if !isEncrypted && packet.type != .HANDSHAKE_REQUEST && packet.type != .HANDSHAKE_RESPONSE {
                            self.logger.warning("⛔ Dropped plaintext \(packet.type.rawValue) before the secure session")
                            return
                        }
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
