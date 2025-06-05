//
//  MistServerManager.swift
//  MistTray
//

import Foundation

class MistServerManager {
  static let shared = MistServerManager()

  private init() {}

  // MARK: - Server Detection

  func findBrewMistserver() -> String? {
    let intelPath = "/usr/local/bin/mistserver"
    if FileManager.default.isExecutableFile(atPath: intelPath) {
      return intelPath
    }
    let armPath = "/opt/homebrew/bin/mistserver"
    if FileManager.default.isExecutableFile(atPath: armPath) {
      return armPath
    }
    return nil
  }

  func findEmbeddedMistserver() -> String? {
    let binDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MistTray/mistserver/bin")
    let controller = binDir.appendingPathComponent("MistController").path
    return FileManager.default.isExecutableFile(atPath: controller) ? controller : nil
  }

  // MARK: - Server Status

  func isMistServerRunning() -> Bool {
    if findBrewMistserver() != nil {
      let output = runShellCommandWithOutput("/bin/launchctl", arguments: ["list"])
      return output.contains("homebrew.mxcl.mistserver")
    } else if findEmbeddedMistserver() != nil {
      return isEmbeddedRunning()
    }
    return false
  }

  func isEmbeddedRunning() -> Bool {
    let output = runShellCommandWithOutput("/bin/ps", arguments: ["aux"])
    return output.contains("MistController")
  }

  // MARK: - Server Lifecycle

  func startServer(completion: @escaping (Bool) -> Void) {
    print("▶️ Starting MistServer...")

    if let brewPath = findBrewMistserver() {
      print("📦 Using Brew MistServer at: \(brewPath)")
      _ = runMistServer(executablePath: brewPath)
      completion(true)
    } else if let embeddedPath = findEmbeddedMistserver() {
      print("📦 Using embedded MistServer at: \(embeddedPath)")
      _ = runMistServer(executablePath: embeddedPath)
      completion(true)
    } else {
      print("📦 No MistServer found, downloading latest...")
      downloadAndInstallLatestMistserver { [weak self] installedPath in
        guard let self = self, let path = installedPath else {
          print("❌ Failed to download and install MistServer")
          completion(false)
          return
        }
        print("✅ Downloaded MistServer, starting at: \(path)")
        _ = self.runMistServer(executablePath: path)
        completion(true)
      }
    }
  }

  func stopServer() {
    print("🛑 Stopping MistServer...")

    if let brewPath = findBrewMistserver() {
      print("📦 Stopping Brew MistServer")
      let brewCmd =
        brewPath.hasPrefix("/opt/homebrew") ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
      runShellCommand(brewCmd, arguments: ["services", "stop", "mistserver"])
    } else if findEmbeddedMistserver() != nil {
      print("📦 Stopping embedded MistServer")
      runShellCommand("/usr/bin/killall", arguments: ["MistController"])
    }
  }

