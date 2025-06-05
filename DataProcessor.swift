//
//  DataProcessor.swift
//  MistTray
//

import Foundation

// Import the configuration types from DialogManager
extension DataProcessor {
  struct PushConfiguration {
    let streamName: String
    let targetURL: String
  }
}

class DataProcessor {
  static let shared = DataProcessor()

  private init() {}

  // MARK: - Stream Data Processing

  func processStreamData(_ data: [String: Any]) -> ProcessedStreamData {
    var activeStreams: [String] = []
    var streamStats: [String: Any] = [:]
    var allStreams: [String: Any] = [:]
    var serverTotals: [String: Any] = [:]

    // Process active streams
    if let streams = data["active_streams"] as? [String: Any] {
      for (streamName, streamData) in streams {
        guard let streamInfo = streamData as? [String: Any] else { continue }

        activeStreams.append(streamName)
        streamStats[streamName] = streamInfo

        // Extract stream statistics
        let clients = streamInfo["clients"] as? Int ?? 0
        let bandwidth = streamInfo["bps_out"] as? Int ?? 0
        let uptime = streamInfo["uptime"] as? Int ?? 0

        streamStats[streamName] = [
          "clients": clients,
          "bps_out": bandwidth,
          "uptime": uptime,
          "formatted_bandwidth": formatBandwidth(bandwidth),
          "formatted_uptime": formatDuration(uptime),
        ]
      }
    }

    // Process all configured streams
    if let config = data["config"] as? [String: Any],
      let streams = config["streams"] as? [String: Any]
    {
      allStreams = streams
    }

    // Process server totals
    if let totals = data["totals"] as? [String: Any] {
      serverTotals = totals
    }

    return ProcessedStreamData(
      activeStreams: activeStreams.sorted(),
      streamStats: streamStats,
      allStreams: allStreams,
      serverTotals: serverTotals
    )
  }

  // MARK: - Push Data Processing

  func processPushData(_ data: [String: Any]) -> ProcessedPushData {
    var activePushes: [String: Any] = [:]

    if let pushes = data["active_pushes"] as? [String: Any] {
      for (pushKey, pushData) in pushes {
        guard let pushInfo = pushData as? [String: Any] else { continue }

        // Enhance push data with formatted information
        var enhancedPushInfo = pushInfo

        if let activeSeconds = pushInfo["active_seconds"] as? Int {
          enhancedPushInfo["formatted_duration"] = formatDuration(activeSeconds)
        }

        if let bytes = pushInfo["bytes"] as? Int {
          enhancedPushInfo["formatted_bytes"] = formatBytes(bytes)
        }

        if let bps = pushInfo["bps"] as? Int {
          enhancedPushInfo["formatted_bandwidth"] = formatBandwidth(bps)
        }

        activePushes[pushKey] = enhancedPushInfo
      }
    }

    return ProcessedPushData(activePushes: activePushes)
  }

  // MARK: - Client Data Processing

  func processClientData(_ data: [String: Any]) -> ProcessedClientData {
    var connectedClients: [String: Any] = [:]
    var clientsByStream: [String: [String: Any]] = [:]

    if let clients = data["clients"] as? [String: Any] {
      for (clientId, clientData) in clients {
        guard let clientInfo = clientData as? [String: Any] else { continue }

        // Enhance client data with formatted information
        var enhancedClientInfo = clientInfo

        if let connTime = clientInfo["conntime"] as? Int {
          let duration = Int(Date().timeIntervalSince1970) - connTime
          enhancedClientInfo["formatted_duration"] = formatDuration(duration)
        }

        if let bytes = clientInfo["bytes_down"] as? Int {
          enhancedClientInfo["formatted_bytes"] = formatBytes(bytes)
        }

        if let bps = clientInfo["bps_down"] as? Int {
          enhancedClientInfo["formatted_bandwidth"] = formatBandwidth(bps)
        }

        connectedClients[clientId] = enhancedClientInfo

        // Group by stream
        if let streamName = clientInfo["stream"] as? String {
          if clientsByStream[streamName] == nil {
            clientsByStream[streamName] = [:]
          }
          clientsByStream[streamName]![clientId] = enhancedClientInfo
        }
      }
    }

    return ProcessedClientData(
      connectedClients: connectedClients,
      clientsByStream: clientsByStream
    )
  }

