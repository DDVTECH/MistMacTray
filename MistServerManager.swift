//
//  MistServerManager.swift
//  MistTray
//

import Foundation

// MARK: - Server Mode

enum ServerMode: Equatable {
  case brew                // Managed by Homebrew (brew services start/stop/restart)
  case binary(String)      // Binary found at path, run directly
  case external            // API responding on 4242 but no binary found (dev env, Docker, etc.)
  case notFound            // Nothing detected

  var canStart: Bool {
    switch self {
    case .brew, .binary: return true
    case .external, .notFound: return false
    }
  }

  var canRestart: Bool {
    switch self {
    case .brew, .binary: return true
    case .external, .notFound: return false
    }
  }

  var description: String {
    switch self {
    case .brew: return "Homebrew"
    case .binary(let path): return "Binary (\(path))"
    case .external: return "External"
    case .notFound: return "Not Found"
    }
  }

  var shortDescription: String {
    switch self {
    case .brew: return "Homebrew"
    case .binary: return "Binary"
    case .external: return "External"
    case .notFound: return "Not Found"
    }
  }
}

class MistServerManager {
  static let shared = MistServerManager()

  private let apiURL = "http://localhost:4242/api"
  private let launchAgentLabel = "com.ddvtech.mistserver"

  private init() {}

  // MARK: - Server Mode Detection

  func detectServerMode() -> ServerMode {
    // 1. Check if brew services manages mistserver
    if isBrewServiceRegistered() {
      return .brew
    }

    // 2. Check for MistController binary at known paths
    if let path = findMistControllerBinary() {
      return .binary(path)
    }

    // 3. Check if something is already listening on port 4242
    if isPortListening(4242) {
      return .external
    }

    return .notFound
  }

