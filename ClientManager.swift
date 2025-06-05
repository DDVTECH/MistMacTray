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

  func disconnectClientLegacy(
    sessionId: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.disconnectClientLegacy(sessionId: sessionId) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func kickAllViewers(streamName: String, completion: @escaping (Result<Void, APIError>) -> Void) {
    print("👢 ClientManager: Kicking all viewers from stream '\(streamName)'")

    APIClient.shared.kickAllViewers(streamName: streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ All viewers kicked successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to kick viewers: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func forceReauthentication(
    streamName: String, completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    print("🔐 ClientManager: Forcing reauthentication for stream '\(streamName)'")

    APIClient.shared.forceReauthentication(streamName: streamName) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Reauthentication forced successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to force reauthentication: \(error)")
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
    print("🏷️ Tagging sessions: \(sessionIds) with tag: \(tag)")

    var successCount = 0
    var failureCount = 0
    let totalCount = sessionIds.count

    guard totalCount > 0 else {
      completion(.success(0))
      return
    }

    for sessionId in sessionIds {
      APIClient.shared.tagSession(sessionId: sessionId, tag: tag) { result in
        switch result {
        case .success:
          print("✅ Successfully tagged session \(sessionId) with \(tag)")
          successCount += 1
        case .failure(let error):
          print("❌ Failed to tag session \(sessionId): \(error)")
          failureCount += 1
        }

        // Check if all requests are complete
        if successCount + failureCount == totalCount {
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
    }
  }

  // MARK: - Client Statistics

  func fetchClientStatistics(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    APIClient.shared.fetchClientStatistics(completion: completion)
  }

  // MARK: - Client Data Processing (removed - now handled by unified state management)

  // Legacy methods removed to eliminate redundant code paths
  // All data processing now happens through AppDelegate.refreshAllData() → updateCompleteState()
  // Removed: getConnectedClients, parseClientData, getClientsByStream

  // MARK: - Stream Name Validation

  private func isValidStreamName(_ streamName: String) -> Bool {
    return !streamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func updateClientsMenu() {
    print("📋 Updating clients menu...")

    // This method is also legacy and should use unified state, but keeping for now
    // getClientsByStream { result in // This line is removed
    //     switch result {
    //     case .success(let clientsByStream):
    //         print("✅ Retrieved clients for \(clientsByStream.count) streams")
    //         // Menu update would be handled by the AppDelegate or main controller
    //         // that has access to the MenuBuilder instance
    //         print("📋 Clients data ready for menu update")
    //     case .failure(let error):
    //         print("❌ Failed to retrieve clients: \(error)")
    //     }
    // }
  }

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
