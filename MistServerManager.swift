//
//  MistServerManager.swift
//  MistTray
//

import AppKit
import Foundation

// MARK: - Server Mode

enum ServerMode: Equatable, Hashable {
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

struct MistInstallation: Equatable, Hashable, Identifiable {
  var id: String { key }
  let key: String      // "brew", "binary:/usr/local/bin/MistController", etc.
  let mode: ServerMode
  let label: String    // "Homebrew", "PKG Install", etc.
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

  // MARK: - Multi-Installation Discovery

  func detectAllInstallations() -> [MistInstallation] {
    var installations: [MistInstallation] = []
    let brewRegistered = isBrewServiceRegistered()
    let isArmBrew = findBrew() == "/opt/homebrew/bin/brew"

    // Check Homebrew
    if brewRegistered {
      installations.append(MistInstallation(
        key: "brew", mode: .brew, label: "Homebrew"))
    }

    // Check binary paths
    if let custom = UserDefaults.standard.string(forKey: "CustomBinaryPath"),
       !custom.isEmpty,
       FileManager.default.isExecutableFile(atPath: custom) {
      installations.append(MistInstallation(
        key: "binary:\(custom)", mode: .binary(custom), label: "Custom (\(custom))"))
    }

    let knownPaths: [(path: String, label: String, skipIfBrew: Bool)] = [
      ("/opt/homebrew/bin/MistController", "Homebrew (ARM)", true),
      ("/usr/local/bin/MistController", isArmBrew ? "PKG Install" : "Homebrew (Intel)", !isArmBrew),
      ("/usr/bin/MistController", "System", false),
    ]

    for entry in knownPaths {
      // Skip paths already managed by brew
      if entry.skipIfBrew && brewRegistered { continue }
      if FileManager.default.isExecutableFile(atPath: entry.path) {
        let key = "binary:\(entry.path)"
        if !installations.contains(where: { $0.key == key }) {
          installations.append(MistInstallation(
            key: key, mode: .binary(entry.path), label: entry.label))
        }
      }
    }

    // Check for external instance (port 4242 responding, no binary found)
    if installations.isEmpty && isPortListening(4242) {
      installations.append(MistInstallation(
        key: "external", mode: .external, label: "External"))
    }

    return installations
  }

  func resolveActiveMode(
    installations: [MistInstallation], preference: String?
  ) -> ServerMode {
    if let pref = preference,
       let match = installations.first(where: { $0.key == pref }) {
      return match.mode
    }
    return installations.first?.mode ?? .notFound
  }

  func loadPreferredInstallation() -> String? {
    UserDefaults.standard.string(forKey: "PreferredInstallation")
  }

