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
    print("StreamManager: Creating stream '\(name)' with source '\(source)'")

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
    print("StreamManager: Deleting stream '\(name)'")
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
    print("StreamManager: Nuking stream '\(name)'")
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
    name: String, config: [String: Any], originalName: String? = nil,
    stopSessions: Bool = false, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("[StreamManager] Updating stream '\(name)'")
    // Use addstream API — adding a stream with an existing name updates it
    APIClient.shared.updateStream(name: name, config: config) { result in
      switch result {
      case .success:
        // Handle rename: delete old stream
        if let oldName = originalName, oldName != name {
          APIClient.shared.deleteStream(oldName) { _ in }
        }
        // Handle stop sessions
        if stopSessions {
          APIClient.shared.kickAllViewers(streamName: originalName ?? name) { _ in }
        }
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func nukeStream(_ streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("Nuking stream: \(streamName)")

    APIClient.shared.nukeStream(streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("Stream \(streamName) nuked successfully")
          completion(.success(()))
        case .failure(let error):
          print("Failed to nuke stream \(streamName): \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Stream Tags Management

  func updateStreamTags(
    streamName: String, tags: [String], completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("[StreamManager] Updating tags for stream '\(streamName)': \(tags)")

    // Fetch current tags, then diff and apply changes
    APIClient.shared.fetchStreamTags(for: streamName) { result in
      switch result {
      case .success(let currentTags):
        let toAdd = tags.filter { !currentTags.contains($0) }
        let toRemove = currentTags.filter { !tags.contains($0) }

        let group = DispatchGroup()
        var errors: [Error] = []

        for tag in toAdd {
          group.enter()
          APIClient.shared.addStreamTag(streamName: streamName, tagName: tag) { result in
            if case .failure(let error) = result { errors.append(error) }
            group.leave()
          }
        }

        for tag in toRemove {
          group.enter()
          APIClient.shared.removeStreamTag(streamName: streamName, tagName: tag) { result in
            if case .failure(let error) = result { errors.append(error) }
            group.leave()
          }
        }

        group.notify(queue: .main) {
          if let firstError = errors.first {
            completion(.failure(firstError))
          } else {
            completion(.success(()))
          }
        }

      case .failure(let error):
        completion(.failure(error))
      }
    }
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
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .invalid("Stream name cannot be empty")
    }

    let invalidChars = CharacterSet(charactersIn: "!@#$%^&*()+={}[]|\\:;\"'<>?,./")
    if name.rangeOfCharacter(from: invalidChars) != nil {
      return .invalid("Stream name contains invalid characters")
    }

    if name.count > 50 {
      return .invalid("Stream name is too long (max 50 characters)")
    }

    return .valid
  }

  func validateStreamSource(_ source: String) -> StreamValidationResult {
    if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .invalid("Stream source cannot be empty")
    }

    let commonProtocols = ["rtmp://", "rtsp://", "http://", "https://", "file://", "push://"]
    let hasValidProtocol = commonProtocols.contains { source.lowercased().hasPrefix($0) }

    if !hasValidProtocol && !source.hasPrefix("/") {
      return .invalid("Stream source must be a valid URL or file path")
    }

    return .valid
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
