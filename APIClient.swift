//
//  APIClient.swift
//  MistTray
//

import Foundation

class APIClient {
  static let shared = APIClient()

  private let baseURL = "http://localhost:4242/api"
  private let session = URLSession.shared

  private init() {}

  // MARK: - Generic API Methods

  func makeAPICall<T>(_ apiCall: [String: Any], completion: @escaping (Result<T, APIError>) -> Void)
  {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: apiCall),
      let url = URL(string: baseURL)
    else {
      completion(.failure(.invalidRequest))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 10.0

    print("📡 API Call: \(apiCall)")

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        print("❌ API Error: \(error)")
        DispatchQueue.main.async {
          completion(.failure(.networkError(error)))
        }
        return
      }

      guard let data = data else {
        print("❌ No data received")
        DispatchQueue.main.async {
          completion(.failure(.noData))
        }
        return
      }

      if let httpResponse = response as? HTTPURLResponse {
        print("📡 API Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
          DispatchQueue.main.async {
            completion(.failure(.httpError(httpResponse.statusCode)))
          }
          return
        }
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? T {
          print("📡 API Response: Success")

          // Add detailed response logging for debugging
          if let jsonDict = json as? [String: Any] {
            print("📡 Full API Response Data:")
            for (key, value) in jsonDict {
              print("   \(key): \(value)")
            }
          }

          DispatchQueue.main.async {
            completion(.success(json))
          }
        } else {
          print("❌ Failed to parse response as expected type")
          print("📡 Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
          DispatchQueue.main.async {
            completion(.failure(.parseError))
          }
        }
      } catch {
        print("❌ JSON parsing error: \(error)")
        print("📡 Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
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
            print("🔄 Retrying API call in \(delay)s... (attempt \(retryCount + 1)/\(maxRetries))")
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

  func deleteStream(
    _ streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["deletestream": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func addStreamTag(
    streamName: String, tagName: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = [
      "addtag": [
        "stream": streamName,
        "tag": tagName,
      ]
    ]
    makeAPICall(apiCall, completion: completion)
  }

  func removeStreamTag(
    streamName: String, tagName: String,
    completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = [
      "deltag": [
        "stream": streamName,
        "tag": tagName,
      ]
    ]
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

  func stopPush(pushId: String, completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["push_stop": pushId]
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
    let apiCall = ["stop_sessID": sessionId]
    makeAPICall(apiCall, completion: completion)
  }

  func disconnectClientLegacy(
    sessionId: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["disconnect": sessionId]
    makeAPICall(apiCall, completion: completion)
  }

  func kickAllViewers(
    streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["kick": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func forceReauthentication(
    streamName: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["reauth": streamName]
    makeAPICall(apiCall, completion: completion)
  }

  func tagSession(
    sessionId: String, tag: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = [
      "tag_sessID": [
        "sessID": sessionId,
        "tag": tag,
      ]
    ]
    makeAPICall(apiCall, completion: completion)
  }

  func stopTaggedSessions(
    tag: String, completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["stop_tag": tag]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Monitoring Operations

  func fetchServerStatus(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["active_streams": true, "totals": true, "clients": true]
    makeAPICallWithRetry(apiCall, completion: completion)
  }

  func fetchAllServerData(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall: [String: Any] = [
      "active_streams": true,
      "streams": true,  // Get ALL streams, not just active ones
      "stats_streams": true,
      "push_list": true,
      "clients": [
        "fields": ["host", "stream", "protocol", "conntime", "sessId"]
      ],
    ]
    makeAPICallWithRetry(apiCall, completion: completion)
  }

  func fetchStreamStatistics(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["active_streams": true, "totals": true]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchServerTotals(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["totals": true]
    makeAPICall(apiCall) { (result: Result<[String: Any], APIError>) in
      switch result {
      case .success(let data):
        if let totals = data["totals"] as? [String: Any] {
          completion(.success(totals))
        } else {
          completion(.success([:]))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func fetchClientStatistics(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["clients": true]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchPushStatistics(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["active_pushes": true]
    makeAPICall(apiCall, completion: completion)
  }

  func fetchConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["config": true]
    makeAPICall(apiCall, completion: completion)
  }

  func updateConfiguration(
    _ config: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    let apiCall = ["config": config]
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Protocol Operations

  func fetchProtocolConfig(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["config": ["protocols": true]]
    makeAPICall(apiCall, completion: completion)
  }

  func performProtocolAction(
    apiCall: [String: Any], completion: @escaping (Result<[String: Any], APIError>) -> Void
  ) {
    makeAPICall(apiCall, completion: completion)
  }

  // MARK: - Configuration Operations

  func backupConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["config": true]
    makeAPICall(apiCall, completion: completion)
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

  // MARK: - Update Operations

  func checkForUpdates(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["checkupdate": true]
    makeAPICall(apiCall, completion: completion)
  }

  func performUpdate(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    let apiCall = ["update": true]
    var request = URLRequest(url: URL(string: baseURL)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: apiCall)
    request.timeoutInterval = 30.0  // Updates might take longer

    print("📡 API Call (Update): \(apiCall)")

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        print("❌ Update API Error: \(error)")
        DispatchQueue.main.async {
          completion(.failure(.networkError(error)))
        }
        return
      }

      guard let data = data else {
        print("❌ No data received for update")
        DispatchQueue.main.async {
          completion(.failure(.noData))
        }
        return
      }

      if let httpResponse = response as? HTTPURLResponse {
        print("📡 Update API Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
          DispatchQueue.main.async {
            completion(.failure(.httpError(httpResponse.statusCode)))
          }
          return
        }
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          print("📡 Update API Response: Success")
          DispatchQueue.main.async {
            completion(.success(json))
          }
        } else {
          print("❌ Failed to parse update response")
          DispatchQueue.main.async {
            completion(.failure(.parseError))
          }
        }
      } catch {
        print("❌ Update JSON parsing error: \(error)")
        DispatchQueue.main.async {
          completion(.failure(.parseError))
        }
      }
    }.resume()
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