  func restartServer(completion: @escaping (Bool) -> Void) {
    print("🚀 Restarting MistServer...")

    // Guard: Don't restart if not running
    if !isMistServerRunning() {
      print("⚠️ MistServer is not running, ignoring restart request")
      completion(false)
      return
    }

    // Stop the server first
    stopServer()

    // Wait a moment then start again
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      self.startServer(completion: completion)
    }
  }

  @discardableResult
  func runMistServer(executablePath: String) -> Process {
    let task = Process()
    task.launchPath = executablePath

    // Ensure default config exists and get its path
    let configPath = ensureDefaultConfig()

    // Pass config file as argument to MistController
    task.arguments = ["-c", configPath]

    task.standardOutput = nil
    task.standardError = nil

    print("📁 Starting MistServer with config: \(configPath)")
    task.launch()

    return task
  }

  // MARK: - Configuration Management

  func ensureDefaultConfig() -> String {
    let baseDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MistTray/mistserver")

    // Create base directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: baseDir.path) {
      do {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        print("📁 Created MistServer directory: \(baseDir.path)")
      } catch {
        print("❌ Failed to create MistServer directory: \(error)")
        return baseDir.appendingPathComponent("config.json").path
      }
    }

    createDefaultConfig(in: baseDir)
    return baseDir.appendingPathComponent("config.json").path
  }

  func createDefaultConfig(in baseDirectory: URL) {
    let configPath = baseDirectory.appendingPathComponent("config.json")

    // Don't overwrite existing config
    if FileManager.default.fileExists(atPath: configPath.path) {
      print("📁 Config already exists at: \(configPath.path)")
      return
    }

    // Default configuration matching original AppDelegate exactly
    let defaultConfig: [String: Any] = [
      "account": [
        "test": [
          "password": "098f6bcd4621d373cade4e832627b4f6"  // MD5 hash of "test"
        ]
      ],
      "auto_push": NSNull(),
      "bandwidth": [
        "exceptions": ["::1", "127.0.0.0/8", "10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
      ],
      "config": [
        "accesslog": "LOG",
        "controller": [
          "interface": NSNull(),
          "port": NSNull(),
          "username": NSNull(),
        ],
        "defaultStream": NSNull(),
        "limits": NSNull(),
        "prometheus": "",
        "protocols": [
          ["connector": "AAC"],
          ["connector": "CMAF"],
          ["connector": "DTSC"],
          ["connector": "EBML"],
          ["connector": "FLAC"],
          ["connector": "FLV"],
          ["connector": "H264"],
          ["connector": "HDS"],
          ["connector": "HLS"],
          ["connector": "HTTP"],
          ["connector": "HTTPTS"],
          ["connector": "JPG"],
          ["connector": "JSON"],
          ["connector": "MP3"],
          ["connector": "MP4"],
          ["connector": "OGG"],
          ["connector": "RTMP"],
          ["connector": "RTSP"],
          ["connector": "SDP"],
          ["connector": "SubRip"],
          ["connector": "TSSRT"],
          ["connector": "WAV"],
          ["connector": "WebRTC"],
        ],
        "serverid": NSNull(),
        "sessionInputMode": 15,
        "sessionOutputMode": 15,
        "sessionStreamInfoMode": 1,
        "sessionUnspecifiedMode": 0,
        "sessionViewerMode": 14,
        "tknMode": 15,
        "triggers": NSNull(),
        "trustedproxy": [],
      ],
      "extwriters": NSNull(),
      "push_settings": [
        "maxspeed": 0,
        "wait": 3,
      ],
      "streams": [
        "live": [
          "name": "live",
          "processes": [],
          "source": "push://",
          "stop_sessions": false,
          "tags": [],
        ]
      ],
      "ui_settings": [
        "sort_autopushes": [
          "by": "Stream",
          "dir": 1,
        ],
        "sort_pushes": [
          "by": "Statistics",
          "dir": 1,
        ],
        "sortstreams": [
          "by": "name",
          "dir": 1,
        ],
      ],
      "variables": NSNull(),
    ]

    do {
      let jsonData = try JSONSerialization.data(
        withJSONObject: defaultConfig, options: [.prettyPrinted, .sortedKeys])
      try jsonData.write(to: configPath)
      print("✅ Created default config at: \(configPath.path)")
      print("🔑 Default login: test/test")
    } catch {
      print("❌ Failed to create default config: \(error)")
    }
  }

  func removeEmbeddedInstallation() {
    print("🚀 Removing embedded installation...")
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MistTray/mistserver")
    try? FileManager.default.removeItem(at: appSupport)
    UserDefaults.standard.removeObject(forKey: "EmbeddedMistTag")
  }

  // MARK: - Installation and Updates

  func checkForUpdates(completion: @escaping (Bool) -> Void) {
    print("🔧 Checking for updates using hybrid system...")

    if isMistServerRunning() {
      print("📡 Server running - using API-based update check")
      checkForUpdatesViaAPI(completion: completion)
    } else if findEmbeddedMistserver() != nil || findBrewMistserver() != nil {
      print("📦 Server installed but not running - using manual update check")
      checkForEmbeddedUpdate(completion: completion)
    } else {
      print("📦 No server found - need initial installation")
      downloadAndInstallLatestMistserver { installedPath in
        completion(installedPath != nil)
      }
    }
  }

  func checkForEmbeddedUpdate(completion: @escaping (Bool) -> Void) {
    print("🔧 Checking for embedded update...")
    let url = URL(string: "https://api.github.com/repos/DDVTECH/mistserver/releases/latest")!

    URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
      if let error = error {
        print("❌ Failed to fetch latest release info: \(error)")
        completion(false)
        return
      }

      guard let data = data else {
        print("❌ No data received from GitHub API")
        completion(false)
        return
      }

      print("📡 Received GitHub API response")

      do {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let latestTag = json["tag_name"] as? String
        else {
          print("❌ Failed to parse GitHub API response")
          completion(false)
          return
        }

        print("📊 Latest GitHub tag: \(latestTag)")
        let savedTag = UserDefaults.standard.string(forKey: "EmbeddedMistTag")
        print("📊 Saved tag: \(savedTag ?? "none")")

        if savedTag != latestTag {
          print("🔄 Update needed: \(savedTag ?? "none") -> \(latestTag)")
          self?.downloadAndInstallLatestMistserver { installedPath in
            if installedPath != nil {
              UserDefaults.standard.set(latestTag, forKey: "EmbeddedMistTag")
              print("✅ Updated to version: \(latestTag)")
              completion(true)
            } else {
              completion(false)
            }
          }
        } else {
          print("✅ Already up to date: \(latestTag)")
          completion(false)
        }
      } catch {
        print("❌ Failed to parse GitHub API JSON: \(error)")
        completion(false)
      }
    }.resume()
  }

  func checkForUpdatesViaAPI(completion: @escaping (Bool) -> Void) {
    print("🔧 Checking for updates via MistServer API...")

    // Check if auto-update is enabled
    let autoUpdateEnabled = UserDefaults.standard.bool(forKey: "AutoUpdateEnabled")
    print("📊 Auto-update enabled: \(autoUpdateEnabled)")

    let apiCall = ["checkupdate": true]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: apiCall),
      let url = URL(string: "http://localhost:4242/api")
    else {
      print("❌ Failed to create checkupdate request")
      // Fallback to manual check
      checkForEmbeddedUpdate(completion: completion)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 10.0

    print("📡 Checking for updates via API...")
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      if let error = error {
        print("❌ API update check error: \(error)")
        // Fallback to manual check
        self?.checkForEmbeddedUpdate(completion: completion)
        return
      }

      guard let data = data else {
        print("❌ No data received for update check")
        completion(false)
        return
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          print("📡 Update check response: \(json)")

          if let updateInfo = json["checkupdate"] as? [String: Any] {
            if let updateAvailable = updateInfo["update"] as? Bool, updateAvailable {
              print("🔄 Update available via API")

              if autoUpdateEnabled {
                print("✅ Auto-update enabled, performing update automatically")
                self?.performUpdateViaAPI { success in
                  completion(success)
                }
              } else {
                print("⚠️ Auto-update disabled, skipping automatic update")
                completion(true)  // Update available but not performed
              }
            } else {
              print("✅ No updates available via API")
              completion(false)
            }
          } else {
            print("❌ Unexpected update check response format")
            completion(false)
          }
        } else {
          print("❌ Failed to parse JSON response")
          completion(false)
        }
      } catch {
        print("❌ Failed to parse update check response: \(error)")
        completion(false)
      }
    }.resume()
  }

  func performUpdateViaAPI(completion: @escaping (Bool) -> Void) {
    print("🔧 Performing update via MistServer API...")

    let apiCall = ["update": true]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: apiCall),
      let url = URL(string: "http://localhost:4242/api")
    else {
      print("❌ Failed to create update request")
      completion(false)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 30.0  // Updates might take longer

    print("📡 Triggering update via API...")
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("❌ API update error: \(error)")
        completion(false)
        return
      }

      guard let data = data else {
        print("❌ No data received for update")
        completion(false)
        return
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          print("📡 Update response: \(json)")

          if let updateResult = json["update"] {
            print("✅ Update completed: \(updateResult)")
            completion(true)
          } else {
            print("❌ Unexpected update response format")
            completion(false)
          }
        } else {
          print("❌ Failed to parse JSON response")
          completion(false)
        }
      } catch {
        print("❌ Failed to parse update response: \(error)")
        completion(false)
      }
    }.resume()
  }

  func downloadAndInstallLatestMistserver(completion: @escaping (String?) -> Void) {
    print("🔧 Starting download and install process...")

    // First, get the latest tag from GitHub
    let url = URL(string: "https://api.github.com/repos/DDVTECH/mistserver/releases/latest")!

    URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
      if let error = error {
        print("❌ Failed to fetch release info: \(error)")
        completion(nil)
        return
      }

      guard let data = data else {
        print("❌ No data received from GitHub API")
        completion(nil)
        return
      }

      print("📡 Received GitHub API response for download")

      do {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String
        else {
          print("❌ Failed to parse GitHub API response")
          completion(nil)
          return
        }

        print("📊 Downloading version: \(tag)")

        // Construct the download URL using the tag
        let downloadURLString = "https://r.mistserver.org/dl/mistserver_mach64V\(tag).zip"
        guard let downloadURL = URL(string: downloadURLString) else {
          print("❌ Invalid download URL: \(downloadURLString)")
          completion(nil)
          return
        }

        print("📡 Download URL: \(downloadURLString)")

        // Download the zip file
        URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, response, error in
          if let error = error {
            print("❌ Download failed: \(error)")
            completion(nil)
            return
          }

          guard let localURL = localURL else {
            print("❌ No local URL for downloaded file")
            completion(nil)
            return
          }

          if let httpResponse = response as? HTTPURLResponse {
            print("📡 Download response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
              print("❌ Download failed with status: \(httpResponse.statusCode)")
              completion(nil)
              return
            }
          }

          print("✅ Download completed, processing...")

          // Process the downloaded file
          self?.processDownloadedZip(localURL: localURL, tag: tag, completion: completion)

        }.resume()

      } catch {
        print("❌ Failed to parse GitHub API JSON: \(error)")
        completion(nil)
      }
    }.resume()
  }

  func processDownloadedZip(localURL: URL, tag: String, completion: @escaping (String?) -> Void) {
    print("🔧 Processing downloaded zip file...")

    let tmpDir = FileManager.default.temporaryDirectory
    let zipPath = tmpDir.appendingPathComponent("mistserver_\(tag).zip")

    do {
      // Copy downloaded file to temp location
      try? FileManager.default.removeItem(at: zipPath)
      try FileManager.default.copyItem(at: localURL, to: zipPath)
      print("📁 Copied zip to: \(zipPath.path)")

      // Create unzip directory
      let unzipDir = tmpDir.appendingPathComponent("mistserver_\(tag)_unzip")
      try? FileManager.default.removeItem(at: unzipDir)
      try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
      print("📁 Created unzip directory: \(unzipDir.path)")

      // Unzip the file
      let unzipResult = runShellCommand(
        "/usr/bin/unzip", arguments: ["-o", zipPath.path, "-d", unzipDir.path])
      if unzipResult != 0 {
        print("❌ Unzip failed with code: \(unzipResult)")
        completion(nil)
        return
      }
      print("✅ Unzip completed")

      // Find the contents - binaries should be directly in the unzipped directory
      let contents = try FileManager.default.contentsOfDirectory(atPath: unzipDir.path)
      print("📁 Unzipped contents: \(contents)")

      // Set up destination
      let destBase = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MistTray/mistserver")
      let destBin = destBase.appendingPathComponent("bin")

      print("📁 Destination: \(destBase.path)")

      // Remove old installation and create new directory
      try? FileManager.default.removeItem(at: destBase)
      try FileManager.default.createDirectory(at: destBin, withIntermediateDirectories: true)

      // Copy all files directly from unzipDir to destBin (since binaries are as-is in the zip)
      print("📁 Copying \(contents.count) files directly from zip")

      for fileName in contents {
        let src = unzipDir.appendingPathComponent(fileName)
        let dst = destBin.appendingPathComponent(fileName)

        // Skip directories and hidden files
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDirectory) {
          if isDirectory.boolValue || fileName.hasPrefix(".") {
            print("⏭️ Skipping: \(fileName)")
            continue
          }
        }

        do {
          try FileManager.default.copyItem(at: src, to: dst)
          print("📁 Copied: \(fileName)")

          // Make executable
          let attributes = [FileAttributeKey.posixPermissions: 0o755]
          try FileManager.default.setAttributes(attributes, ofItemAtPath: dst.path)
          print("🔧 Made executable: \(fileName)")
        } catch {
          print("❌ Failed to copy \(fileName): \(error)")
        }
      }

      // Clean up temp files
      try? FileManager.default.removeItem(at: zipPath)
      try? FileManager.default.removeItem(at: unzipDir)

      // Return the path to MistController
      let controllerPath = destBin.appendingPathComponent("MistController").path
      if FileManager.default.isExecutableFile(atPath: controllerPath) {
        print("✅ Installation completed: \(controllerPath)")
        completion(controllerPath)
      } else {
        print("❌ MistController not found after installation")
        completion(nil)
      }

    } catch {
      print("❌ Failed to process zip file: \(error)")
      completion(nil)
    }
  }

  // MARK: - Shell Command Utilities

  @discardableResult
  func runShellCommand(_ launchPath: String, arguments: [String]) -> Int32 {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = arguments
    task.standardOutput = nil
    task.standardError = nil
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
  }

  func runShellCommandWithOutput(_ launchPath: String, arguments: [String]) -> String {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.launch()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
