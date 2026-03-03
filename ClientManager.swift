//
//  ClientManager.swift
//  MistTray
//

import Foundation

class ClientManager {
  static let shared = ClientManager()

  private init() {}

  // MARK: - Client Operations

  func disconnectClient(sessionId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    APIClient.shared.disconnectClient(sessionId: sessionId) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func kickAllViewers(streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("ClientManager: Kicking all viewers from stream '\(streamName)'")

    APIClient.shared.kickAllViewers(streamName: streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("All viewers kicked successfully")
          completion(.success(()))
        case .failure(let error):
          print("Failed to kick viewers: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func forceReauthentication(
    streamName: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    print("ClientManager: Forcing reauthentication for stream '\(streamName)'")

    APIClient.shared.forceReauthentication(streamName: streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("Reauthentication forced successfully")
          completion(.success(()))
        case .failure(let error):
          print("Failed to force reauthentication: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func tagSession(
    sessionId: String, tag: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.tagSession(sessionId: sessionId, tag: tag) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Session Tagging

  func tagSessions(
    sessionIds: [String], tag: String, completion: @escaping (Result<Int, Error>) -> Void
  ) {
    print("Tagging sessions: \(sessionIds) with tag: \(tag)")

    guard !sessionIds.isEmpty else {
      completion(.success(0))
      return
    }

    let group = DispatchGroup()
    var failureCount = 0

    for sessionId in sessionIds {
      group.enter()
      APIClient.shared.tagSession(sessionId: sessionId, tag: tag) { result in
        if case .failure(let error) = result {
          print("Failed to tag session \(sessionId): \(error)")
          failureCount += 1
        }
        group.leave()
      }
    }

    group.notify(queue: .main) {
      let successCount = sessionIds.count - failureCount
      if failureCount == 0 {
        completion(.success(successCount))
      } else {
        let error = NSError(
          domain: "ClientManager", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Tagged \(successCount) session(s), failed to tag \(failureCount) session(s)"
          ])
        completion(.failure(error))
      }
    }
  }

  // MARK: - Utilities

  func getTotalViewers(from clientsData: [String: Any]) -> Int {
    return UtilityManager.shared.getTotalViewers(from: clientsData)
  }
}

// MARK: - Supporting Types

struct ClientInfo {
  let sessionId: String
  let host: String
  let protocolName: String
  let stream: String
  let connectedTime: Int
  let bytesDown: Int
  let bytesUp: Int

  var formattedConnectedTime: String {
    return DataProcessor.shared.formatConnectionTime(connectedTime)
  }

  var formattedBytesDown: String {
    return DataProcessor.shared.formatBytes(bytesDown)
  }

  var formattedBytesUp: String {
    return DataProcessor.shared.formatBytes(bytesUp)
  }

  var displayName: String {
    return "\(host) (\(protocolName))"
  }
}
