import AuthenticationServices
import Foundation
import Security
import UIKit

struct StravaTokens: Codable, Sendable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Date
  var athleteName: String?
}

enum StravaError: LocalizedError {
  case missingAppCredentials
  case notConnected
  case cancelled
  case http(Int, String)
  case processing(String)
  case timedOut

  var errorDescription: String? {
    switch self {
    case .missingAppCredentials: "Strava app credentials are missing from the build."
    case .notConnected: "Connect Strava in Settings."
    case .cancelled: "Strava sign-in was cancelled."
    case .http(let code, let body): "Strava returned \(code): \(body.prefix(160))"
    case .processing(let message): message
    case .timedOut: "Strava is still processing the upload."
    }
  }

  /// Errors worth retrying later without user action.
  var isTransient: Bool {
    switch self {
    case .http(let code, _): code == 429 || code >= 500
    case .timedOut: true
    default: false
    }
  }
}

/// Strava OAuth with tokens kept in the Keychain and refreshed automatically.
@MainActor
final class StravaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let redirectURI = "splice://localhost"
  private let keychainAccount = "strava.tokens"

  let clientID = Bundle.main.object(forInfoDictionaryKey: "StravaClientID") as? String ?? ""
  let clientSecret = Bundle.main.object(forInfoDictionaryKey: "StravaClientSecret") as? String ?? ""

  private(set) var tokens: StravaTokens?
  private var session: ASWebAuthenticationSession?

  var hasAppCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty && !clientID.hasPrefix("$(") }

  override init() {
    super.init()
    tokens = Keychain.read(account: keychainAccount).flatMap { try? JSONDecoder.splice.decode(StravaTokens.self, from: $0) }
  }

  func connect() async throws {
    guard hasAppCredentials else { throw StravaError.missingAppCredentials }
    var c = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
    c.queryItems = [
      .init(name: "client_id", value: clientID),
      .init(name: "redirect_uri", value: Self.redirectURI),
      .init(name: "response_type", value: "code"),
      .init(name: "approval_prompt", value: "auto"),
      .init(name: "scope", value: "read,activity:write"),
    ]
    let callback: URL = try await withCheckedThrowingContinuation { cont in
      let s = ASWebAuthenticationSession(url: c.url!, callback: .customScheme("splice")) { url, error in
        if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? StravaError.cancelled) }
      }
      s.presentationContextProvider = self
      s.prefersEphemeralWebBrowserSession = false
      session = s
      s.start()
    }
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let code = items.first(where: { $0.name == "code" })?.value else {
      throw StravaError.processing(items.first(where: { $0.name == "error" })?.value ?? "No code returned")
    }
    let scope = items.first(where: { $0.name == "scope" })?.value ?? ""
    guard scope.contains("activity:write") else {
      throw StravaError.processing("Allow “Upload your activities” when connecting Strava.")
    }
    try await requestTokens(["grant_type": "authorization_code", "code": code])
  }

  func disconnect() {
    tokens = nil
    Keychain.delete(account: keychainAccount)
  }

  /// A valid access token, refreshed if it expires within a minute.
  func validAccessToken() async throws -> String {
    guard let tokens else { throw StravaError.notConnected }
    if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
    try await requestTokens(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken])
    return self.tokens!.accessToken
  }

  func forceRefresh() async throws {
    guard let tokens else { throw StravaError.notConnected }
    try await requestTokens(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken])
  }

  private func requestTokens(_ params: [String: String]) async throws {
    var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var all = params
    all["client_id"] = clientID
    all["client_secret"] = clientSecret
    request.httpBody = all.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
      .joined(separator: "&").data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else {
      if code == 400 || code == 401 { disconnect() }
      throw StravaError.http(code, String(decoding: data, as: UTF8.self))
    }
    struct Body: Decodable {
      struct Athlete: Decodable { let firstname: String? }
      let access_token: String
      let refresh_token: String
      let expires_at: TimeInterval
      let athlete: Athlete?
    }
    let body = try JSONDecoder().decode(Body.self, from: data)
    let new = StravaTokens(
      accessToken: body.access_token,
      refreshToken: body.refresh_token,
      expiresAt: Date(timeIntervalSince1970: body.expires_at),
      athleteName: body.athlete?.firstname ?? tokens?.athleteName
    )
    tokens = new
    if let encoded = try? JSONEncoder.splice.encode(new) { Keychain.write(encoded, account: keychainAccount) }
  }

  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.compactMap(\.keyWindow).first ?? ASPresentationAnchor(windowScene: scenes[0])
    }
  }
}

enum Keychain {
  private static let service = "com.soumyamaheshwari.splice"

  static func read(account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
    ]
    var result: AnyObject?
    return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
  }

  static func write(_ data: Data, account: String) {
    delete(account: account)
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      // Readable in the background after the first unlock, so uploads work with the phone locked.
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  static func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
