//
//  StreamManager.swift
//  MistTray
//

import Foundation

class StreamManager {
  static let shared = StreamManager()

  private init() {}

  // MARK: - Stream Operations

  func createStream(
    name: String, source: String, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("🚀 StreamManager: Creating stream '\(name)' with source '\(source)'")

    APIClient.shared.createStream(name: name, source: source) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func deleteStream(name: String, completion: @escaping (Result<Void, Error>) -> Void) {
    print("🚀 StreamManager: Deleting stream '\(name)'")
    APIClient.shared.deleteStream(name) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func nukeStream(name: String, completion: @escaping (Result<Void, Error>) -> Void) {
    print("🚀 StreamManager: Nuking stream '\(name)'")
    APIClient.shared.nukeStream(name) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func updateStream(
    name: String, config: [String: Any], completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("🚀 StreamManager: Updating stream '\(name)'")
    // For now, use configuration update - in real implementation would need specific stream update API
    APIClient.shared.updateConfiguration(config) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func getStreamStatistics(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    print("🚀 StreamManager: Fetching stream statistics")
    APIClient.shared.fetchStreamStatistics { result in
      switch result {
      case .success(let data):
        completion(.success(data))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func getActiveStreams(completion: @escaping (Result<[String], Error>) -> Void) {
    print("🚀 StreamManager: Fetching active streams")

    APIClient.shared.fetchStreamStatistics { result in
      switch result {
      case .success(let data):
        let activeStreams = self.extractActiveStreams(from: data)
        completion(.success(activeStreams))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func getAllStreams(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    print("🚀 StreamManager: Fetching all streams")
    // Use configuration fetch to get all streams
    APIClient.shared.fetchConfiguration { result in
      switch result {
      case .success(let data):
        completion(.success(data))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func startStream(_ streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    // Use existing createStream method as there's no startStream in APIClient
    APIClient.shared.createStream(name: streamName, source: nil) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }

  func stopStream(_ streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    // Use deleteStream as there's no stopStream in APIClient
    APIClient.shared.deleteStream(streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }

  func nukeStream(_ streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("🔥 Nuking stream: \(streamName)")

    APIClient.shared.nukeStream(streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Stream \(streamName) nuked successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to nuke stream \(streamName): \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Stream Tags Management

  func getStreamTags(streamName: String, completion: @escaping (Result<[String], Error>) -> Void) {
    print("🚀 StreamManager: Fetching tags for stream '\(streamName)'")

    APIClient.shared.fetchConfiguration { result in
      switch result {
      case .success(let config):
        let tags = self.extractTags(from: config)
        completion(.success(tags))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func updateStreamTags(
    streamName: String, tags: [String], completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("🚀 StreamManager: Updating tags for stream '\(streamName)': \(tags)")

    // For now, just complete successfully - in real implementation would update stream config
    completion(.success(()))
  }

  func addStreamTag(
    _ streamName: String, tag: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.addStreamTag(streamName: streamName, tagName: tag) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }

  func removeStreamTag(
    _ streamName: String, tag: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.removeStreamTag(streamName: streamName, tagName: tag) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }

  func fetchStreamTags(
    for streamName: String, completion: @escaping (Result<[String], APIError>) -> Void
  ) {
    APIClient.shared.fetchStreamTags(for: streamName) { result in
      DispatchQueue.main.async {
        completion(result)
      }
    }
  }

  // MARK: - Session Management

  func tagSessions(
    _ sessionIds: [String], tag: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    // Tag each session individually since APIClient expects single sessionId
    let group = DispatchGroup()
    var errors: [APIError] = []

    for sessionId in sessionIds {
      group.enter()
      APIClient.shared.tagSession(sessionId: sessionId, tag: tag) { result in
        switch result {
        case .success:
          break
        case .failure(let error):
          errors.append(error)
        }
        group.leave()
      }
    }

    group.notify(queue: .main) {
      if errors.isEmpty {
        completion(.success(()))
      } else {
        completion(.failure(errors.first!))
      }
    }
  }

  func stopTaggedSessions(_ tag: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    APIClient.shared.stopTaggedSessions(tag: tag) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          completion(.success(()))
        case .failure(let error):
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Stream Validation

  func validateStreamName(_ name: String) -> StreamValidationResult {
    // Check if name is empty
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .invalid("Stream name cannot be empty")
    }

    // Check for invalid characters
    let invalidChars = CharacterSet(charactersIn: "!@#$%^&*()+={}[]|\\:;\"'<>?,./")
    if name.rangeOfCharacter(from: invalidChars) != nil {
      return .invalid("Stream name contains invalid characters")
    }

    // Check length
    if name.count > 50 {
      return .invalid("Stream name is too long (max 50 characters)")
    }

    return .valid
  }

  func validateStreamSource(_ source: String) -> StreamValidationResult {
    // Check if source is empty
    if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .invalid("Stream source cannot be empty")
    }

    // Basic URL validation for common protocols
    let commonProtocols = ["rtmp://", "rtsp://", "http://", "https://", "file://", "push://"]
    let hasValidProtocol = commonProtocols.contains { source.lowercased().hasPrefix($0) }

    if !hasValidProtocol && !source.hasPrefix("/") {
      return .invalid("Stream source must be a valid URL or file path")
    }

    return .valid
  }

  // MARK: - Stream Monitoring

  func getStreamHealth(
    streamName: String, completion: @escaping (Result<StreamHealth, Error>) -> Void
  ) {
    print("🚀 StreamManager: Checking health for stream '\(streamName)'")

    APIClient.shared.fetchStreamStatistics { result in
      switch result {
      case .success(let data):
        let health = self.analyzeStreamHealth(streamName: streamName, from: data)
        completion(.success(health))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func getStreamMetrics(
    streamName: String, completion: @escaping (Result<StreamMetrics, Error>) -> Void
  ) {
    print("🚀 StreamManager: Fetching metrics for stream '\(streamName)'")

    APIClient.shared.fetchStreamStatistics { result in
      switch result {
      case .success(let data):
        let metrics = self.extractStreamMetrics(streamName: streamName, from: data)
        completion(.success(metrics))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Helper Methods

  private func extractActiveStreams(from data: [String: Any]) -> [String] {
    var activeStreams: [String] = []

    if let streams = data["streams"] as? [String: Any] {
      for (streamName, streamData) in streams {
        if let stream = streamData as? [String: Any],
          let clients = stream["clients"] as? Int,
          clients > 0
        {
          activeStreams.append(streamName)
        }
      }
    }

    return activeStreams.sorted()
  }

  private func extractTags(from config: [String: Any]) -> [String] {
    if let tags = config["tags"] as? [String] {
      return tags
    } else if let tagsString = config["tags"] as? String {
      return tagsString.components(separatedBy: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return []
  }

  private func analyzeStreamHealth(streamName: String, from data: [String: Any]) -> StreamHealth {
    guard let streams = data["streams"] as? [String: Any],
      let streamData = streams[streamName] as? [String: Any]
    else {
      return StreamHealth(status: .offline, issues: ["Stream not found"])
    }

    var issues: [String] = []
    var status: StreamHealth.Status = .healthy

    // Check if stream has viewers
    let clients = streamData["clients"] as? Int ?? 0
    if clients == 0 {
      issues.append("No active viewers")
      status = .warning
    }

    // Check bandwidth
    let bandwidth = streamData["bps_out"] as? Int ?? 0
    if bandwidth == 0 && clients > 0 {
      issues.append("No outgoing bandwidth despite having viewers")
      status = .error
    }

    // Check for errors in stream data
    if let errors = streamData["errors"] as? [String], !errors.isEmpty {
      issues.append(contentsOf: errors)
      status = .error
    }

    return StreamHealth(status: status, issues: issues)
  }

  private func extractStreamMetrics(streamName: String, from data: [String: Any]) -> StreamMetrics {
    guard let streams = data["streams"] as? [String: Any],
      let streamData = streams[streamName] as? [String: Any]
    else {
      return StreamMetrics(viewers: 0, bandwidth: 0, uptime: 0, bytesTransferred: 0)
    }

    let viewers = streamData["clients"] as? Int ?? 0
    let bandwidth = streamData["bps_out"] as? Int ?? 0
    let uptime = streamData["uptime"] as? Int ?? 0
    let bytesTransferred = streamData["bytes_out"] as? Int ?? 0

    return StreamMetrics(
      viewers: viewers,
      bandwidth: bandwidth,
      uptime: uptime,
      bytesTransferred: bytesTransferred
    )
  }
}

// MARK: - Supporting Types

enum StreamValidationResult {
  case valid
  case invalid(String)

  var isValid: Bool {
    switch self {
    case .valid:
      return true
    case .invalid:
      return false
    }
  }

  var errorMessage: String? {
    switch self {
    case .valid:
      return nil
    case .invalid(let message):
      return message
    }
  }
}

struct StreamHealth {
  enum Status {
    case healthy
    case warning
    case error
    case offline
  }

  let status: Status
  let issues: [String]
}

struct StreamMetrics {
  let viewers: Int
  let bandwidth: Int  // bits per second
  let uptime: Int  // seconds
  let bytesTransferred: Int

  var formattedBandwidth: String {
    return formatBandwidth(bandwidth)
  }

  var formattedUptime: String {
    return formatDuration(uptime)
  }

  var formattedBytes: String {
    return formatBytes(bytesTransferred)
  }

  private func formatBandwidth(_ bps: Int) -> String {
    let units = ["bps", "Kbps", "Mbps", "Gbps"]
    var value = Double(bps)
    var unitIndex = 0

    while value >= 1000 && unitIndex < units.count - 1 {
      value /= 1000
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }

  private func formatBytes(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
      value /= 1024
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%d:%02d", minutes, secs)
    }
  }
}
