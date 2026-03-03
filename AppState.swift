//
//  AppState.swift
//  MistTray
//

import Foundation

@Observable
class AppState {
  // MARK: - Server State
  var serverRunning = false
  var needsSetup = false
  var serverMode: ServerMode = .notFound

  // MARK: - Loading States
  var isTogglingServer = false
  var isRestartingServer = false
  var isStoppingPush: Set<Int> = []

  // MARK: - Data State
  var activeStreams: [String] = []
  var allStreams: [String: Any] = [:]
  var streamStats: [String: Any] = [:]
  var activePushes: [String: Any] = [:]
  var connectedClients: [String: Any] = [:]
  var lastProtocolData: [String: Any] = [:]
  var serverLogs: [[Any]] = []
  var serverCapabilities: [String: Any] = [:]
  var serverTotals: [String: Any] = [:]
  var lastRefreshDate: Date?

  // MARK: - Reset

  func resetData() {
    activeStreams = []
    allStreams = [:]
    streamStats = [:]
    activePushes = [:]
    connectedClients = [:]
    lastProtocolData = [:]
    serverLogs = []
    serverTotals = [:]
    lastRefreshDate = nil
  }

  // MARK: - Stream Computed Properties

  var sortedStreamNames: [String] {
    allStreams.keys.sorted()
  }

  var streamCount: Int {
    allStreams.count
  }

  var activeStreamCount: Int {
    activeStreams.count
  }

  var pushCount: Int {
    activePushes.count
  }

  var viewerCount: Int {
    // Prefer server-reported total; fall back to client dict count
    if let total = serverTotals["clients"] as? Int { return total }
    return connectedClients.count
  }

  func isStreamOnline(_ streamName: String) -> Bool {
    guard let data = allStreams[streamName] as? [String: Any] else { return false }
    return (data["online"] as? Int) == 1
  }

  func streamSource(_ streamName: String) -> String {
    guard let data = allStreams[streamName] as? [String: Any] else { return "Unknown" }
    return data["source"] as? String ?? "Unknown"
  }

  func streamViewerCount(_ streamName: String) -> Int {
    guard let stats = streamStats[streamName] as? [String: Any] else { return 0 }
    return stats["clients"] as? Int ?? 0
  }

  func streamBandwidth(_ streamName: String) -> Int {
    guard let stats = streamStats[streamName] as? [String: Any] else { return 0 }
    return stats["bps_out"] as? Int ?? 0
  }

  // MARK: - Push Helpers

  var sortedPushes: [(id: Int, stream: String, target: String)] {
    activePushes.compactMap { (key, value) in
      guard let data = value as? [String: Any],
            let stream = data["stream"] as? String,
            let target = data["target"] as? String
      else { return nil }
      let id = data["id"] as? Int ?? (Int(key) ?? 0)
      return (id: id, stream: stream, target: target)
    }.sorted { $0.stream < $1.stream }
  }

  // MARK: - Server Totals

  var serverUptime: Int {
    serverTotals["uptime"] as? Int ?? 0
  }

  var formattedUptime: String {
    DataProcessor.shared.formatDuration(serverUptime)
  }

  var totalBandwidthOut: Int {
    serverTotals["bps_out"] as? Int ?? 0
  }

  var formattedTotalBandwidth: String {
    DataProcessor.shared.formatBandwidth(totalBandwidthOut)
  }

  var totalBandwidthIn: Int {
    serverTotals["bps_in"] as? Int ?? 0
  }

  // MARK: - Client Helpers

  var clientsByStream: [String: [(id: String, info: [String: Any])]] {
    var grouped: [String: [(id: String, info: [String: Any])]] = [:]
    for (clientId, value) in connectedClients {
      guard let info = value as? [String: Any],
            let stream = info["stream"] as? String
      else { continue }
      grouped[stream, default: []].append((id: clientId, info: info))
    }
    for key in grouped.keys {
      grouped[key]?.sort { a, b in
        let aTime = a.info["conntime"] as? Int ?? 0
        let bTime = b.info["conntime"] as? Int ?? 0
        return aTime < bTime
      }
    }
    return grouped
  }

  var sortedClientStreamNames: [String] {
    clientsByStream.keys.sorted()
  }
}
