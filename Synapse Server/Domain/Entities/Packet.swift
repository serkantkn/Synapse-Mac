//
//  PacketType.swift
//  Synapse Server
//

import Foundation

/// All packet types exchanged over the wire.
enum PacketType: String, Codable {
    case HANDSHAKE_REQUEST
    case HANDSHAKE_RESPONSE
    case CLIPBOARD_TRANSFER
    case HEARTBEAT
    case CALL_EVENT
    case SMS_EVENT
    case CALL_COMMAND
    case SMS_COMMAND
    case WALLPAPER_TRANSFER
    case NOTIFICATION_EVENT
    case SCREEN_STREAM_COMMAND
    case SCREEN_FRAME
    case REMOTE_INPUT
}

/// Base packet envelope — matches the Android JSON schema exactly.
struct Packet: Codable {
    let packetId: String
    let type: PacketType
    let senderId: String
    let timestamp: Int64
    let payload: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case packetId = "packet_id"
        case type
        case senderId = "sender_id"
        case timestamp
        case payload
    }
}

/// A type-erased Codable wrapper so we can handle arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else if let arrVal = try? container.decode([AnyCodable].self) {
            value = arrVal.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let dictVal as [String: Any]:
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        case let arrVal as [Any]:
            try container.encode(arrVal.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