  // MARK: - Protocol Data Processing

  func processProtocolData(_ data: [String: Any]) -> ProcessedProtocolData {
    var protocolConfig: [String: Any] = [:]
    var enabledProtocols: [String] = []
    var disabledProtocols: [String] = []

    if let config = data["config"] as? [String: Any],
      let protocols = config["protocols"] as? [[String: Any]]
    {

      protocolConfig["protocols"] = protocols

      for protocolInfo in protocols {
        guard let connector = protocolInfo["connector"] as? String else { continue }

        let port = protocolInfo["port"] as? Int ?? 0
        if port > 0 {
          enabledProtocols.append(connector)
        } else {
          disabledProtocols.append(connector)
        }
      }
    }

    return ProcessedProtocolData(
      protocolConfig: protocolConfig,
      enabledProtocols: enabledProtocols.sorted(),
      disabledProtocols: disabledProtocols.sorted()
    )
  }

  // MARK: - Server Statistics Processing

  func processServerStatistics(_ data: [String: Any]) -> ProcessedServerStats {
    var stats = ProcessedServerStats()

    if let totals = data["totals"] as? [String: Any] {
      stats.totalClients = totals["clients"] as? Int ?? 0
      stats.totalBandwidth = totals["bps_out"] as? Int ?? 0
      stats.uptime = totals["uptime"] as? Int ?? 0
      stats.totalStreams = totals["streams"] as? Int ?? 0

      // Format values
      stats.formattedBandwidth = formatBandwidth(stats.totalBandwidth)
      stats.formattedUptime = formatDuration(stats.uptime)
    }

    if let memory = data["memory"] as? [String: Any] {
      stats.memoryUsage = memory["used"] as? Int ?? 0
      stats.memoryTotal = memory["total"] as? Int ?? 0
      stats.formattedMemory = formatBytes(stats.memoryUsage)
    }

    if let cpu = data["cpu"] as? [String: Any] {
      stats.cpuUsage = cpu["usage"] as? Double ?? 0.0
    }

    return stats
  }

  // MARK: - Configuration Data Processing

  func processConfigurationData(_ data: [String: Any]) -> ProcessedConfigData {
    var config = ProcessedConfigData()

    if let configData = data["config"] as? [String: Any] {
      config.rawConfig = configData

      // Extract key configuration sections
      if let streams = configData["streams"] as? [String: Any] {
        config.streamCount = streams.count
        config.streamNames = Array(streams.keys).sorted()
      }

      if let protocols = configData["protocols"] as? [[String: Any]] {
        config.protocolCount = protocols.count
        config.enabledProtocolCount = protocols.filter { ($0["port"] as? Int ?? 0) > 0 }.count
      }

      if let triggers = configData["triggers"] as? [String: Any] {
        config.triggerCount = triggers.count
      }

      // Extract server settings
      config.serverName = configData["name"] as? String ?? "MistServer"
      config.serverPort = configData["port"] as? Int ?? 4242
      config.serverInterface = configData["interface"] as? String ?? "0.0.0.0"
    }

    return config
  }

  // MARK: - Data Formatting Utilities

