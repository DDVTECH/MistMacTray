//
//  MistServerManager.swift
//  MistTray
//

import Foundation

class MistServerManager {
  static let shared = MistServerManager()

  private let apiURL = "http://localhost:4242/api"

  private init() {}

  // MARK: - Server Detection

  /// Check if MistServer API is reachable (the definitive "is it running?"check)
  func checkAPIReachable(completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: apiURL) else {
      completion(false)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
    request.timeoutInterval = 3.0

    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        print("[MistServerManager] API not reachable: \(error.localizedDescription)")
        DispatchQueue.main.async { completion(false) }
        return
      }

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
        DispatchQueue.main.async { completion(true) }
      } else {
        DispatchQueue.main.async { completion(false) }
      }
    }.resume()
  }

  /// Synchronous check — tries API first, falls back to launchctl for brew
  func isMistServerRunning() -> Bool {
    // Quick synchronous check via launchctl for brew service
    if findBrewMistserver() != nil {
      let output = runShellCommandWithOutput("/bin/launchctl", arguments: ["list"])
      if output.contains("homebrew.mxcl.mistserver") {
        return true
      }
    }

    // Fallback: check if anything is listening on port 4242
    let output = runShellCommandWithOutput("/usr/sbin/lsof", arguments: ["-i", ":4242", "-sTCP:LISTEN"])
    return output.contains("LISTEN")
  }

  /// Check if MistServer is installed via Homebrew
  func findBrewMistserver() -> String? {
    let armPath = "/opt/homebrew/bin/MistController"
    if FileManager.default.isExecutableFile(atPath: armPath) {
      return armPath
    }
    let intelPath = "/usr/local/bin/MistController"
    if FileManager.default.isExecutableFile(atPath: intelPath) {
      return intelPath
    }
    return nil
  }

  /// Check if Homebrew itself is installed
  func findBrew() -> String? {
    let armBrew = "/opt/homebrew/bin/brew"
    if FileManager.default.isExecutableFile(atPath: armBrew) {
      return armBrew
    }
    let intelBrew = "/usr/local/bin/brew"
    if FileManager.default.isExecutableFile(atPath: intelBrew) {
      return intelBrew
    }
    return nil
  }

  // MARK: - Server Lifecycle

  func startServer(completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Starting MistServer...")

    guard let brewCmd = findBrew() else {
      print("[MistServerManager] Homebrew not found, cannot start MistServer")
      completion(false)
      return
    }

    if findBrewMistserver() == nil {
      print("[MistServerManager] MistServer not installed via Homebrew")
      completion(false)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "start", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] brew services start result: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  func stopServer(completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Stopping MistServer...")

    // Prefer API graceful shutdown — works regardless of how server was installed
    APIClient.shared.gracefulShutdown { [weak self] result in
      switch result {
      case .success:
        print("[MistServerManager] Graceful shutdown via API succeeded")
        completion(true)
      case .failure:
        print("[MistServerManager] API shutdown failed, falling back to brew services stop")
        self?.stopServerViaBrew(completion: completion)
      }
    }
  }

  private func stopServerViaBrew(completion: @escaping (Bool) -> Void) {
    guard let brewCmd = findBrew() else {
      print("[MistServerManager] Homebrew not found, cannot stop MistServer")
      completion(false)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "stop", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] brew services stop result: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  func restartServer(completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Restarting MistServer...")

    guard let brewCmd = findBrew() else {
      print("[MistServerManager] Homebrew not found, cannot restart MistServer")
      completion(false)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "restart", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] brew services restart result: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  // MARK: - Installation Status

  enum InstallStatus {
    case installed       // MistServer binary found (via Homebrew)
    case notInstalled    // No MistServer binary, but Homebrew available
    case noHomebrew      // Homebrew not installed
  }

  func installStatus() -> InstallStatus {
    if findBrewMistserver() != nil {
      return .installed
    } else if findBrew() != nil {
      return .notInstalled
    } else {
      return .noHomebrew
    }
  }

  // MARK: - Shell Command Utilities

  @discardableResult
  func runShellCommand(_ launchPath: String, arguments: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
      task.waitUntilExit()
      return task.terminationStatus
    } catch {
      print("[MistServerManager] Failed to run \(launchPath): \(error)")
      return -1
    }
  }

  func runShellCommandWithOutput(_ launchPath: String, arguments: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      task.waitUntilExit()
      return String(data: data, encoding: .utf8) ?? ""
    } catch {
      print("[MistServerManager] Failed to run \(launchPath): \(error)")
      return ""
    }
  }
}
