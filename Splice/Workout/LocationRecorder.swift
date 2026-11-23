import CoreLocation
import Foundation
import SpliceCore

/// GPS for workouts. Runs in the background once started from the app.
@MainActor
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
  var onLocation: ((LocationSample) -> Void)?
  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.activityType = .fitness
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.pausesLocationUpdatesAutomatically = false
  }

  /// Asks for "While Using", then for "Always" so a workout started from the Lock Screen still gets GPS.
  func requestPermission() {
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
    default: break
    }
  }

  func start() {
    requestPermission()
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.startUpdatingLocation()
  }

  func stop() {
    manager.stopUpdatingLocation()
    manager.allowsBackgroundLocationUpdates = false
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    let samples = locations.map {
      LocationSample(
        time: $0.timestamp,
        latitude: $0.coordinate.latitude,
        longitude: $0.coordinate.longitude,
        altitude: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
        horizontalAccuracy: $0.horizontalAccuracy
      )
    }
    MainActor.assumeIsolated {
      samples.forEach { onLocation?($0) }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedWhenInUse {
      manager.requestAlwaysAuthorization()
    }
  }
}
