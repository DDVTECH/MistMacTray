//
//  UtilityManager.swift
//  MistTray
//

import Cocoa
import Foundation

class UtilityManager {
  static let shared = UtilityManager()

  private init() {}

  // MARK: - Data Processing

  func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }

  func formatConnectionTime(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%02d:%02d", minutes, secs)
    }
  }

  func formatBandwidth(_ bps: Int) -> String {
    let kbps = Double(bps) / 1024.0
    let mbps = kbps / 1024.0
    let gbps = mbps / 1024.0

    if gbps >= 1.0 {
      return String(format: "%.2f Gbps", gbps)
    } else if mbps >= 1.0 {
      return String(format: "%.2f Mbps", mbps)
    } else if kbps >= 1.0 {
      return String(format: "%.1f Kbps", kbps)
    } else {
      return "\(bps) bps"
    }
  }

  // MARK: - Shell Commands

  func runShellCommand(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/sh"

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      return (
        output: output.trimmingCharacters(in: .whitespacesAndNewlines),
        exitCode: task.terminationStatus
      )
    } catch {
      return (output: "Error: \(error.localizedDescription)", exitCode: -1)
    }
  }

  func runShellCommandAsync(_ command: String, completion: @escaping (String, Int32) -> Void) {
    DispatchQueue.global(qos: .background).async {
      let result = self.runShellCommand(command)
      DispatchQueue.main.async {
        completion(result.output, result.exitCode)
      }
    }
  }

  // MARK: - File Operations

  func createDirectoryIfNeeded(at url: URL) -> Bool {
    do {
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true, attributes: nil)
      return true
    } catch {
      print("❌ Failed to create directory: \(error)")
      return false
    }
  }

  func fileExists(at path: String) -> Bool {
    return FileManager.default.fileExists(atPath: path)
  }

  func removeFile(at path: String) -> Bool {
    do {
      try FileManager.default.removeItem(atPath: path)
      return true
    } catch {
      print("❌ Failed to remove file: \(error)")
      return false
    }
  }

  func copyFile(from sourcePath: String, to destinationPath: String) -> Bool {
    do {
      try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
      return true
    } catch {
      print("❌ Failed to copy file: \(error)")
      return false
    }
  }

  // MARK: - URL Validation

  func isValidURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return url.scheme != nil && url.host != nil
  }

  func isValidStreamingURL(_ urlString: String) -> Bool {
    let validSchemes = ["rtmp", "rtmps", "srt", "udp", "http", "https", "file"]
    guard let url = URL(string: urlString),
      let scheme = url.scheme?.lowercased()
    else { return false }
    return validSchemes.contains(scheme)
  }

  // MARK: - String Utilities

  func sanitizeStreamName(_ name: String) -> String {
    // Remove invalid characters for stream names
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return name.components(separatedBy: allowedCharacters.inverted).joined()
  }

  func truncateString(_ string: String, maxLength: Int) -> String {
    if string.count <= maxLength {
      return string
    }
    let truncated = String(string.prefix(maxLength - 3))
    return truncated + "..."
  }

  // MARK: - Network Utilities

  func isPortAvailable(_ port: Int) -> Bool {
    let result = runShellCommand("lsof -i :\(port)")
    return result.output.isEmpty
  }

  func getLocalIPAddress() -> String? {
    let result = runShellCommand(
      "ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}'")
    return result.output.isEmpty ? nil : result.output
  }

  // MARK: - System Information

  func getSystemInfo() -> SystemInfo {
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let hostName = ProcessInfo.processInfo.hostName
    let uptime = ProcessInfo.processInfo.systemUptime

    return SystemInfo(
      osVersion: osVersion,
      hostName: hostName,
      uptime: Int(uptime),
      localIP: getLocalIPAddress()
    )
  }

  // MARK: - Application Utilities

  func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }

  func showInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func getTotalViewers(from clientsData: [String: Any]) -> Int {
    return clientsData.count
  }

  func getDefaultPort() -> Int {
    return 4242
  }

  func generateStatusText(
    isRunning: Bool, activeStreams: [String], activePushes: [String: Any], totalViewers: Int,
    serverType: String
  ) -> String {
    if !isRunning {
      return "MistServer: Stopped"
    }

    var statusText = "MistServer (\(serverType)): Running"

    if !activeStreams.isEmpty || !activePushes.isEmpty {
      var details: [String] = []

      if !activeStreams.isEmpty {
        details.append("\(activeStreams.count) streams")
      }

      if !activePushes.isEmpty {
        details.append("\(activePushes.count) pushes")
      }

      if totalViewers > 0 {
        details.append("\(totalViewers) viewers")
      }

      if !details.isEmpty {
        statusText += " (\(details.joined(separator: ", ")))"
      }
    }

    return statusText
  }

  // MARK: - Protocol Utilities

  func getDefaultPort(for protocolName: String) -> String {
    switch protocolName.uppercased() {
    case "RTMP": return "1935"
    case "HLS": return "8080"
    case "DASH": return "8080"
    case "WEBRTC": return "8080"
    case "SRT": return "9999"
    case "RTSP": return "554"
    case "HTTP": return "8080"
    case "WEBSOCKET": return "8080"
    default: return "8080"
    }
  }
}

// MARK: - Supporting Types

struct SystemInfo {
  let osVersion: String
  let hostName: String
  let uptime: Int
  let localIP: String?

  var formattedUptime: String {
    return UtilityManager.shared.formatConnectionTime(uptime)
  }
}
