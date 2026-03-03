//
//  PushManager.swift
//  MistTray
//

import Foundation

class PushManager {
  static let shared = PushManager()

  private init() {}

  // MARK: - Push Operations

  func startPush(
    streamName: String, targetURL: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    print("PushManager: Starting push for stream '\(streamName)' to '\(targetURL)'")

    APIClient.shared.startPush(streamName: streamName, targetURL: targetURL) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("Push started successfully")
          completion(.success(()))
        case .failure(let error):
          print("Failed to start push: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func stopPush(pushId: Int, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("PushManager: Stopping push '\(pushId)'")

    APIClient.shared.stopPush(pushId: pushId) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("Push stopped successfully")
          completion(.success(()))
        case .failure(let error):
          print("Failed to stop push: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Auto-Push Rules

  func createAutoPushRule(
    streamPattern: String, targetURL: String,
    completion: @escaping (Result<String, APIError>) -> Void
  ) {
    print("PushManager: Creating auto push rule for pattern '\(streamPattern)' to '\(targetURL)'")

    APIClient.shared.createAutoPushRule(streamPattern: streamPattern, targetURL: targetURL) {
      result in
      DispatchQueue.main.async {
        switch result {
        case .success(let response):
          print("Auto push rule created successfully")
          if let ruleId = response["id"] as? String {
            completion(.success(ruleId))
          } else {
            completion(.success("rule_created"))
          }
        case .failure(let error):
          print("Failed to create auto push rule: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func deleteAutoPushRule(ruleId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    APIClient.shared.deleteAutoPushRule(ruleId: ruleId) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func listAutoPushRules(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    APIClient.shared.fetchAutoPushRules(completion: completion)
  }

  // MARK: - Push Validation

  func validatePushConfiguration(streamName: String, targetURL: String) -> PushValidationResult {
    var errors: [String] = []

    if streamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("Stream name cannot be empty")
    }

    if targetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("Target URL cannot be empty")
    } else if !isValidPushURL(targetURL) {
      errors.append("Invalid target URL format")
    }

    return PushValidationResult(isValid: errors.isEmpty, errors: errors)
  }

  private func isValidPushURL(_ url: String) -> Bool {
    let validPrefixes = [
      "rtmp://", "rtmps://", "srt://", "udp://", "file://", "http://", "https://",
    ]
    return validPrefixes.contains { url.lowercased().hasPrefix($0) }
  }

  // MARK: - Push Settings

  func performPushStart(
    streamName: String, targetURL: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    print("Performing push start for \(streamName) -> \(targetURL)")
    startPush(streamName: streamName, targetURL: targetURL, completion: completion)
  }

  func applyPushSettings(
    _ settings: [String: Any], completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    guard let streamName = settings["stream"] as? String,
      let targetURL = settings["target"] as? String
    else {
      completion(.failure(.invalidRequest))
      return
    }

    let autoStart = settings["autoStart"] as? Bool ?? false

    if autoStart {
      createAutoPushRule(streamPattern: streamName, targetURL: targetURL) { result in
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    } else {
      startPush(streamName: streamName, targetURL: targetURL, completion: completion)
    }
  }
}

// MARK: - Supporting Types

struct PushValidationResult {
  let isValid: Bool
  let errors: [String]
}