  func isBrewServiceRegistered() -> Bool {
    guard let brewCmd = findBrew() else { return false }
    let output = runShellCommandWithOutput(brewCmd, arguments: ["services", "list"])
    // brew services list output has "mistserver" as first column when registered
    for line in output.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("mistserver ") || trimmed.hasPrefix("mistserver\t") {
        return true
      }
    }
    return false
  }

  func findMistControllerBinary() -> String? {
    // Check custom path first
    if let custom = UserDefaults.standard.string(forKey: "CustomBinaryPath"),
       !custom.isEmpty,
       FileManager.default.isExecutableFile(atPath: custom) {
      return custom
    }
    // Known install locations
    let paths = [
      "/opt/homebrew/bin/MistController",
      "/usr/local/bin/MistController",
      "/usr/bin/MistController",
    ]
    for path in paths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }
    return nil
  }

  func isPortListening(_ port: Int) -> Bool {
    let output = runShellCommandWithOutput(
      "/usr/sbin/lsof", arguments: ["-i", ":\(port)", "-sTCP:LISTEN"])
    return output.contains("LISTEN")
  }

  // MARK: - LaunchAgent Plist

  func launchAgentPlistPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
  }

  func hasLaunchAgentPlist() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPlistPath())
  }

  // MARK: - Config File Detection

  func findConfigFile() -> String {
    // Check custom path
    if let custom = UserDefaults.standard.string(forKey: "CustomConfigPath"),
       !custom.isEmpty,
       FileManager.default.fileExists(atPath: custom) {
      return custom
    }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let locations = [
      "\(home)/Library/Application Support/MistServer/config.json",
      "/etc/mistserver.conf",
      "/usr/local/etc/mistserver.conf",
    ]

    for path in locations {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    // Default location for macOS
    return "\(home)/Library/Application Support/MistServer/config.json"
  }

  func ensureConfigDirectory() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let dir = "\(home)/Library/Application Support/MistServer"
    if !FileManager.default.fileExists(atPath: dir) {
      try? FileManager.default.createDirectory(
        atPath: dir, withIntermediateDirectories: true)
    }
  }

  // MARK: - Server Running Check

  func isMistServerRunning() -> Bool {
    isPortListening(4242)
  }

  func isMistServerRunning(mode: ServerMode) -> Bool {
    switch mode {
    case .brew:
      let output = runShellCommandWithOutput("/bin/launchctl", arguments: ["list"])
      if output.contains("homebrew.mxcl.mistserver") {
        return true
      }
      return isPortListening(4242)
    case .binary:
      if hasLaunchAgentPlist() {
        let output = runShellCommandWithOutput("/bin/launchctl", arguments: ["list"])
        if output.contains(launchAgentLabel) {
          return true
        }
      }
      return isPortListening(4242)
    case .external:
      return isPortListening(4242)
    case .notFound:
      return isPortListening(4242)
    }
  }

  /// Check if MistServer API is reachable (async)
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

  // MARK: - Homebrew Helpers

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

  // MARK: - Server Lifecycle (Mode-Aware)

  func startServer(mode: ServerMode, completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Starting MistServer (mode: \(mode.shortDescription))...")

    switch mode {
    case .brew:
      startServerBrew(completion: completion)
    case .binary(let path):
      startServerBinary(path: path, completion: completion)
    case .external, .notFound:
      print("[MistServerManager] Cannot start in \(mode.shortDescription) mode")
      completion(false)
    }
  }

  func stopServer(mode: ServerMode, completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Stopping MistServer (mode: \(mode.shortDescription))...")

    switch mode {
    case .brew:
      stopServerBrew(completion: completion)
    case .binary:
      stopServerBinary(completion: completion)
    case .external:
      // External mode: API shutdown only, no pkill (we didn't start it)
      stopServerViaAPI(completion: completion)
    case .notFound:
      completion(false)
    }
  }

  func restartServer(mode: ServerMode, completion: @escaping (Bool) -> Void) {
    print("[MistServerManager] Restarting MistServer (mode: \(mode.shortDescription))...")

    switch mode {
    case .brew:
      restartServerBrew(completion: completion)
    case .binary(let path):
      stopServerBinary { [weak self] _ in
        // Wait for process to fully stop, then start again
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
          self?.startServerBinary(path: path, completion: completion)
        }
      }
    case .external:
      // External: can only stop, not restart
      print("[MistServerManager] Cannot restart external instance")
      completion(false)
    case .notFound:
      completion(false)
    }
  }

  // MARK: - Brew Lifecycle

  private func startServerBrew(completion: @escaping (Bool) -> Void) {
    guard let brewCmd = findBrew() else {
      completion(false)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "start", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] brew services start: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  private func stopServerBrew(completion: @escaping (Bool) -> Void) {
    // Must use `brew services stop` first to unregister from launchd.
    // If we only do API graceful shutdown, launchd will auto-restart the process
    // because `brew services start` registered it as a managed service.
    guard let brewCmd = findBrew() else {
      stopServerViaAPI(completion: completion)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "stop", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        if result == 0 {
          print("[MistServerManager] brew services stop succeeded")
          completion(true)
        } else {
          print("[MistServerManager] brew services stop failed, trying API shutdown")
          self?.stopServerViaAPI(completion: completion)
        }
      }
    }
  }

  private func restartServerBrew(completion: @escaping (Bool) -> Void) {
    guard let brewCmd = findBrew() else {
      completion(false)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand(brewCmd, arguments: ["services", "restart", "mistserver"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] brew services restart: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  // MARK: - Binary Lifecycle

  private func startServerBinary(path: String, completion: @escaping (Bool) -> Void) {
    if hasLaunchAgentPlist() {
      // Use launchctl to load the plist (handles KeepAlive properly)
      let plistPath = launchAgentPlistPath()
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let result = self?.runShellCommand("/bin/launchctl", arguments: ["load", plistPath]) ?? -1
        DispatchQueue.main.async {
          let success = result == 0
          print("[MistServerManager] launchctl load: \(success ? "success" : "failed")")
          completion(success)
        }
      }
    } else {
      // Run binary directly with config path
      ensureConfigDirectory()
      let configPath = findConfigFile()
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-c", configPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
          try task.run()
          // Don't waitUntilExit — it's a daemon process
          Thread.sleep(forTimeInterval: 1.0)
          let running = self?.isPortListening(4242) ?? false
          DispatchQueue.main.async {
            print("[MistServerManager] Binary start: \(running ? "success" : "failed")")
            completion(running)
          }
        } catch {
          print("[MistServerManager] Failed to start binary: \(error)")
          DispatchQueue.main.async { completion(false) }
        }
      }
    }
  }

  private func stopServerBinary(completion: @escaping (Bool) -> Void) {
    if hasLaunchAgentPlist() {
      // Use launchctl to unload (prevents KeepAlive auto-restart)
      let plistPath = launchAgentPlistPath()
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let result = self?.runShellCommand("/bin/launchctl", arguments: ["unload", plistPath]) ?? -1
        DispatchQueue.main.async {
          if result == 0 {
            print("[MistServerManager] launchctl unload succeeded")
            completion(true)
          } else {
            print("[MistServerManager] launchctl unload failed, trying API shutdown")
            self?.stopServerViaAPI(completion: completion)
          }
        }
      }
    } else {
      // API graceful shutdown, then pkill fallback
      stopServerViaAPI(completion: completion)
    }
  }

  // MARK: - Shared Stop Helpers

  private func stopServerViaAPI(completion: @escaping (Bool) -> Void) {
    APIClient.shared.gracefulShutdown { [weak self] result in
      switch result {
      case .success:
        print("[MistServerManager] Graceful shutdown via API succeeded")
        completion(true)
      case .failure:
        print("[MistServerManager] API shutdown failed, trying pkill")
        self?.killMistServerProcess(completion: completion)
      }
    }
  }

  private func killMistServerProcess(completion: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand("/usr/bin/pkill", arguments: ["-f", "MistController"]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] pkill MistController: \(success ? "success" : "no process found")")
        completion(success)
      }
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
