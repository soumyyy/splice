import Foundation

public enum Sport: String, Codable, CaseIterable, Sendable, Identifiable {
  case run, ride, walk, hike, workout

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .run: "Run"
    case .ride: "Ride"
    case .walk: "Walk"
    case .hike: "Hike"
    case .workout: "Workout"
    }
  }

  /// Strava `sport_type` upload value.
  public var stravaSportType: String {
    switch self {
    case .run: "Run"
    case .ride: "Ride"
    case .walk: "Walk"
    case .hike: "Hike"
    case .workout: "Workout"
    }
  }

  /// TCX `Activity Sport` attribute. TCX only knows Running, Biking and Other.
  public var tcxSport: String {
    switch self {
    case .run: "Running"
    case .ride: "Biking"
    case .walk, .hike, .workout: "Other"
    }
  }

  /// Whether GPS is recorded by default.
  public var usesGPS: Bool { self != .workout }
}

public struct HeartRateSample: Codable, Sendable, Equatable {
  public let time: Date
  public let bpm: Int
  public init(time: Date, bpm: Int) {
    self.time = time
    self.bpm = bpm
  }
}

public struct LocationSample: Codable, Sendable, Equatable {
  public let time: Date
  public let latitude: Double
  public let longitude: Double
  public let altitude: Double?
  public let horizontalAccuracy: Double

  public init(time: Date, latitude: Double, longitude: Double, altitude: Double?, horizontalAccuracy: Double) {
    self.time = time
    self.latitude = latitude
    self.longitude = longitude
    self.altitude = altitude
    self.horizontalAccuracy = horizontalAccuracy
  }
}

public enum UploadState: Codable, Sendable, Equatable {
  case notUploaded
  case uploading
  case uploaded(activityID: Int64)
  case failed(message: String)
}

public struct Workout: Codable, Sendable, Identifiable, Equatable {
  public let id: UUID
  public var sport: Sport
  public let startedAt: Date
  public var endedAt: Date?
  public var heartRate: [HeartRateSample]
  public var locations: [LocationSample]
  public var maxHeartRateSetting: Int
  public var upload: UploadState

  public init(id: UUID = UUID(), sport: Sport, startedAt: Date, maxHeartRateSetting: Int) {
    self.id = id
    self.sport = sport
    self.startedAt = startedAt
    self.endedAt = nil
    self.heartRate = []
    self.locations = []
    self.maxHeartRateSetting = maxHeartRateSetting
    self.upload = .notUploaded
  }

  public var duration: TimeInterval {
    (endedAt ?? Date()).timeIntervalSince(startedAt)
  }

  public var averageHeartRate: Int? {
    guard !heartRate.isEmpty else { return nil }
    return Int((Double(heartRate.reduce(0) { $0 + $1.bpm }) / Double(heartRate.count)).rounded())
  }

  public var maxHeartRate: Int? { heartRate.map(\.bpm).max() }

  /// Distance along accurate GPS points, in meters.
  public var distanceMeters: Double {
    Geo.cumulativeDistances(locations).last ?? 0
  }

  public var zones: HeartRateZones { HeartRateZones(maxHeartRate: maxHeartRateSetting) }

  public var timeInZones: [TimeInterval] { zones.timeInZones(heartRate, endedAt: endedAt) }
}

public enum Geo {
  public static let maxAccuracy: Double = 30

  /// Haversine distance in meters.
  public static func distance(_ a: LocationSample, _ b: LocationSample) -> Double {
    let r = 6_371_000.0
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(h)))
  }

  /// Running distance at each sample; inaccurate points add no distance.
  public static func cumulativeDistances(_ locations: [LocationSample]) -> [Double] {
    var result: [Double] = []
    var total = 0.0
    var last: LocationSample?
    for loc in locations {
      if loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= maxAccuracy {
        if let last { total += distance(last, loc) }
        last = loc
      }
      result.append(total)
    }
    return result
  }
}