  func formatBandwidth(_ bps: Int) -> String {
    let units = ["bps", "Kbps", "Mbps", "Gbps"]
    var value = Double(bps)
    var unitIndex = 0

    while value >= 1000 && unitIndex < units.count - 1 {
      value /= 1000
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }

  func formatBytes(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
      value /= 1024
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }

  func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%d:%02d", minutes, secs)
    }
  }

  func formatConnectionTime(_ timestamp: Int) -> String {
    let connectionDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter.string(from: connectionDate)
  }

  func formatPercentage(_ value: Double) -> String {
    return String(format: "%.1f%%", value)
  }

  // MARK: - Data Validation

  func validateStreamConfiguration(_ config: [String: Any]) -> ValidationResult {
    var errors: [String] = []
    var warnings: [String] = []

    // Check required fields
    guard let source = config["source"] as? String, !source.isEmpty else {
      errors.append("Stream source is required")
      return ValidationResult(isValid: false, errors: errors, warnings: warnings)
    }

    // Validate source format
    if !isValidSourceURL(source) {
      warnings.append("Source URL format may not be supported")
    }

    // Check for common issues
    if source.hasPrefix("rtmp://") && !source.contains("/live/") {
      warnings.append("RTMP URLs typically require a '/live/' path")
    }

    return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
  }

  func validatePushConfiguration(_ config: PushConfiguration) -> ValidationResult {
    var errors: [String] = []
    var warnings: [String] = []

    // Validate target URL
    if !isValidTargetURL(config.targetURL) {
      errors.append("Invalid target URL format")
    }

    // Check for common issues
    if config.targetURL.hasPrefix("rtmp://") && !config.targetURL.contains("/live/") {
      warnings.append("RTMP URLs typically require a '/live/' path")
    }

    return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
  }

  private func isValidSourceURL(_ url: String) -> Bool {
    let supportedSchemes = ["rtmp://", "rtsp://", "http://", "https://", "push://", "file://", "/"]
    return supportedSchemes.contains { url.hasPrefix($0) }
  }

  private func isValidTargetURL(_ url: String) -> Bool {
    let supportedSchemes = ["rtmp://", "rtsp://", "http://", "https://"]
    return supportedSchemes.contains { url.hasPrefix($0) }
  }

  // MARK: - Data Aggregation

  func aggregateStreamStatistics(_ streamStats: [String: Any]) -> StreamAggregateStats {
    var totalClients = 0
    var totalBandwidth = 0
    var totalUptime = 0
    var streamCount = 0

    for (_, stats) in streamStats {
      guard let streamData = stats as? [String: Any] else { continue }

      totalClients += streamData["clients"] as? Int ?? 0
      totalBandwidth += streamData["bps_out"] as? Int ?? 0
      totalUptime += streamData["uptime"] as? Int ?? 0
      streamCount += 1
    }

    let averageUptime = streamCount > 0 ? totalUptime / streamCount : 0

    return StreamAggregateStats(
      totalStreams: streamCount,
      totalClients: totalClients,
      totalBandwidth: totalBandwidth,
      averageUptime: averageUptime,
      formattedBandwidth: formatBandwidth(totalBandwidth),
      formattedAverageUptime: formatDuration(averageUptime)
    )
  }

  // MARK: - Raw Data Processing (from AppDelegate)

  func processAllStreams(_ streamsData: Any?) -> [String: Any] {
    print(
      "🔍 processAllStreams - Input type: \(type(of: streamsData)), value: \(streamsData ?? "nil")")

    // Handle null values gracefully (normal for fresh server)
    if streamsData == nil || streamsData is NSNull {
      print("📊 No streams configured")
      return [:]
    }

    guard let streams = streamsData as? [String: Any] else {
      print("❌ Invalid streams data format - expected [String: Any], got \(type(of: streamsData))")
      return [:]
    }

    print("📊 Processing \(streams.count) total streams: \(Array(streams.keys))")
    return streams
  }

  func processStreamStats(_ statsData: Any?) -> [String: Any] {
    print("🔍 processStreamStats - Input type: \(type(of: statsData)), value: \(statsData ?? "nil")")

    // Handle null values gracefully (normal for fresh server)
    if statsData == nil || statsData is NSNull {
      print("📊 No stream statistics available")
      return [:]
    }

    guard let stats = statsData as? [String: Any] else {
      print(
        "❌ Invalid stream stats data format - expected [String: Any], got \(type(of: statsData))")
      return [:]
    }

    print("📊 Processing stream statistics for \(stats.count) streams: \(Array(stats.keys))")
    return stats
  }

  func processPushList(_ pushListData: Any?) -> [String: Any] {
    print(
      "🔍 processPushList - Input type: \(type(of: pushListData)), value: \(pushListData ?? "nil")")

    // Handle null values gracefully (normal for fresh server)
    if pushListData == nil || pushListData is NSNull {
      print("📊 No pushes configured")
      return [:]
    }

    guard let pushes = pushListData as? [String: Any] else {
      print(
        "❌ Invalid push list data format - expected [String: Any], got \(type(of: pushListData))")
      return [:]
    }

    print("📊 Processing \(pushes.count) active pushes: \(Array(pushes.keys))")
    return pushes
  }

  func processClients(_ clientsData: Any?) -> [String: Any] {
    print("🔍 processClients - Input type: \(type(of: clientsData)), value: \(clientsData ?? "nil")")

    // Handle null values gracefully (normal for fresh server)
    if clientsData == nil || clientsData is NSNull {
      print("📊 No clients connected")
      return [:]
    }

    // Handle MistServer's clients data structure: {"data": <null>, "fields": [...], "time": 123}
    if let clientsDict = clientsData as? [String: Any] {
      print("🔍 Clients dict keys: \(Array(clientsDict.keys))")
      if let data = clientsDict["data"], data is NSNull {
        print("📊 No clients connected (data field is null)")
        return [:]
      } else if let data = clientsDict["data"] as? [String: Any] {
        print("📊 Processing \(data.count) connected clients: \(Array(data.keys))")
        return data
      } else {
        print("📊 Processing clients data structure with keys: \(Array(clientsDict.keys))")
        return clientsDict
      }
    }

    guard let clients = clientsData as? [String: Any] else {
      print("❌ Invalid clients data format - expected [String: Any], got \(type(of: clientsData))")
      return [:]
    }

    print("📊 Processing \(clients.count) connected clients: \(Array(clients.keys))")
    return clients
  }
}

