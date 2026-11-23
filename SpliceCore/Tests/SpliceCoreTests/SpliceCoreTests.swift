import Foundation
import Testing
@testable import SpliceCore

private func data(_ hex: String) -> Data {
  var bytes: [UInt8] = []
  var i = hex.startIndex
  while i < hex.endIndex {
    let j = hex.index(i, offsetBy: 2)
    bytes.append(UInt8(hex[i..<j], radix: 16)!)
    i = j
  }
  return Data(bytes)
}

// Frames captured from a WHOOP 5.0 band on 23 Nov 2026.
private let realtimeTwoRR = "aa011800010022e12802657b046b0a5764027502620200000000010071239891"
private let realtimeOneRR = "aa011800010022e12802667b046b0a5765016e0200000000000001008d1846a3"
private let hrOnAck = "aa010c00010027112476034101000000e6321dcc"

@Suite struct BandProtocolTests {
  @Test func encodesRealtimeHeartRateCommandExactlyAsTheBandAccepted() {
    let frame = BandProtocol.commandFrame(sequence: 65, command: .toggleRealtimeHeartRate, data: [1])
    #expect(frame == data("aa0108000001e671234103016e5bb1be"))
  }

  @Test func encodesBroadcastCommandExactlyAsTheBandAccepted() {
    let frame = BandProtocol.commandFrame(sequence: 65, command: .toggleStandardHeartRateBroadcast, data: [1])
    #expect(frame == data("aa0108000001e67123410e0123251f0b"))
    // The band acknowledged it with status 1.
    let ack = BandProtocol.commandResponse(data("aa010c000100271124910e4101000000a1b984b6"))
    #expect(ack?.command == 14)
    #expect(ack?.accepted == true)
  }

  @Test func decodesBpmTimestampAndBeatIntervals() throws {
    let reading = try #require(BandProtocol.decodeRealtimeHeartRate(data(realtimeTwoRR)))
    #expect(reading.bpm == 100)
    #expect(reading.rrIntervalsMS == [629, 610])
    #expect(reading.bandTime == Date(timeIntervalSince1970: 0x6b04_7b65))
  }

  @Test func decodesSingleBeatInterval() throws {
    let reading = try #require(BandProtocol.decodeRealtimeHeartRate(data(realtimeOneRR)))
    #expect(reading.bpm == 101)
    #expect(reading.rrIntervalsMS == [622])
  }

  @Test func rejectsCorruptedFrames() {
    var corrupt = [UInt8](data(realtimeTwoRR))
    corrupt[16] ^= 0xff
    #expect(BandProtocol.decodeRealtimeHeartRate(Data(corrupt)) == nil)
    #expect(BandProtocol.decodeRealtimeHeartRate(data(String(realtimeTwoRR.dropLast(8)))) == nil)
  }

  @Test func ignoresNonHeartRateFrames() {
    #expect(BandProtocol.decodeRealtimeHeartRate(data(hrOnAck)) == nil)
  }

  @Test func parsesCommandAcknowledgement() throws {
    let ack = try #require(BandProtocol.commandResponse(data(hrOnAck)))
    #expect(ack.command == 3)
    #expect(ack.sequence == 65)
    #expect(ack.accepted)
    // The band refused command 63 with status 3.
    let refused = try #require(BandProtocol.commandResponse(data("aa010c000100271124773f4203000000df4c7bf4")))
    #expect(!refused.accepted)
  }

  @Test func helloFrameIsWellFormed() {
    #expect(BandProtocol.validatedPayload(BandProtocol.helloFrame) != nil)
  }
}

@Suite struct ZoneTests {
  let zones = HeartRateZones(maxHeartRate: 190)

  @Test func classifiesByPercentOfMax() {
    #expect(zones.zone(for: 100) == 0)
    #expect(zones.zone(for: 114) == 1)
    #expect(zones.zone(for: 133) == 2)
    #expect(zones.zone(for: 152) == 3)
    #expect(zones.zone(for: 171) == 4)
    #expect(zones.zone(for: 200) == 4)
  }

  @Test func timeInZonesCapsGaps() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let samples = [
      HeartRateSample(time: t0, bpm: 100),
      HeartRateSample(time: t0.addingTimeInterval(1), bpm: 100),
      HeartRateSample(time: t0.addingTimeInterval(2), bpm: 160),
      HeartRateSample(time: t0.addingTimeInterval(60), bpm: 160),
    ]
    let totals = zones.timeInZones(samples, endedAt: t0.addingTimeInterval(61))
    #expect(totals[0] == 2)
    #expect(totals[3] == 6)
  }
}

@Suite struct TCXTests {
  func sampleWorkout() -> Workout {
    let t0 = Date(timeIntervalSince1970: 1_795_455_844)
    var w = Workout(sport: .run, startedAt: t0, maxHeartRateSetting: 190)
    for i in 0..<10 {
      w.heartRate.append(HeartRateSample(time: t0.addingTimeInterval(Double(i)), bpm: 120 + i))
    }
    w.locations = [
      LocationSample(time: t0, latitude: 51.5, longitude: -0.12, altitude: 10, horizontalAccuracy: 5),
      LocationSample(time: t0.addingTimeInterval(5), latitude: 51.5001, longitude: -0.12, altitude: 10, horizontalAccuracy: 5),
      LocationSample(time: t0.addingTimeInterval(6), latitude: 52.0, longitude: -0.12, altitude: 10, horizontalAccuracy: 500),
    ]
    w.endedAt = t0.addingTimeInterval(10)
    return w
  }

  @Test func writesHeartRateOnEveryTrackpointAndParsesAsXML() throws {
    let xml = TCXWriter.document(for: sampleWorkout())
    #expect(xml.contains("<Activity Sport=\"Running\">"))
    #expect(xml.contains("<Id>2026-11-23T"))
    #expect(xml.components(separatedBy: "<HeartRateBpm>").count - 1 == 10)
    #expect(xml.contains("<AverageHeartRateBpm><Value>125</Value>"))
    #expect(xml.contains("<MaximumHeartRateBpm><Value>129</Value>"))
    #expect(!xml.contains("52.0000000"), "inaccurate GPS fix must be dropped")
    let parser = XMLParser(data: Data(xml.utf8))
    #expect(parser.parse())
  }

  @Test func distanceIgnoresInaccurateFixes() {
    let d = sampleWorkout().distanceMeters
    #expect(d > 10 && d < 12)
  }

  @Test func descriptionListsZones() {
    let text = WorkoutSummary.stravaDescription(for: sampleWorkout())
    #expect(text.contains("Avg 125 bpm"))
    #expect(text.contains("Z2 Endurance"))
  }
}
