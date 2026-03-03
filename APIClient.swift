//
//  APIClient.swift
//  MistTray
//

import CryptoKit
import Foundation

class APIClient {
  static let shared = APIClient()

  var baseURL = "http://localhost:4242/api"
  private let session = URLSession.shared

  // MARK: - Auth State
  var authUsername = ""
  var authPasswordHash = ""  // MD5(raw_password)
  var authChallenge = ""

  private init() {}

  private func md5(_ string: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Build the authorize block to include with every API call (mirrors LSP behavior).
  private func authBlock() -> [String: Any] {
    let password: String
    if !authPasswordHash.isEmpty && !authChallenge.isEmpty {
      password = md5(authPasswordHash + authChallenge)
    } else {
      password = ""
    }
    return ["username": authUsername, "password": password]
  }

  // MARK: - Generic API Methods

  func makeAPICall<T>(_ apiCall: [String: Any], completion: @escaping (Result<T, APIError>) -> Void)
  {
    // Inject authorize block if caller didn't provide one (like LSP does with every request)
    var enriched = apiCall
    if enriched["authorize"] == nil {
      enriched["authorize"] = authBlock()
    }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: enriched),
      let url = URL(string: baseURL)
    else {
      completion(.failure(.invalidRequest))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 30.0

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        DispatchQueue.main.async {
          completion(.failure(.networkError(error)))
        }
        return
      }

      guard let data = data else {
        DispatchQueue.main.async {
          completion(.failure(.noData))
        }
        return
      }

      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode != 200 {
          DispatchQueue.main.async {
            completion(.failure(.httpError(httpResponse.statusCode)))
          }
          return
        }
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? T {
          DispatchQueue.main.async {
            completion(.success(json))
          }
        } else {
          DispatchQueue.main.async {
            completion(.failure(.parseError))
          }
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(.parseError))
        }
      }
    }.resume()
  }

  func makeAPICallWithRetry(
    _ apiCall: [String: Any], retryCount: Int = 0, maxRetries: Int = 3,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    makeAPICall(apiCall) { (result: Result<[String: Any], APIError>) in
      switch result {
      case .success(let data):
        completion(.success(data))
      case .failure(let error):
        if retryCount < maxRetries, case .networkError(let networkError) = error {
          let nsError = networkError as NSError
          if nsError.code == -1004 {  // Connection failed
            let delay = Double(retryCount + 1) * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
              self?.makeAPICallWithRetry(
                apiCall, retryCount: retryCount + 1, maxRetries: maxRetries, completion: completion)
            }
          } else {
            completion(.failure(error))
          }
        } else {
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Stream Operations

  func nukeStream(
    _ streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["nuke_stream": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func createStream(
    name: String, source: String?, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    var streamConfig: [String: Any] = [:]
    if let source = source {
      streamConfig["source"] = source
    }

    let apiCall = ["addstream": [name: streamConfig]]
    makeAPICall(apiCall, completion: completion)
  }

  func updateStream(
    name: String, config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["addstream": [name: config]]
    makeAPICall(apiCall, completion: completion)
  }

  func deleteStream(
    _ streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["deletestream": [streamName]]
    makeAPICall(apiCall, completion: completion)
  }

  func addStreamTag(
    streamName: String, tagName: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["tag_stream": [streamName: tagName]]
    makeAPICall(apiCall, completion: completion)
  }

  func removeStreamTag(
    streamName: String, tagName: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["untag_stream": [streamName: tagName]]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchStreamTags(
    for streamName: String, completion: @escaping (Result<[String], APIError>) -> Void
  ) {
    let apiCall = ["stream_tags": streamName]
    makeAPICall(apiCall) { (result: Result<[String: Any], APIError>) in
      switch result {
      case .success(let data):
        if let tags = data["stream_tags"] as? [String] {
          completion(.success(tags))
        } else {
          completion(.success([]))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Push Operations

  func startPush(
    streamName: String, targetURL: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = [
      "push_start": [
        "stream": streamName,
        "target": targetURL,
      ]
    ]
    makeAPICall(apiCall, completion: completion)
  }

  func stopPush(pushId: Int, completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["push_stop": [pushId]]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchAutoPushRules(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["push_auto_list": true]
    makeAPICall(apiCall, completion: completion)
  }

  func createAutoPushRule(
    streamPattern: String, targetURL: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = [
      "push_auto_add": [
        "stream": streamPattern,
        "target": targetURL,
      ]
    ]
    makeAPICall(apiCall, completion: completion)
  }

  func deleteAutoPushRule(
    ruleId: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["push_auto_remove": ruleId]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Client Operations

  func disconnectClient(
    sessionId: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["stop_sessid": sessionId]
    makeAPICall(apiCall, completion: completion)
  }

  func kickAllViewers(
    streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["stop_sessions": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func forceReauthentication(
    streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["invalidate_sessions": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func tagSession(
    sessionId: String, tag: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["tag_sessid": [sessionId: tag]]
    makeAPICall(apiCall, completion: completion)
  }

  func stopTaggedSessions(
    tag: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["stop_tag": tag]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Monitoring Operations

  func fetchAllServerData(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = [
      "active_streams": true,
      "streams": true,
      "push_list": true,
      "push_auto_list": true,
      "push_settings": true,
      "config": true,
      "totals": true,
      "log": true,
      "capabilities": true,
      "variable_list": true,
      "external_writer_list": true,
      "jwks": true,
      "streamkeys": true,
      "clients": [
        "fields": ["host", "stream", "protocol", "conntime", "downbps", "upbps"]
      ],
    ]
    makeAPICallWithRetry(apiCall, completion: completion)
  }

  func fetchConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["config": true]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchCapabilities(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["capabilities": true]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Configuration Operations

  func backupConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["config_backup": true]
    makeAPICall(apiCall) { (result: Result<[String: Any], APIError>) in
      switch result {
      case .success(let data):
        if let backup = data["config_backup"] as? [String: Any] {
          completion(.success(backup))
        } else {
          // Fallback: return full response if config_backup key not found
          completion(.success(data))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func restoreConfiguration(
    _ configData: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["config_restore": configData]
    makeAPICall(apiCall, completion: completion)
  }

  func saveConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["save": true]
    makeAPICall(apiCall, completion: completion)
  }

  func gracefulShutdown(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["shutdown": true]
    makeAPICall(apiCall, completion: completion)
  }

  func applyPushSettings(
    maxSpeed: Int, waitTime: Int, autoRestart: Bool,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let pushSettings: [String: Any] = [
      "maxspeed": maxSpeed,
      "wait": waitTime,
      "autorestart": autoRestart,
    ]
    let apiCall = ["push_settings": pushSettings]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Authorization Operations

  func checkAuthStatus(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    // Send empty request — authorize block is auto-injected by makeAPICall
    let apiCall: [String: Any] = [:]
    makeAPICall(apiCall, completion: completion)
  }

  /// Attempt login with username and raw password.
  /// Stores hashed credentials on success for all subsequent API calls.
  func login(
    username: String, rawPassword: String,
    completion: @escaping (Bool, String?) -> Void
  ) {
    authUsername = username
    authPasswordHash = md5(rawPassword)

    // Send auth check — makeAPICall auto-injects authorize with current credentials
    makeAPICall([:]) { [weak self] (result: Result<[String: Any], APIError>) in
      guard let self = self else { return }
      switch result {
      case .success(let data):
        guard let authorize = data["authorize"] as? [String: Any],
              let status = authorize["status"] as? String
        else {
          completion(false, "Unexpected response")
          return
        }
        switch status {
        case "OK":
          completion(true, nil)
        case "CHALL":
          if let challenge = authorize["challenge"] as? String {
            let oldChallenge = self.authChallenge
            self.authChallenge = challenge
            if challenge == oldChallenge {
              // Same challenge = wrong credentials
              completion(false, "Invalid username or password")
            } else {
              // New challenge, retry with updated hash
              self.retryLogin(completion: completion)
            }
          } else {
            completion(false, "Missing challenge")
          }
        default:
          completion(false, "Unexpected status: \(status)")
        }
      case .failure(let error):
        completion(false, error.localizedDescription)
      }
    }
  }

  private func retryLogin(completion: @escaping (Bool, String?) -> Void) {
    makeAPICall([:]) { [weak self] (result: Result<[String: Any], APIError>) in
      guard let self = self else { return }
      switch result {
      case .success(let data):
        guard let authorize = data["authorize"] as? [String: Any],
              let status = authorize["status"] as? String
        else {
          completion(false, "Unexpected response")
          return
        }
        if status == "OK" {
          completion(true, nil)
        } else if status == "CHALL" {
          if let challenge = authorize["challenge"] as? String {
            self.authChallenge = challenge
          }
          completion(false, "Invalid username or password")
        } else {
          completion(false, "Unexpected status: \(status)")
        }
      case .failure(let error):
        completion(false, error.localizedDescription)
      }
    }
  }

  func clearAuth() {
    authUsername = ""
    authPasswordHash = ""
    authChallenge = ""
  }

  func createAccount(
    username: String, password: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = [
      "authorize": [
        "new_username": username,
        "new_password": password,
      ]
    ]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Protocol Management

  func addProtocol(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["addprotocol": config]
    makeAPICall(apiCall, completion: completion)
  }

  func deleteProtocol(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["deleteprotocol": config]
    makeAPICall(apiCall, completion: completion)
  }

  func updateProtocol(
    original: [String: Any], updated: [String: Any],
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["updateprotocol": [original, updated]]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Trigger Management

  /// Save triggers by reading current config, replacing the triggers key, and sending full config.
  func saveTriggers(
    _ triggers: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    fetchConfiguration { [weak self] result in
      switch result {
      case .success(let data):
        var config = data["config"] as? [String: Any] ?? [:]
        config["triggers"] = triggers
        let apiCall: [String: Any] = ["config": config]
        self?.makeAPICall(apiCall, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Variables

  func listVariables(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["variable_list": true]
    makeAPICall(apiCall, completion: completion)
  }

  func addVariable(
    _ variable: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["variable_add": variable]
    makeAPICall(apiCall, completion: completion)
  }

  func removeVariable(
    name: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["variable_remove": name]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - External Writers

  func listExternalWriters(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["external_writer_list": true]
    makeAPICall(apiCall, completion: completion)
  }

  func addExternalWriter(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["external_writer_add": config]
    makeAPICall(apiCall, completion: completion)
  }

  func removeExternalWriter(
    name: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["external_writer_remove": name]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Push Extras

  /// Add an automatic push rule with full fields (scheduling, conditions, notes, deactivation).
  func addAutoPush(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["push_auto_add": config]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - JWK Management

  func addJWK(
    _ entries: [[Any]], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["addjwks": entries]
    makeAPICall(apiCall, completion: completion)
  }

  func deleteJWK(
    _ identifier: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["deletejwks": identifier]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Stream Processes

  func fetchProcessList(
    streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["proc_list": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Stream Keys

  func addStreamKeys(
    _ keys: [String: String], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["streamkey_add": keys]
    makeAPICall(apiCall, completion: completion)
  }

  func deleteStreamKeys(
    _ keys: [String], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["streamkey_del": keys]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Camera / Device Discovery

  func listCameras(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = ["camera_list": true]
    makeAPICall(apiCall, completion: completion)
  }

  func updateCamera(
    _ params: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["camera_update": params]
    makeAPICall(apiCall, completion: completion)
  }

  func removeCamera(
    id: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["camera_remove": ["id": id]]
    makeAPICall(apiCall, completion: completion)
  }

  func queryCameraCommand(
    id: String, command: String, args: [String: Any]? = nil,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    var query: [String: Any] = ["id": id, "command": command]
    if let args = args { query["args"] = args }
    let apiCall: [String: Any] = ["camera_query": query]
    makeAPICall(apiCall, completion: completion)
  }

  func createStreamFromCamera(
    _ params: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["camera_create_stream": params]
    makeAPICall(apiCall, completion: completion)
  }

  func updateCameraConfig(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall: [String: Any] = ["camera_config": config]
    makeAPICall(apiCall, completion: completion)
  }
}

// MARK: - Error Types

enum APIError: Error, LocalizedError {
  case invalidRequest
  case networkError(Error)
  case httpError(Int)
  case noData
  case parseError

  var errorDescription: String? {
    switch self {
    case .invalidRequest:
      return "Invalid API request"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .httpError(let code):
      return "HTTP error: \(code)"
    case .noData:
      return "No data received"
    case .parseError:
      return "Failed to parse response"
    }
  }
}
