import Foundation
import os
import SpliceCore

/// Uploads a finished workout as TCX and waits until Strava has created the activity.
@MainActor
final class StravaUploader {
  private let auth: StravaAuth
  private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "strava")

  init(auth: StravaAuth) {
    self.auth = auth
  }

  /// Returns the Strava activity id.
  func upload(_ workout: Workout) async throws -> Int64 {
    let upload = try await post(workout, retryOnUnauthorized: true)
    if let activityID = upload.activityID { return activityID }
    if let duplicate = upload.duplicateActivityID { return duplicate }
    if let error = upload.error { throw StravaError.processing(error) }

    // Processing usually takes under 2 seconds.
    for _ in 0..<30 {
      try await Task.sleep(for: .seconds(2))
      let status = try await poll(upload.id)
      if let activityID = status.activityID { return activityID }
      if let duplicate = status.duplicateActivityID { return duplicate }
      if let error = status.error { throw StravaError.processing(error) }
    }
    throw StravaError.timedOut
  }

  private struct UploadStatus: Decodable {
    let id: Int64
    let error: String?
    let status: String?
    let activity_id: Int64?

    var activityID: Int64? { activity_id }

    /// Strava reports an already-uploaded file as "… duplicate of activity 123".
    var duplicateActivityID: Int64? {
      guard let error, let range = error.range(of: "duplicate of activity ") else { return nil }
      let digits = error[range.upperBound...].prefix { $0.isNumber }
      return Int64(digits)
    }
  }

  private func post(_ workout: Workout, retryOnUnauthorized: Bool) async throws -> UploadStatus {
    let token = try await auth.validAccessToken()
    let boundary = "splice-\(UUID().uuidString)"
    var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    func field(_ name: String, _ value: String) {
      body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    field("data_type", "tcx")
    field("sport_type", workout.sport.stravaSportType)
    field("description", WorkoutSummary.stravaDescription(for: workout))
    field("external_id", "splice-\(workout.id.uuidString).tcx")
    if workout.locations.isEmpty { field("trainer", "1") }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"splice-\(workout.id.uuidString).tcx\"\r\nContent-Type: application/xml\r\n\r\n".data(using: .utf8)!)
    body.append(Data(TCXWriter.document(for: workout).utf8))
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401, retryOnUnauthorized {
      try await auth.forceRefresh()
      return try await post(workout, retryOnUnauthorized: false)
    }
    // Strava answers 400 with an upload body for duplicates and bad files.
    if let status = try? JSONDecoder().decode(UploadStatus.self, from: data), code == 201 || code == 400 {
      log.info("upload \(status.id) accepted: \(status.status ?? "", privacy: .public)")
      return status
    }
    throw StravaError.http(code, String(decoding: data, as: UTF8.self))
  }

  private func poll(_ id: Int64) async throws -> UploadStatus {
    let token = try await auth.validAccessToken()
    var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(id)")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else { throw StravaError.http(code, String(decoding: data, as: UTF8.self)) }
    return try JSONDecoder().decode(UploadStatus.self, from: data)
  }
}