  func savePreferredInstallation(_ key: String) {
    UserDefaults.standard.set(key, forKey: "PreferredInstallation")
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
    // Direct TCP connect — works regardless of process owner (root vs user)
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return false }
    defer { Darwin.close(sock) }
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    return withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    } == 0
  }

  // MARK: - LaunchAgent / LaunchDaemon Plist

  private let systemDaemonPlistPath = "/Library/LaunchDaemons/com.ddvtech.mistserver.plist"

  func launchAgentPlistPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
  }

  func hasLaunchAgentPlist() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPlistPath())
  }

  func hasSystemLaunchDaemon() -> Bool {
    FileManager.default.fileExists(atPath: systemDaemonPlistPath)
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
      if hasSystemLaunchDaemon() {
        // Check if the system daemon is loaded (doesn't require root to query)
        let output = runShellCommandWithOutput(
          "/bin/launchctl", arguments: ["print", "system/\(launchAgentLabel)"])
        if !output.isEmpty && !output.contains("Could not find service") {
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
      // User-level LaunchAgent (PKG interactive install or manual setup)
      let plistPath = launchAgentPlistPath()
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let result = self?.runShellCommand("/bin/launchctl", arguments: ["load", plistPath]) ?? -1
        DispatchQueue.main.async {
          let success = result == 0
          print("[MistServerManager] launchctl load: \(success ? "success" : "failed")")
          completion(success)
        }
      }
    } else if hasSystemLaunchDaemon() {
      // System-level LaunchDaemon (PKG headless install) — needs admin privileges
      startSystemDaemon(completion: completion)
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
      // User-level LaunchAgent — no admin needed
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
    } else if hasSystemLaunchDaemon() {
      // System-level LaunchDaemon — needs admin privileges
      stopSystemDaemon(completion: completion)
    } else {
      // API graceful shutdown, then pkill fallback
      stopServerViaAPI(completion: completion)
    }
  }

  // MARK: - System LaunchDaemon Management (requires admin)

  private func startSystemDaemon(completion: @escaping (Bool) -> Void) {
    let plistPath = systemDaemonPlistPath
    let script = "do shell script \"launchctl load \(plistPath)\" with administrator privileges"
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand("/usr/bin/osascript", arguments: ["-e", script]) ?? -1
      DispatchQueue.main.async {
        let success = result == 0
        print("[MistServerManager] System daemon start: \(success ? "success" : "failed")")
        completion(success)
      }
    }
  }

  private func stopSystemDaemon(completion: @escaping (Bool) -> Void) {
    let plistPath = systemDaemonPlistPath
    let script = "do shell script \"launchctl unload \(plistPath)\" with administrator privileges"
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = self?.runShellCommand("/usr/bin/osascript", arguments: ["-e", script]) ?? -1
      DispatchQueue.main.async {
        if result == 0 {
          print("[MistServerManager] System daemon stop succeeded")
          completion(true)
        } else {
          print("[MistServerManager] System daemon stop failed, trying API shutdown")
          self?.stopServerViaAPI(completion: completion)
        }
      }
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

  // MARK: - Version Checking

  /// Compare two version strings like "3.10" vs "3.9.2".
  /// Returns positive if a > b, negative if a < b, 0 if equal.
  static func compareVersions(_ a: String, _ b: String) -> Int {
    let aParts = a.components(separatedBy: ".").compactMap { Int($0) }
    let bParts = b.components(separatedBy: ".").compactMap { Int($0) }
    let maxLen = max(aParts.count, bParts.count)
    for i in 0..<maxLen {
      let aVal = i < aParts.count ? aParts[i] : 0
      let bVal = i < bParts.count ? bParts[i] : 0
      if aVal != bVal { return aVal - bVal }
    }
    return 0
  }

  func checkLatestMistServerVersion(
    mode: ServerMode, completion: @escaping (String?) -> Void
  ) {
    if case .brew = mode {
      checkBrewLatestVersion(completion: completion)
    } else {
      fetchGitHubLatestTag(owner: "DDVTECH", repo: "mistserver", completion: completion)
    }
  }

  /// Check the latest available version in the Homebrew tap
  private func checkBrewLatestVersion(completion: @escaping (String?) -> Void) {
    guard let brewPath = findBrew() else {
      completion(nil)
      return
    }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self = self else { return }
      let output = self.runShellCommandWithOutput(
        brewPath, arguments: ["info", "--json=v2", "mistserver"])
      guard !output.isEmpty,
        let data = output.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let formulae = json["formulae"] as? [[String: Any]],
        let formula = formulae.first,
        let versions = formula["versions"] as? [String: Any],
        let stable = versions["stable"] as? String
      else {
        DispatchQueue.main.async { completion(nil) }
        return
      }
      DispatchQueue.main.async { completion(stable) }
    }
  }

  func checkLatestMistTrayRelease(completion: @escaping (String?, URL?) -> Void) {
    let urlString = "https://api.github.com/repos/DDVTECH/MistMacTray/releases/latest"
    guard let url = URL(string: urlString) else {
      completion(nil, nil)
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15.0

    URLSession.shared.dataTask(with: request) { data, _, error in
      guard let data = data, error == nil,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tagName = json["tag_name"] as? String
      else {
        DispatchQueue.main.async { completion(nil, nil) }
        return
      }

      var downloadURL: URL?
      if let assets = json["assets"] as? [[String: Any]] {
        for asset in assets {
          if let name = asset["name"] as? String, name.hasSuffix(".zip"),
            let urlStr = asset["browser_download_url"] as? String
          {
            downloadURL = URL(string: urlStr)
            break
          }
        }
      }

      let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
      DispatchQueue.main.async { completion(version, downloadURL) }
    }.resume()
  }

  func downloadAndInstallTrayUpdate(from url: URL, completion: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MistTrayUpdate-\(UUID().uuidString)")

      do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      } catch {
        print("[Update] Failed to create temp dir: \(error)")
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Download
      let semaphore = DispatchSemaphore(value: 0)
      var downloadedURL: URL?
      let task = URLSession.shared.downloadTask(with: url) { localURL, _, error in
        if let localURL = localURL, error == nil {
          let zipPath = tempDir.appendingPathComponent("update.zip")
          try? FileManager.default.moveItem(at: localURL, to: zipPath)
          downloadedURL = zipPath
        }
        semaphore.signal()
      }
      task.resume()
      semaphore.wait()

      guard let zipPath = downloadedURL else {
        print("[Update] Download failed")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Unzip
      let extractDir = tempDir.appendingPathComponent("extracted")
      let unzipStatus = self.runShellCommand(
        "/usr/bin/unzip", arguments: ["-o", zipPath.path, "-d", extractDir.path])
      guard unzipStatus == 0 else {
        print("[Update] Unzip failed with status \(unzipStatus)")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Find the .app bundle
      guard
        let contents = try? FileManager.default.contentsOfDirectory(
          at: extractDir, includingPropertiesForKeys: nil),
        let newApp = contents.first(where: { $0.pathExtension == "app" })
      else {
        print("[Update] No .app bundle found in zip")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Remove quarantine attribute (app is notarized, Gatekeeper still validates)
      self.runShellCommand("/usr/bin/xattr", arguments: ["-cr", newApp.path])

      // Verify codesign identity matches
      let currentApp = Bundle.main.bundlePath
      let currentAuthority = self.codesignAuthority(currentApp)
      let newAuthority = self.codesignAuthority(newApp.path)

      if !currentAuthority.isEmpty && !newAuthority.isEmpty
        && currentAuthority != newAuthority
      {
        print("[Update] Codesign mismatch: current=\(currentAuthority), new=\(newAuthority)")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Check write permission to app directory
      let appDir = URL(fileURLWithPath: currentApp).deletingLastPathComponent().path
      if !FileManager.default.isWritableFile(atPath: appDir) {
        print("[Update] No write permission to \(appDir), opening download in browser")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async {
          NSWorkspace.shared.open(url)
          completion(false)
        }
        return
      }

      // Replace app bundle
      let appURL = URL(fileURLWithPath: currentApp)
      do {
        let backupURL = tempDir.appendingPathComponent("MistTray-backup.app")
        try FileManager.default.moveItem(at: appURL, to: backupURL)
        try FileManager.default.moveItem(at: newApp, to: appURL)
      } catch {
        print("[Update] Failed to swap app: \(error)")
        try? FileManager.default.removeItem(at: tempDir)
        DispatchQueue.main.async { completion(false) }
        return
      }

      // Relaunch via open(1) for proper LaunchServices handling
      let relaunchTask = Process()
      relaunchTask.executableURL = URL(fileURLWithPath: "/bin/sh")
      relaunchTask.arguments = ["-c", "sleep 1 && open '\(currentApp)'"]
      try? relaunchTask.run()

      DispatchQueue.main.async { completion(true) }
    }
  }

  private func codesignAuthority(_ appPath: String) -> String {
    // codesign outputs to stderr, so we need to capture that
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    task.arguments = ["-dvvv", appPath]
    let pipe = Pipe()
    task.standardError = pipe
    task.standardOutput = FileHandle.nullDevice
    do {
      try task.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      task.waitUntilExit()
      let result = String(data: data, encoding: .utf8) ?? ""
      // Extract Authority= lines
      return result.components(separatedBy: "\n")
        .filter { $0.hasPrefix("Authority=") }
        .joined(separator: "\n")
    } catch {
      return ""
    }
  }

  private func fetchGitHubLatestTag(
    owner: String, repo: String, completion: @escaping (String?) -> Void
  ) {
    let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15.0

    URLSession.shared.dataTask(with: request) { data, _, error in
      guard let data = data, error == nil,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tagName = json["tag_name"] as? String
      else {
        DispatchQueue.main.async { completion(nil) }
        return
      }
      DispatchQueue.main.async { completion(tagName) }
    }.resume()
  }
}
