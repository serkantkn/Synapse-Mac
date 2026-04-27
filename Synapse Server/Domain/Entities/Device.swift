//
//  Device.swift
//  Synapse Server
//

import Foundation

/// Represents a discovered device on the local network.
struct Device: Identifiable, Hashable {
    let id: String
    let name: String
    let deviceType: String   // "macOS" or "android"
    let ipAddress: String
    let port: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
}

/// Connection lifecycle states.
enum ConnectionStatus: Equatable {
    case disconnected
    case discovering
    case connecting
    case pairing
    case connected
    case error(String)
}
