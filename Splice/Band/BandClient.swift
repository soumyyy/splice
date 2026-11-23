import CoreBluetooth
import Foundation
import os
import SpliceCore

/// Owns the Bluetooth link to the band: finds it, reconnects forever, and keeps the 1 Hz heart-rate stream on.
@MainActor
@Observable
final class BandClient: NSObject {
  enum Status: Equatable {
    case bluetoothOff
    case unauthorized
    case searching
    case connecting
    case connected
    case streaming
  }

  private(set) var status: Status = .searching {
    didSet {
      guard status != oldValue else { return }
      debugTrace("band status \(status)")
      if status == .streaming { searchTimedOut = false }
    }
  }

  /// True once a band has connected on this phone; Splice reconnects to it automatically.
  private(set) var hasSavedBand = UserDefaults.standard.string(forKey: "splice.band.identifier") != nil

  /// Set when connecting has taken longer than expected, so the UI can offer help.
  private(set) var searchTimedOut = false
  /// The name the band advertises over Bluetooth, e.g. "WHOOP 5B00233988". Strava lists it by this name.
  private(set) var bandName: String?

  /// Friendly name shown in the app.
  var displayName: String { "WHOOP 5" }

  /// The serial part of the Bluetooth name, e.g. "5B00233988".
  var serial: String? {
    guard let bandName, bandName.hasPrefix("WHOOP ") else { return nil }
    return String(bandName.dropFirst("WHOOP ".count))
  }
  private(set) var batteryPercent: Int?
  private(set) var lastReadingAt: Date?

  /// Called for every decoded reading with the phone time it arrived.
  @ObservationIgnored var onReading: ((HeartRateReading, Date) -> Void)?

  /// The user's streaming switch. When off, the band stops broadcasting (saves band battery).
  var wantsStream = UserDefaults.standard.object(forKey: "splice.streaming") as? Bool ?? true {
    didSet {
      guard wantsStream != oldValue else { return }
      UserDefaults.standard.set(wantsStream, forKey: "splice.streaming")
      wantsStream ? startStream() : stopStream()
    }
  }

  private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "band")
  private let savedBandKey = "splice.band.identifier"
  private let serviceID = CBUUID(string: BandProtocol.serviceUUID)
  private let commandID = CBUUID(string: BandProtocol.commandCharacteristicUUID)
  private let responseID = CBUUID(string: BandProtocol.commandResponseCharacteristicUUID)
  private let dataID = CBUUID(string: BandProtocol.dataCharacteristicUUID)
  private let batteryServiceID = CBUUID(string: "180F")
  private let batteryLevelID = CBUUID(string: "2A19")

  @ObservationIgnored private var central: CBCentralManager!
  @ObservationIgnored private var band: CBPeripheral?
  @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
  @ObservationIgnored private var sequence: UInt8 = 0
  @ObservationIgnored private var lastStreamRequestAt = Date.distantPast
  @ObservationIgnored private var watchdog: Timer?

  override init() {
    super.init()
    central = CBCentralManager(
      delegate: self,
      queue: .main,
      options: [CBCentralManagerOptionRestoreIdentifierKey: "splice.central"]
    )
    watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkStream() }
    }
  }

  @ObservationIgnored private var timeoutTask: Task<Void, Never>?

  /// Tries to reach the band right away, e.g. when the app opens. Safe to call any time.
  func reconnectNow() {
    guard central.state == .poweredOn, status != .streaming else { return }
    if let band, band.state == .connecting {
      // Restart a stale pending connection so the attempt is fresh.
      central.cancelPeripheralConnection(band)
      central.connect(band)
    } else {
      beginSearch()
    }
    startTimeout()
  }

  private func startTimeout() {
    searchTimedOut = false
    timeoutTask?.cancel()
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard let self, !Task.isCancelled, self.status != .streaming else { return }
      self.searchTimedOut = true
    }
  }

  /// Forget the paired band and look for a new one.
  func forgetBand() {
    if let band { central.cancelPeripheralConnection(band) }
    UserDefaults.standard.removeObject(forKey: savedBandKey)
    hasSavedBand = false
    band = nil
    bandName = nil
    batteryPercent = nil
    beginSearch()
    startTimeout()
  }

  // MARK: - Connection

  private func beginSearch() {
    guard central.state == .poweredOn else { return }
    if let band, band.state == .connected || band.state == .connecting { return }

    if let saved = UserDefaults.standard.string(forKey: savedBandKey).flatMap(UUID.init(uuidString:)),
       let known = central.retrievePeripherals(withIdentifiers: [saved]).first {
      // A pending connect never times out, so the band reconnects whenever it comes back in range.
      attach(known)
      return
    }
    if let connected = central.retrieveConnectedPeripherals(withServices: [serviceID]).first {
      attach(connected)
      return
    }
    status = .searching
    central.scanForPeripherals(withServices: [serviceID])
  }

  private func attach(_ peripheral: CBPeripheral) {
    central.stopScan()
    band = peripheral
    peripheral.delegate = self
    bandName = peripheral.name
    status = .connecting
    if peripheral.state == .connected {
      peripheral.discoverServices([serviceID, batteryServiceID])
    } else {
      central.connect(peripheral)
    }
  }

  // MARK: - Streaming

  private func send(_ command: BandProtocol.Command, _ data: [UInt8]) {
    guard let band, let commandCharacteristic else { return }
    sequence &+= 1
    let frame = BandProtocol.commandFrame(sequence: sequence, command: command, data: data)
    band.writeValue(frame, for: commandCharacteristic, type: writeType(commandCharacteristic))
  }

  private func writeType(_ c: CBCharacteristic) -> CBCharacteristicWriteType {
    c.properties.contains(.write) ? .withResponse : .withoutResponse
  }

  private func startStream() {
    guard wantsStream, let band, let commandCharacteristic else { return }
    lastStreamRequestAt = Date()
    band.writeValue(BandProtocol.helloFrame, for: commandCharacteristic, type: writeType(commandCharacteristic))
    // Keep the band visible to Strava and other apps as a standard heart-rate sensor.
    send(.toggleStandardHeartRateBroadcast, [1])
    send(.toggleRealtimeHeartRate, [1])
    log.info("requested realtime heart rate")
  }

  private func stopStream() {
    send(.toggleRealtimeHeartRate, [0])
    send(.toggleStandardHeartRateBroadcast, [0])
    lastReadingAt = nil
    if status == .streaming { status = .connected }
  }

  /// Re-arms the stream if readings stop arriving while connected.
  private func checkStream() {
    guard wantsStream, band?.state == .connected, commandCharacteristic != nil else { return }
    let now = Date()
    if let lastReadingAt, now.timeIntervalSince(lastReadingAt) < 5 { return }
    if status == .streaming { status = .connected }
    if now.timeIntervalSince(lastStreamRequestAt) >= 6 { startStream() }
  }

  private func handleData(_ value: Data) {
    guard wantsStream, let reading = BandProtocol.decodeRealtimeHeartRate(value) else { return }
    let now = Date()
    lastReadingAt = now
    if status != .streaming { status = .streaming }
    onReading?(reading, now)
    debugTrace("hr \(reading.bpm) rr \(reading.rrIntervalsMS)")
  }
}

