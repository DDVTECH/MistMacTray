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
    print("🚀 PushManager: Starting push for stream '\(streamName)' to '\(targetURL)'")

    APIClient.shared.startPush(streamName: streamName, targetURL: targetURL) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Push started successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to start push: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func stopPush(streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("🛑 PushManager: Stopping push for stream '\(streamName)'")

    // Note: APIClient.stopPush expects pushId, but we only have streamName
    // In a real implementation, we'd need to map streamName to pushId
    // For now, we'll use streamName as pushId (this may need adjustment)
    APIClient.shared.stopPush(pushId: streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Push stopped successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to stop push: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func listActivePushes(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    APIClient.shared.fetchPushStatistics(completion: completion)
  }

  // MARK: - Auto-Push Rules

  func createAutoPushRule(
    streamPattern: String, targetURL: String,
    completion: @escaping (Result<String, APIError>) -> Void
  ) {
    print("🚀 PushManager: Creating auto push rule for pattern '\(streamPattern)' to '\(targetURL)'")

    APIClient.shared.createAutoPushRule(streamPattern: streamPattern, targetURL: targetURL) {
      result in
      DispatchQueue.main.async {
        switch result {
        case .success(let response):
          print("✅ Auto push rule created successfully")
          // Extract rule ID from response if available
          if let ruleId = response["id"] as? String {
            completion(.success(ruleId))
          } else {
            completion(.success("rule_created"))
          }
        case .failure(let error):
          print("❌ Failed to create auto push rule: \(error)")
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

    // Validate stream name
    if streamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("Stream name cannot be empty")
    }

    // Validate target URL
    if targetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("Target URL cannot be empty")
    } else if !isValidPushURL(targetURL) {
      errors.append("Invalid target URL format")
    }

    return PushValidationResult(isValid: errors.isEmpty, errors: errors)
  }

  private func isValidPushURL(_ url: String) -> Bool {
    // Check for common push protocols
    let validPrefixes = [
      "rtmp://", "rtmps://", "srt://", "udp://", "file://", "http://", "https://",
    ]
    return validPrefixes.contains { url.lowercased().hasPrefix($0) }
  }

  // MARK: - Push Statistics

  func getPushStatistics(
    pushId: String, completion: @escaping (Result<PushStatistics, APIError>) -> Void
  ) {
    APIClient.shared.fetchPushStatistics(completion: { result in
      switch result {
      case .success(let data):
        let pushData = data[pushId] as? [String: Any] ?? [:]
        let stats = PushStatistics(
          pushId: pushId,
          bytesOut: pushData["bytes_out"] as? Int ?? 0,
          packetsOut: pushData["packets_out"] as? Int ?? 0,
          uptime: pushData["uptime"] as? Int ?? 0,
          status: pushData["status"] as? String ?? "unknown"
        )
        completion(.success(stats))
      case .failure(let error):
        completion(.failure(error))
      }
    })
  }

  // MARK: - Push Data Processing (removed - now handled by unified state management)

  // Legacy method removed to eliminate redundant code paths
  // All data processing now happens through AppDelegate.refreshAllData() → updateCompleteState()

  func performPushStart(
    streamName: String, targetURL: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    print("🎯 Performing push start for \(streamName) -> \(targetURL)")
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
      // Create auto push rule
      createAutoPushRule(streamPattern: streamName, targetURL: targetURL) { result in
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    } else {
      // Just start the push manually
      startPush(streamName: streamName, targetURL: targetURL, completion: completion)
    }
  }
}

// MARK: - Supporting Types

struct PushValidationResult {
  let isValid: Bool
  let errors: [String]
}

struct PushStatistics {
  let pushId: String
  let bytesOut: Int
  let packetsOut: Int
  let uptime: Int
  let status: String

  var formattedBytesOut: String {
    return DataProcessor.shared.formatBytes(bytesOut)
  }

  var formattedUptime: String {
    return DataProcessor.shared.formatConnectionTime(uptime)
  }
}
