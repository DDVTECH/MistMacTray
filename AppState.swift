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
  var needsAuth = false
  var authError: String?
  var serverMode: ServerMode = .notFound
  var discoveredInstallations: [MistInstallation] = []

  var serverURL: String = UserDefaults.standard.string(forKey: "ServerURL") ?? "http://localhost:4242" {
    didSet {
      UserDefaults.standard.set(serverURL, forKey: "ServerURL")
      APIClient.shared.baseURL = serverURL + "/api"
    }
  }

  // MARK: - Loading States
  var isTogglingServer = false
  var isRestartingServer = false
  var isStoppingPush: Set<Int> = []

  // MARK: - Update State
  var mistServerCurrentVersion: String?
  var mistServerLatestVersion: String?
  var mistServerUpdateAvailable = false
  var mistTrayLatestVersion: String?
  var mistTrayUpdateURL: URL?
  var mistTrayUpdateAvailable = false
  var lastUpdateCheck: Date?
  var isCheckingForUpdates = false
  var isInstallingTrayUpdate = false

  var mistServerBaseVersion: String? {
    guard let v = mistServerCurrentVersion else { return nil }
    // Version string can be:
    //   "3.10-6-gd648a5b49 Generic_aarch64" (git-describe + release)
    //   "3.10 Generic_aarch64"               (tagged build)
    //   "Unknown Generic_aarch64"            (no git info, e.g. brew tarball)
    //   "3.9.2"                              (from brew info fallback)
    // Extract the first token and check if it looks like a version number
    let firstToken = v.components(separatedBy: " ").first?
      .components(separatedBy: "-").first ?? v
    // Only return if it starts with a digit (is an actual version)
    if let first = firstToken.first, first.isNumber {
      return firstToken
    }
    return nil
  }

  var mistTrayCurrentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

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

  // MARK: - Protocol State
  var configuredProtocols: [[String: Any]] = []
  var availableConnectors: [String: Any] = [:]

  // MARK: - Trigger State
  var triggers: [String: Any] = [:]

  // MARK: - Variables State
  var variables: [String: Any] = [:]

  // MARK: - External Writers State
  var externalWriters: [String: Any] = [:]

  // MARK: - Camera State
  var cameras: [String: Any] = [:]

  // MARK: - Auto-Push & Push Settings
  var autoPushRules: [String: Any] = [:]
  var pushSettings: [String: Any] = [:]

  // MARK: - JWK State
  var jwkEntries: [[Any]] = []

  // MARK: - Stream Keys
  var streamKeys: [String: String] = [:]  // key → streamName mapping

  // MARK: - Refresh Callback (for snappy UX after mutations)
  var onDataChanged: (() -> Void)?

  // MARK: - Time Series History

  struct TotalsSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let clients: Int
    let bpsOut: Int
    let bpsIn: Int
  }

  struct StreamSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let viewers: Int
    let bpsOut: Int
    let bpsIn: Int
  }

  var totalsHistory: [TotalsSnapshot] = []
  var streamHistory: [String: [StreamSnapshot]] = [:]
  private static let maxHistorySize = 15

  func appendTotalsSnapshot() {
    let snapshot = TotalsSnapshot(
      timestamp: Date(),
      clients: serverTotals["clients"] as? Int ?? 0,
      bpsOut: serverTotals["bps_out"] as? Int ?? 0,
      bpsIn: serverTotals["bps_in"] as? Int ?? 0
    )
    totalsHistory.append(snapshot)
    if totalsHistory.count > Self.maxHistorySize {
      totalsHistory.removeFirst(totalsHistory.count - Self.maxHistorySize)
    }
  }

  func appendStreamSnapshots() {
    for name in activeStreams {
      let snapshot = StreamSnapshot(
        timestamp: Date(),
        viewers: streamViewerCount(name),
        bpsOut: streamBandwidth(name),
        bpsIn: streamBandwidthIn(name)
      )
      var history = streamHistory[name] ?? []
      history.append(snapshot)
      if history.count > Self.maxHistorySize {
        history.removeFirst(history.count - Self.maxHistorySize)
      }
      streamHistory[name] = history
    }
    let activeSet = Set(activeStreams)
    streamHistory = streamHistory.filter { activeSet.contains($0.key) }
  }

  // MARK: - CPU / Memory Computed Properties

  var cpuUsagePercent: Double {
    if let cpuUse = serverCapabilities["cpu_use"] as? Int {
      return Double(cpuUse) / 10.0
    }
    if let cpu = serverCapabilities["cpu"] as? [String: Any],
      let use = cpu["use"] as? Int
    {
      return Double(use) / 10.0
    }
    return 0
  }

  var memoryUsedMB: Int {
    guard let mem = serverCapabilities["mem"] as? [String: Any] else { return 0 }
    return mem["used"] as? Int ?? 0
  }

  var memoryTotalMB: Int {
    guard let mem = serverCapabilities["mem"] as? [String: Any] else { return 0 }
    return mem["total"] as? Int ?? 0
  }

  var memoryPercent: Double {
    guard memoryTotalMB > 0 else { return 0 }
    return Double(memoryUsedMB) / Double(memoryTotalMB) * 100.0
  }

  var loadAverages: (one: Double, five: Double, fifteen: Double)? {
    guard let load = serverCapabilities["load"] as? [String: Any] else { return nil }
    let one = (load["one"] as? Double) ?? Double(load["one"] as? Int ?? 0) / 100.0
    let five = (load["five"] as? Double) ?? Double(load["five"] as? Int ?? 0) / 100.0
    let fifteen = (load["fifteen"] as? Double) ?? Double(load["fifteen"] as? Int ?? 0) / 100.0
    return (one, five, fifteen)
  }

  // MARK: - Client Protocol Distribution

  var clientProtocolCounts: [String: Int] {
    var counts: [String: Int] = [:]
    for (_, value) in connectedClients {
      guard let info = value as? [String: Any],
        let proto = info["protocol"] as? String
      else { continue }
      counts[proto, default: 0] += 1
    }
    return counts
  }

  var clientProtocolBandwidth: [String: Int] {
    var bandwidth: [String: Int] = [:]
    for (_, value) in connectedClients {
      guard let info = value as? [String: Any],
        let proto = info["protocol"] as? String
      else { continue }
      let down = info["downbps"] as? Int ?? 0
      let up = info["upbps"] as? Int ?? 0
      bandwidth[proto, default: 0] += down + up
    }
    return bandwidth
  }

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
    totalsHistory = []
    streamHistory = [:]
    configuredProtocols = []
    availableConnectors = [:]
    triggers = [:]
    variables = [:]
    externalWriters = [:]
    cameras = [:]
    autoPushRules = [:]
    pushSettings = [:]
    jwkEntries = []
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
    // Count non-INPUT connections from actual client data when available
    if !connectedClients.isEmpty {
      return connectedClients.values.filter { value in
        guard let info = value as? [String: Any],
              let proto = info["protocol"] as? String
        else { return true }
        return !proto.hasPrefix("INPUT:")
      }.count
    }
    // Fallback to totals when no client data available
    return serverTotals["clients"] as? Int ?? 0
  }

  /// Total connections including inputs (from server totals time-series)
  var totalConnectionCount: Int {
    serverTotals["clients"] as? Int ?? connectedClients.count
  }

  /// Input connection count from actual client data
  var inputConnectionCount: Int {
    connectedClients.values.filter { value in
      guard let info = value as? [String: Any],
            let proto = info["protocol"] as? String
      else { return false }
      return proto.hasPrefix("INPUT:")
    }.count
  }

  /// Returns the stream status code:
  /// 0=Inactive, 1=Initializing, 2=Booting, 3=Waiting, 4=Available, 5=Shutting down, 6=Invalid
  func streamStatus(_ streamName: String) -> Int {
    guard let data = allStreams[streamName] as? [String: Any] else { return 0 }
    return data["online"] as? Int ?? 0
  }

  func isStreamOnline(_ streamName: String) -> Bool {
    let status = streamStatus(streamName)
    return status >= 1 && status <= 2
  }

  func streamStatusLabel(_ streamName: String) -> (text: String, color: String) {
    // MistServer config `online` field: -1=Enabling, 0=Unavailable, 1=Active, 2=Standby
    switch streamStatus(streamName) {
    case -1: return ("Enabling", "yellow")
    case 0: return ("Offline", "gray")
    case 1: return ("Active", "green")
    case 2: return ("Standby", "orange")
    default: return ("Unknown", "gray")
    }
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

  func streamBandwidthIn(_ streamName: String) -> Int {
    guard let stats = streamStats[streamName] as? [String: Any] else { return 0 }
    return stats["bps_in"] as? Int ?? 0
  }

  // MARK: - Push Helpers

  struct EnhancedPush: Identifiable {
    let id: Int
    let stream: String
    let target: String
    let resolvedTarget: String
    let activeMs: Int
    let bytes: Int
    let latency: Int
    let pktLossCount: Int
    let pktRetransCount: Int
    let tracks: [String]
    let logs: [[Any]]
  }

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

  var sortedEnhancedPushes: [EnhancedPush] {
    activePushes.compactMap { (key, value) in
      guard let data = value as? [String: Any],
            let stream = data["stream"] as? String,
            let target = data["target"] as? String
      else { return nil }
      let stats = data["stats"] as? [String: Any] ?? [:]
      let resolvedTarget = stats["current_target"] as? String
                        ?? data["resolved_target"] as? String
                        ?? target
      return EnhancedPush(
        id: data["id"] as? Int ?? (Int(key) ?? 0),
        stream: stream,
        target: target,
        resolvedTarget: resolvedTarget,
        activeMs: stats["active_ms"] as? Int ?? 0,
        bytes: stats["bytes"] as? Int ?? 0,
        latency: stats["latency"] as? Int ?? 0,
        pktLossCount: stats["pkt_loss_count"] as? Int ?? 0,
        pktRetransCount: stats["pkt_retrans_count"] as? Int ?? 0,
        tracks: stats["tracks"] as? [String] ?? [],
        logs: data["logs"] as? [[Any]] ?? []
      )
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

  // MARK: - Protocol Computed Properties

  /// Normalize the online field which MistServer may return as Int, Bool, or String.
  func normalizeOnlineState(_ value: Any?) -> Int {
    if let i = value as? Int { return i }
    if let b = value as? Bool { return b ? 1 : 0 }
    if let s = value as? String {
      let lower = s.lowercased()
      if lower == "online" || lower == "enabled" { return 1 }
      if lower == "starting" || lower == "pending" { return 2 }
    }
    return -1 // unknown / not reported
  }

  /// Check if a connector is HTTP-based (depends on HTTP/HTTPS connector).
  private func isHTTPBased(_ connectorName: String) -> Bool {
    if let connectors = serverCapabilities["connectors"] as? [String: Any],
       let info = connectors[connectorName] as? [String: Any] {
      // Check deps field
      if let deps = info["deps"] as? String, !deps.isEmpty {
        return deps.range(of: "http", options: .caseInsensitive) != nil
      }
      if let deps = info["deps"] as? [String] {
        return deps.contains { $0.range(of: "http", options: .caseInsensitive) != nil }
      }
    }
    // Fallback: match known HTTP-based connector names
    let lower = connectorName.lowercased()
    let httpBased = ["hls", "dash", "cmaf", "webrtc", "wss", "mss", "mp4", "jpg",
                     "webm", "flv", "ogg", "aac", "mp3", "wav", "h264", "hds"]
    return httpBased.contains { lower.contains($0) }
  }

  var sortedProtocols: [(index: Int, connector: String, port: Int, online: Int)] {
    configuredProtocols.enumerated().compactMap { (index, proto) in
      guard let connector = proto["connector"] as? String else { return nil }
      let port = proto["port"] as? Int ?? 0
      var online = normalizeOnlineState(proto["online"])

      // HTTP-based protocols without their own online state inherit from
      // whatever HTTP/HTTPS connector is configured.
      if online == -1 && isHTTPBased(connector) {
        let httpOnline = configuredProtocols.contains { p in
          guard let c = p["connector"] as? String else { return false }
          let upper = c.uppercased()
          return (upper == "HTTP" || upper == "HTTPS") && normalizeOnlineState(p["online"]) == 1
        }
        online = httpOnline ? 1 : 0
      }

      return (index: index, connector: connector, port: port, online: max(online, 0))
    }
  }

  // MARK: - Trigger Computed Properties

  var sortedTriggerNames: [String] {
    triggers.keys.sorted()
  }

  var triggerCount: Int {
    triggers.values.reduce(0) { total, value in
      total + ((value as? [Any])?.count ?? 0)
    }
  }

  // MARK: - Variable Computed Properties

  var sortedVariableNames: [String] {
    variables.keys.sorted()
  }

  // MARK: - Writer Protocol Helpers

  /// Combined list of all available writer protocols (internal + external)
  var writerProtocols: [String] {
    var protocols: [String] = []
    // Internal writers from capabilities
    if let internal_ = serverCapabilities["internal_writers"] as? [String] {
      protocols.append(contentsOf: internal_.map { $0 + "://" })
    }
    // External writers
    for (_, value) in externalWriters {
      if let writer = value as? [String: Any],
         let protos = writer["protocols"] as? [String] {
        protocols.append(contentsOf: protos.map { $0 + "://" })
      } else if let writer = value as? [Any], writer.count >= 3,
                let protos = writer[2] as? [String] {
        protocols.append(contentsOf: protos.map { $0 + "://" })
      }
    }
    return protocols
  }
}