// MARK: - Data Structures

struct ProcessedStreamData {
  let activeStreams: [String]
  let streamStats: [String: Any]
  let allStreams: [String: Any]
  let serverTotals: [String: Any]
}

struct ProcessedPushData {
  let activePushes: [String: Any]
}

struct ProcessedClientData {
  let connectedClients: [String: Any]
  let clientsByStream: [String: [String: Any]]
}

struct ProcessedProtocolData {
  let protocolConfig: [String: Any]
  let enabledProtocols: [String]
  let disabledProtocols: [String]
}

struct ProcessedServerStats {
  var totalClients: Int = 0
  var totalBandwidth: Int = 0
  var uptime: Int = 0
  var totalStreams: Int = 0
  var memoryUsage: Int = 0
  var memoryTotal: Int = 0
  var cpuUsage: Double = 0.0

  var formattedBandwidth: String = ""
  var formattedUptime: String = ""
  var formattedMemory: String = ""
  var formattedCPU: String = ""
}

struct ProcessedConfigData {
  var rawConfig: [String: Any] = [:]
  var streamCount: Int = 0
  var streamNames: [String] = []
  var protocolCount: Int = 0
  var enabledProtocolCount: Int = 0
  var triggerCount: Int = 0
  var serverName: String = ""
  var serverPort: Int = 0
  var serverInterface: String = ""
}

struct ValidationResult {
  let isValid: Bool
  let errors: [String]
  let warnings: [String]
}

struct StreamAggregateStats {
  let totalStreams: Int
  let totalClients: Int
  let totalBandwidth: Int
  let averageUptime: Int
  let formattedBandwidth: String
  let formattedAverageUptime: String
}