// MARK: - CBCentralManagerDelegate

extension BandClient: CBCentralManagerDelegate {
  nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    MainActor.assumeIsolated {
      if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
        log.info("restored band after relaunch")
        band = restored
        restored.delegate = self
        bandName = restored.name
      }
    }
  }

  nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
    MainActor.assumeIsolated {
      switch central.state {
      case .poweredOn:
        if let band { attach(band) } else { beginSearch() }
      case .unauthorized:
        status = .unauthorized
      default:
        status = .bluetoothOff
        commandCharacteristic = nil
      }
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
    MainActor.assumeIsolated {
      log.info("found \(peripheral.name ?? "band", privacy: .public)")
      attach(peripheral)
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    MainActor.assumeIsolated {
      UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedBandKey)
      hasSavedBand = true
      bandName = peripheral.name
      status = .connected
      peripheral.discoverServices([serviceID, batteryServiceID])
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    MainActor.assumeIsolated {
      log.error("connect failed: \(String(describing: error), privacy: .public)")
      central.connect(peripheral)
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    MainActor.assumeIsolated {
      log.info("disconnected; reconnecting")
      commandCharacteristic = nil
      lastReadingAt = nil
      status = .connecting
      central.connect(peripheral)
    }
  }
}

// MARK: - CBPeripheralDelegate

extension BandClient: CBPeripheralDelegate {
  nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    MainActor.assumeIsolated {
      for service in peripheral.services ?? [] {
        if service.uuid == serviceID {
          peripheral.discoverCharacteristics([commandID, responseID, dataID], for: service)
        } else if service.uuid == batteryServiceID {
          peripheral.discoverCharacteristics([batteryLevelID], for: service)
        }
      }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    MainActor.assumeIsolated {
      for c in service.characteristics ?? [] {
        switch c.uuid {
        case commandID:
          commandCharacteristic = c
        case responseID, dataID:
          peripheral.setNotifyValue(true, for: c)
        case batteryLevelID:
          peripheral.readValue(for: c)
          peripheral.setNotifyValue(true, for: c)
        default:
          break
        }
      }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    MainActor.assumeIsolated {
      // Ask for the stream once the data channel is listening.
      if characteristic.uuid == dataID, characteristic.isNotifying { startStream() }
    }
  }

  nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    MainActor.assumeIsolated {
      guard let value = characteristic.value else { return }
      switch characteristic.uuid {
      case dataID:
        handleData(value)
      case responseID:
        if let ack = BandProtocol.commandResponse(value), !ack.accepted {
          log.error("band refused command \(ack.command)")
        }
      case batteryLevelID:
        if let level = value.first { batteryPercent = Int(level) }
      default:
        break
      }
    }
  }
}

/// Debug builds echo key events to stdout so a tethered Mac can follow along.
func debugTrace(_ message: @autoclosure () -> String) {
  #if DEBUG
  print("SPLICE \(Date().formatted(.iso8601.time(includingFractionalSeconds: false))) \(message())")
  #endif
}
