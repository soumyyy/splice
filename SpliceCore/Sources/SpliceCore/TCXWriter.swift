import Foundation

/// Builds a Garmin TCX v2 file that Strava accepts, with heart rate on every trackpoint.
public enum TCXWriter {
  public static let creatorName = "Splice"

  public static func document(for workout: Workout) -> String {
    let end = workout.endedAt ?? workout.heartRate.last?.time ?? workout.startedAt
    let points = trackpoints(for: workout)
    let distance = Geo.cumulativeDistances(workout.locations).last ?? 0

    var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Activities>
        <Activity Sport="\(workout.sport.tcxSport)">
          <Id>\(iso(workout.startedAt))</Id>
          <Lap StartTime="\(iso(workout.startedAt))">
            <TotalTimeSeconds>\(String(format: "%.1f", end.timeIntervalSince(workout.startedAt)))</TotalTimeSeconds>
            <DistanceMeters>\(String(format: "%.1f", distance))</DistanceMeters>
            <Calories>0</Calories>

    """
    if let avg = workout.averageHeartRate {
      xml += "          <AverageHeartRateBpm><Value>\(avg)</Value></AverageHeartRateBpm>\n"
    }
    if let max = workout.maxHeartRate {
      xml += "          <MaximumHeartRateBpm><Value>\(max)</Value></MaximumHeartRateBpm>\n"
    }
    xml += """
              <Intensity>Active</Intensity>
              <TriggerMethod>Manual</TriggerMethod>
              <Track>

    """
    for point in points {
      xml += "            <Trackpoint>\n"
      xml += "              <Time>\(iso(point.time))</Time>\n"
      if let loc = point.location {
        xml += "              <Position><LatitudeDegrees>\(String(format: "%.7f", loc.latitude))</LatitudeDegrees><LongitudeDegrees>\(String(format: "%.7f", loc.longitude))</LongitudeDegrees></Position>\n"
        if let alt = loc.altitude {
          xml += "              <AltitudeMeters>\(String(format: "%.1f", alt))</AltitudeMeters>\n"
        }
        xml += "              <DistanceMeters>\(String(format: "%.1f", point.distance))</DistanceMeters>\n"
      }
      if let bpm = point.bpm {
        xml += "              <HeartRateBpm><Value>\(bpm)</Value></HeartRateBpm>\n"
      }
      xml += "            </Trackpoint>\n"
    }
    xml += """
              </Track>
            </Lap>
            <Creator xsi:type="Device_t"><Name>\(creatorName)</Name><UnitId>0</UnitId><ProductID>0</ProductID><Version><VersionMajor>1</VersionMajor><VersionMinor>0</VersionMinor></Version></Creator>
          </Activity>
        </Activities>
      </TrainingCenterDatabase>

    """
    return xml
  }

  struct Point {
    let time: Date
    var bpm: Int?
    var location: LocationSample?
    var distance: Double
  }

  /// Merges heart rate (1 Hz) and GPS onto one timeline at whole seconds.
  static func trackpoints(for workout: Workout) -> [Point] {
    let distances = Geo.cumulativeDistances(workout.locations)
    var bySecond: [Int: Point] = [:]
    func key(_ d: Date) -> Int { Int(d.timeIntervalSince1970.rounded()) }

    for sample in workout.heartRate {
      let k = key(sample.time)
      bySecond[k, default: Point(time: Date(timeIntervalSince1970: TimeInterval(k)), distance: 0)].bpm = sample.bpm
    }
    for (i, loc) in workout.locations.enumerated()
    where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= Geo.maxAccuracy {
      let k = key(loc.time)
      var p = bySecond[k] ?? Point(time: Date(timeIntervalSince1970: TimeInterval(k)), distance: 0)
      p.location = loc
      p.distance = distances[i]
      bySecond[k] = p
    }
    return bySecond.keys.sorted().compactMap { bySecond[$0] }
  }

  private static func iso(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))
      .replacingOccurrences(of: "+0000", with: "Z")
  }
}

public enum WorkoutSummary {
  /// Plain-text description for the Strava activity, including time in zones.
  public static func stravaDescription(for workout: Workout) -> String {
    var lines: [String] = []
    if let avg = workout.averageHeartRate, let max = workout.maxHeartRate {
      lines.append("❤️ Avg \(avg) bpm · Max \(max) bpm")
    }
    let zones = workout.timeInZones
    let total = zones.reduce(0, +)
    if total > 0 {
      let bounds = workout.zones.thresholds
      for (i, seconds) in zones.enumerated() where seconds >= 1 {
        let pct = Int((seconds / total * 100).rounded())
        let upper = i < 4 ? "\(bounds[i + 1] - 1)" : "+"
        let range = i < 4 ? "\(bounds[i])–\(upper)" : "\(bounds[i])+"
        lines.append("Z\(i + 1) \(HeartRateZones.names[i]) (\(range)): \(duration(seconds)) · \(pct)%")
      }
    }
    lines.append("Recorded with Splice")
    return lines.joined(separator: "\n")
  }

  public static func duration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    return s >= 3600
      ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
      : String(format: "%d:%02d", s / 60, s % 60)
  }
}
