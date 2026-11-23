import Foundation

/// Wire format for the band's private Bluetooth service.
///
/// Every message is a frame:
/// `aa 01 <len u16 LE> 00 01 <crc16 header> <payload…> <crc32 payload LE>`
/// where `len` counts the payload plus its 4-byte CRC.
public enum BandProtocol {
  public static let serviceUUID = "fd4b0001-cce1-4033-93ce-002d5875f58a"
  public static let commandCharacteristicUUID = "fd4b0002-cce1-4033-93ce-002d5875f58a"
  public static let commandResponseCharacteristicUUID = "fd4b0003-cce1-4033-93ce-002d5875f58a"
  public static let eventCharacteristicUUID = "fd4b0004-cce1-4033-93ce-002d5875f58a"
  public static let dataCharacteristicUUID = "fd4b0005-cce1-4033-93ce-002d5875f58a"

  /// Fixed client hello the band expects before it accepts commands.
  public static let helloFrame = Data([
    0xaa, 0x01, 0x08, 0x00, 0x00, 0x01, 0xe6, 0x71,
    0x23, 0x01, 0x91, 0x01, 0x36, 0x3e, 0x5c, 0x8d,
  ])

  public enum PacketType: UInt8 {
    case command = 35
    case commandResponse = 36
    case realtimeData = 40
    case event = 48
    case metadata = 49
  }

  public enum Command: UInt8, Sendable {
    /// Payload `[1]` starts a 1 Hz heart-rate stream on the data characteristic, `[0]` stops it.
    case toggleRealtimeHeartRate = 3
    /// Payload `[1]` turns on the standard Bluetooth heart-rate profile (0x180D / 0x2A37),
    /// so apps like Strava can pair with the band as a normal heart-rate sensor.
    case toggleStandardHeartRateBroadcast = 14
  }

  public static let headerLength = 8

  public static func commandFrame(sequence: UInt8, command: Command, data: [UInt8]) -> Data {
    var payload: [UInt8] = [PacketType.command.rawValue, sequence, command.rawValue] + data
    while payload.count % 4 != 0 { payload.append(0) }
    let payloadCRC = CRC.crc32(payload)
    let declared = UInt16(payload.count + 4)
    var frame: [UInt8] = [0xaa, 0x01, UInt8(declared & 0xff), UInt8(declared >> 8), 0x00, 0x01]
    let headerCRC = CRC.crc16Modbus(frame)
    frame += [UInt8(headerCRC & 0xff), UInt8(headerCRC >> 8)]
    frame += payload
    frame += withUnsafeBytes(of: payloadCRC.littleEndian, Array.init)
    return Data(frame)
  }

  /// Returns the payload of a complete, CRC-valid frame, or nil.
  public static func validatedPayload(_ frame: Data) -> [UInt8]? {
    let bytes = [UInt8](frame)
    guard bytes.count >= headerLength + 4, bytes[0] == 0xaa else { return nil }
    let declared = Int(bytes[2]) | Int(bytes[3]) << 8
    guard declared >= 4, bytes.count == headerLength + declared else { return nil }
    let headerCRC = UInt16(bytes[6]) | UInt16(bytes[7]) << 8
    guard CRC.crc16Modbus(Array(bytes[0..<6])) == headerCRC else { return nil }
    let payload = Array(bytes[headerLength..<(bytes.count - 4)])
    let tail = bytes[(bytes.count - 4)...]
    let crc = tail.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    guard CRC.crc32(payload) == crc else { return nil }
    return payload
  }

  /// Decodes a realtime heart-rate packet.
  ///
  /// Payload layout (observed on WHOOP 5.0, firmware Nov 2026):
  /// `28 02 <unix seconds u32 LE> <2 bytes subsec> <bpm u8> <rr count u8> <rr ms u16 LE>×count …`
  public static func decodeRealtimeHeartRate(_ frame: Data) -> HeartRateReading? {
    guard let p = validatedPayload(frame),
          p.count >= 10,
          p[0] == PacketType.realtimeData.rawValue
    else { return nil }
    let seconds = UInt32(p[2]) | UInt32(p[3]) << 8 | UInt32(p[4]) << 16 | UInt32(p[5]) << 24
    let bpm = Int(p[8])
    let rrCount = Int(p[9])
    guard (25...240).contains(bpm), rrCount <= 6, p.count >= 10 + rrCount * 2 else { return nil }
    var rr: [Int] = []
    for i in 0..<rrCount {
      let ms = Int(p[10 + 2 * i]) | Int(p[11 + 2 * i]) << 8
      if (250...2500).contains(ms) { rr.append(ms) }
    }
    return HeartRateReading(
      bandTime: Date(timeIntervalSince1970: TimeInterval(seconds)),
      bpm: bpm,
      rrIntervalsMS: rr
    )
  }

  /// Command responses carry `24 <band seq> <command> <our seq> <status> …`; status 1 means accepted.
  public static func commandResponse(_ frame: Data) -> (sequence: UInt8, command: UInt8, accepted: Bool)? {
    guard let p = validatedPayload(frame), p.count >= 5,
          p[0] == PacketType.commandResponse.rawValue else { return nil }
    return (p[3], p[2], p[4] == 1)
  }
}

public struct HeartRateReading: Sendable, Equatable, Codable {
  public let bandTime: Date
  public let bpm: Int
  public let rrIntervalsMS: [Int]

  public init(bandTime: Date, bpm: Int, rrIntervalsMS: [Int]) {
    self.bandTime = bandTime
    self.bpm = bpm
    self.rrIntervalsMS = rrIntervalsMS
  }
}

public enum CRC {
  public static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0xffff
    for b in bytes {
      crc ^= UInt16(b)
      for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xa001 : crc >> 1 }
    }
    return crc
  }

  public static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for b in bytes {
      crc ^= UInt32(b)
      for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
    }
    return ~crc
  }
}
