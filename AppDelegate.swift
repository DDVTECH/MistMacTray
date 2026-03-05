//
//  AppDelegate.swift
//  MistTray
//

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
  // MARK: - Core Properties
  var statusItem: NSStatusItem!
  var activeStreamsTimer: Timer?
  private var updateCheckTimer: Timer?

  // MARK: - New Architecture
  let appState = AppState()
  private var panelManager: PanelManager!

  // MARK: - Component Managers
  private let mistServerManager = MistServerManager.shared

  /// Re-detect all installations and resolve active mode
  func redetectServerMode() {
    let installations = mistServerManager.detectAllInstallations()
    let preference = mistServerManager.loadPreferredInstallation()
    appState.discoveredInstallations = installations
    appState.serverMode = mistServerManager.resolveActiveMode(
      installations: installations, preference: preference)
  }

  override init() {
    super.init()
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    panelManager = PanelManager(appState: appState)

    // Sync API base URL from persisted setting
    APIClient.shared.baseURL = appState.serverURL + "/api"

    // Wire refresh callback for snappy UX after mutations
    appState.onDataChanged = { [weak self] in
      self?.refreshAllData()
    }

    // 1) Create the menu bar icon
    setupStatusBarIcon()

    // 2) Detect server installations and resolve active mode
    let installations = mistServerManager.detectAllInstallations()
    let preference = mistServerManager.loadPreferredInstallation()
    appState.discoveredInstallations = installations
    appState.serverMode = mistServerManager.resolveActiveMode(
      installations: installations, preference: preference)
    appState.serverRunning = mistServerManager.isMistServerRunning(mode: appState.serverMode)

    // 3) Initial data refresh with auth check (capabilities included in main fetch)
    if appState.serverRunning {
      checkAuthAndRefresh()
    }

    // 4) Initial update check + daily timer
    checkForAllUpdates()
    updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
      self?.checkForAllUpdates()
    }

    // 5) Schedule regular data updates (every 10 seconds)
    activeStreamsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      // Re-detect installations on background queue to avoid blocking main thread
      DispatchQueue.global(qos: .utility).async {
        let installations = self.mistServerManager.detectAllInstallations()
        let preference = self.mistServerManager.loadPreferredInstallation()
        let mode = self.mistServerManager.resolveActiveMode(
          installations: installations, preference: preference)
        let running = self.mistServerManager.isMistServerRunning(mode: mode)
        DispatchQueue.main.async {
          self.appState.discoveredInstallations = installations
          self.appState.serverMode = mode
          self.appState.serverRunning = running
          if running {
            if self.appState.needsSetup {
              self.checkAuthAndRefresh()
            } else {
              self.refreshAllData()
            }
          }
        }
      }
    }
  }

  // MARK: - Auth Check

  func checkAuthAndRefresh() {
    APIClient.shared.checkAuthStatus { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let data):
          if let authorize = data["authorize"] as? [String: Any],
             let status = authorize["status"] as? String {
            switch status {
            case "NOACC":
              self.appState.needsSetup = true
              self.appState.needsAuth = false
            case "CHALL":
              // Server requires authentication
              if let challenge = authorize["challenge"] as? String {
                APIClient.shared.authChallenge = challenge
              }
              // If we have stored credentials, retry automatically
              if !APIClient.shared.authPasswordHash.isEmpty {
                self.retryAuthWithStoredCredentials()
              } else {
                self.appState.needsAuth = true
                self.appState.needsSetup = false
              }
            case "OK":
              self.appState.needsSetup = false
              self.appState.needsAuth = false
              self.refreshAllData()
            default:
              self.appState.needsSetup = false
              self.appState.needsAuth = false
              self.refreshAllData()
            }
          } else {
            self.appState.needsSetup = false
            self.appState.needsAuth = false
            self.refreshAllData()
          }
        case .failure:
          self.appState.needsSetup = false
        }
      }
    }
  }

  private func retryAuthWithStoredCredentials() {
    // Retry with current credentials — makeAPICall auto-injects authorize
    APIClient.shared.checkAuthStatus { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success(let data):
          if let authorize = data["authorize"] as? [String: Any],
             let status = authorize["status"] as? String, status == "OK" {
            self.appState.needsAuth = false
            self.appState.needsSetup = false
            self.refreshAllData()
          } else {
            // Credentials expired or changed
            APIClient.shared.clearAuth()
            self.appState.needsAuth = true
            self.appState.needsSetup = false
          }
        case .failure:
          self.appState.needsAuth = true
        }
      }
    }
  }

  private func fetchCapabilities() {
    APIClient.shared.fetchCapabilities { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let data):
          if let capabilities = data["capabilities"] as? [String: Any] {
            self?.appState.serverCapabilities = capabilities
          } else {
            self?.appState.serverCapabilities = data
          }
        case .failure:
          break
        }
      }
    }
  }

  // MARK: - Status Bar Setup

  private func setupStatusBarIcon() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      if let image = NSImage(named: "StatusIcon") {
        let height: CGFloat = 18
        let aspect = image.size.width / image.size.height
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        button.image = image
      }
      button.toolTip = "MistTray"

      // Left-click = panel, right-click = menu
      button.target = self
      button.action = #selector(statusBarClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
  }

  @objc func statusBarClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp {
      NSCursor.arrow.set()
      let menu = buildRightClickMenu()
      statusItem.menu = menu
      statusItem.button?.performClick(nil)
      statusItem.menu = nil
    } else {
      panelManager.togglePanel(relativeTo: sender)
    }
  }

  // MARK: - Right-Click Menu

  private func buildRightClickMenu() -> NSMenu {
    let menu = NSMenu()

    let isRunning = appState.serverRunning
    let mode = appState.serverMode

    let stopTitle = mode == .external ? "Stop Server (API only)" : "Stop Server"
    let toggleItem = NSMenuItem(
      title: isRunning ? stopTitle : "Start Server",
      action: #selector(toggleServer),
      keyEquivalent: ""
    )
    toggleItem.target = self
    toggleItem.isEnabled = isRunning || mode.canStart
    menu.addItem(toggleItem)

    let restartItem = NSMenuItem(
      title: "Restart Server",
      action: #selector(restartServer),
      keyEquivalent: ""
    )
    restartItem.target = self
    restartItem.isEnabled = isRunning && mode.canRestart
    menu.addItem(restartItem)

    menu.addItem(NSMenuItem.separator())

    let webUIItem = NSMenuItem(
      title: "Open Web UI",
      action: #selector(openWebUI),
      keyEquivalent: ""
    )
    webUIItem.target = self
    webUIItem.isEnabled = isRunning
    menu.addItem(webUIItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit MistTray",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    return menu
  }

  // MARK: - Server Actions

  @objc func openWebUI() {
    guard let url = URL(string: appState.serverURL) else { return }
    NSWorkspace.shared.open(url)
  }

  @objc func toggleServer() {
    let mode = appState.serverMode
    if mistServerManager.isMistServerRunning() {
      mistServerManager.stopServer(mode: mode) { [weak self] success in
        DispatchQueue.main.async {
          self?.appState.serverRunning = !success
          if success {
            // Re-detect mode after stopping
            self?.redetectServerMode()
          }
        }
      }
    } else {
      guard mode.canStart else {
        DialogManager.shared.showInfoAlert(
          title: "MistServer Not Found",
          message:
            "MistServer is not installed. You can install it via:\n\n"
            + "Homebrew:\n  brew tap ddvtech/mistserver\n  brew install mistserver\n\n"
            + "Or download from:\n  releases.mistserver.org"
        )
        return
      }
      mistServerManager.startServer(mode: mode) { [weak self] success in
        DispatchQueue.main.async {
          self?.appState.serverRunning = success
          if success {
            self?.redetectServerMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
              self?.checkAuthAndRefresh()
            }
          }
        }
      }
    }
  }

  @objc func restartServer() {
    let mode = appState.serverMode
    guard mode.canRestart else {
      if mode == .external {
        DialogManager.shared.showInfoAlert(
          title: "External Instance",
          message:
            "MistTray is connected to an external MistServer instance and cannot restart it. Use the stop command to disconnect."
        )
      }
      return
    }
    mistServerManager.restartServer(mode: mode) { [weak self] success in
      DispatchQueue.main.async {
        self?.appState.serverRunning = success
        if success {
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self?.checkAuthAndRefresh()
          }
        }
      }
    }
  }

  // MARK: - Data Updates

  func refreshAllData() {
    APIClient.shared.fetchAllServerData { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let data):
          self?.updateAppState(from: data)
        case .failure(let error):
          print("Failed to refresh: \(error)")
        }
      }
    }
  }

  private func updateAppState(from serverData: [String: Any]) {
    // Clear data that API omits when empty (prevents stale ghost entries)
    appState.autoPushRules = [:]
    appState.pushSettings = [:]

    appState.allStreams = DataProcessor.shared.processAllStreams(serverData["streams"])

    if let activeStreamsDict = serverData["active_streams"] as? [String: Any] {
      appState.activeStreams = Array(activeStreamsDict.keys).sorted()
    } else if let activeStreamsList = serverData["active_streams"] as? [String] {
      appState.activeStreams = activeStreamsList.sorted()
    } else {
      appState.activeStreams = []
    }

    appState.activePushes = DataProcessor.shared.processPushList(serverData["push_list"])
    appState.connectedClients = DataProcessor.shared.processClients(serverData["clients"])

    // Derive per-stream stats from clients data (stats_streams API returns useless data)
    var derivedStats: [String: Any] = [:]
    for (_, value) in appState.connectedClients {
      guard let info = value as? [String: Any],
            let stream = info["stream"] as? String
      else { continue }
      var stats = derivedStats[stream] as? [String: Any] ?? ["clients": 0, "bps_out": 0, "bps_in": 0]
      let proto = info["protocol"] as? String ?? ""
      if !proto.hasPrefix("INPUT:") {
        stats["clients"] = (stats["clients"] as? Int ?? 0) + 1
        stats["bps_out"] = (stats["bps_out"] as? Int ?? 0) + (info["downbps"] as? Int ?? 0)
      } else {
        stats["bps_in"] = (stats["bps_in"] as? Int ?? 0) + (info["upbps"] as? Int ?? 0)
      }
      derivedStats[stream] = stats
    }
    appState.streamStats = derivedStats

    if let config = serverData["config"] as? [String: Any] {
      if let protocols = config["protocols"] as? [String: Any] {
        appState.lastProtocolData = protocols
      } else {
        appState.lastProtocolData = [:]
      }
      if let protocols = config["protocols"] as? [[String: Any]] {
        appState.configuredProtocols = protocols
      }
      if let triggers = config["triggers"] as? [String: Any] {
        appState.triggers = triggers
      }
      if let version = config["version"] as? String {
        appState.mistServerCurrentVersion = version
        // If version is "Unknown" (e.g. brew tarball build), get from brew
        if version.hasPrefix("Unknown"), case .brew = appState.serverMode {
          fetchBrewInstalledVersion()
        }
      }
    } else {
      appState.lastProtocolData = [:]
    }

    if let logs = serverData["log"] as? [[Any]] {
      appState.serverLogs = logs
    } else {
      appState.serverLogs = []
    }

    // totals returns time-series: {data: [[c,i,o,d,u,...], ...], fields: [...]}
    if let totalsResponse = serverData["totals"] as? [String: Any],
       let fields = totalsResponse["fields"] as? [String],
       let data = totalsResponse["data"] as? [[Any]],
       let lastRow = data.last {
      var totals: [String: Any] = [:]
      for (i, field) in fields.enumerated() where i < lastRow.count {
        switch field {
        case "downbps": totals["bps_out"] = lastRow[i]
        case "upbps": totals["bps_in"] = lastRow[i]
        default: totals[field] = lastRow[i]
        }
      }
      appState.serverTotals = totals
    } else {
      appState.serverTotals = [:]
    }

    if let capabilities = serverData["capabilities"] as? [String: Any] {
      appState.serverCapabilities = capabilities
      if let connectors = capabilities["connectors"] as? [String: Any] {
        appState.availableConnectors = connectors
      }
    } else {
      appState.serverCapabilities = [:]
    }

    if let variables = serverData["variable_list"] as? [String: Any] {
      appState.variables = variables
    } else {
      appState.variables = [:]
    }

    if let writers = serverData["external_writer_list"] as? [String: Any] {
      appState.externalWriters = writers
    } else {
      appState.externalWriters = [:]
    }

    // Parse auto-push rules (API returns under "push_auto_list" or "auto_push" key)
    let autoPushData = serverData["push_auto_list"] ?? serverData["auto_push"]
    if let autoPushResponse = autoPushData as? [String: Any] {
      // Filter to only entries that look like actual rules (have stream+target)
      let filtered = autoPushResponse.filter { _, value in
        guard let rule = value as? [String: Any] else { return false }
        return rule["stream"] != nil && rule["target"] != nil
      }
      appState.autoPushRules = filtered
    }
    // else: already cleared to [:] at top of function

    if let pushSettings = serverData["push_settings"] as? [String: Any] {
      appState.pushSettings = pushSettings
    }

    // Parse JWK entries
    if let jwks = serverData["jwks"] as? [[Any]] {
      appState.jwkEntries = jwks
    } else {
      appState.jwkEntries = []
    }

    // Parse stream keys
    if let keys = serverData["streamkeys"] as? [String: String] {
      appState.streamKeys = keys
    } else {
      appState.streamKeys = [:]
    }

    // Fallback: derive active streams from allStreams when active_streams key was absent
    if appState.activeStreams.isEmpty {
      appState.activeStreams = appState.allStreams.compactMap { (name, value) in
        guard let data = value as? [String: Any],
              let online = data["online"] as? Int,
              online >= 1 && online <= 2
        else { return nil }
        return name
      }.sorted()
    }

    appState.lastRefreshDate = Date()
    appState.serverRunning = mistServerManager.isMistServerRunning(mode: appState.serverMode)

    // Append time-series snapshots for sparkline charts
    appState.appendTotalsSnapshot()
    appState.appendStreamSnapshots()
  }

  private func fetchBrewInstalledVersion() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self = self,
            let brewPath = self.mistServerManager.findBrew()
      else { return }
      let output = self.mistServerManager.runShellCommandWithOutput(
        brewPath, arguments: ["info", "--json=v2", "mistserver"])
      guard !output.isEmpty,
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let formulae = json["formulae"] as? [[String: Any]],
            let formula = formulae.first,
            let installed = formula["installed"] as? [[String: Any]],
            let current = installed.first,
            let version = current["version"] as? String
      else { return }
      DispatchQueue.main.async {
        self.appState.mistServerCurrentVersion = version
      }
    }
  }

  // MARK: - First-Time Setup

  /// After account creation, fetch capabilities and enable all default protocols
  /// (mirrors what the LSP web UI does on first-time setup).
  func enableDefaultProtocols(completion: @escaping () -> Void) {
    APIClient.shared.fetchCapabilities { [weak self] result in
      switch result {
      case .success(let data):
        guard let capabilities = data["capabilities"] as? [String: Any],
              let connectors = capabilities["connectors"] as? [String: Any]
        else {
          completion()
          return
        }

        var protocols: [[String: Any]] = []
        for (name, value) in connectors {
          guard let info = value as? [String: Any] else { continue }
          // Skip push-only connectors
          if let flags = info["flags"] as? [String: Any], flags["PUSHONLY"] != nil { continue }
          if info["PUSHONLY"] != nil { continue }
          // Skip connectors with NODEFAULT flag
          if let flags = info["flags"] as? [String: Any], flags["NODEFAULT"] != nil { continue }
          if info["NODEFAULT"] != nil { continue }
          // Skip connectors that require configuration
          if let required = info["required"] as? [String: Any], !required.isEmpty { continue }
          protocols.append(["connector": name])
        }

        if protocols.isEmpty {
          completion()
          return
        }

        let apiCall: [String: Any] = ["config": ["protocols": protocols]]
        APIClient.shared.makeAPICall(apiCall) { (_: Result<[String: Any], APIError>) in
          DispatchQueue.main.async {
            self?.refreshAllData()
            completion()
          }
        }

      case .failure:
        completion()
      }
    }
  }

  // MARK: - Update Checking

  func checkForAllUpdates() {
    appState.isCheckingForUpdates = true

    let group = DispatchGroup()

    // Check MistServer latest release
    group.enter()
    mistServerManager.checkLatestMistServerVersion(mode: appState.serverMode) { [weak self] latestVersion in
      guard let self = self else { group.leave(); return }
      self.appState.mistServerLatestVersion = latestVersion
      if let latest = latestVersion, let current = self.appState.mistServerBaseVersion {
        self.appState.mistServerUpdateAvailable =
          MistServerManager.compareVersions(latest, current) > 0
      }
      group.leave()
    }

    // Check MistTray latest release
    group.enter()
    mistServerManager.checkLatestMistTrayRelease { [weak self] version, url in
      guard let self = self else { group.leave(); return }
      self.appState.mistTrayLatestVersion = version
      self.appState.mistTrayUpdateURL = url
      if let latest = version {
        self.appState.mistTrayUpdateAvailable =
          MistServerManager.compareVersions(latest, self.appState.mistTrayCurrentVersion) > 0
      }
      group.leave()
    }

    group.notify(queue: .main) { [weak self] in
      self?.appState.lastUpdateCheck = Date()
      self?.appState.isCheckingForUpdates = false
    }
  }

  func installMistTrayUpdate() {
    guard let url = appState.mistTrayUpdateURL else { return }
    appState.isInstallingTrayUpdate = true
    mistServerManager.downloadAndInstallTrayUpdate(from: url) { [weak self] success in
      if success {
        // New version was launched, terminate this one
        NSApp.terminate(nil)
      } else {
        self?.appState.isInstallingTrayUpdate = false
        DialogManager.shared.showInfoAlert(
          title: "Update Failed",
          message: "Failed to install the update. Please download manually from GitHub."
        )
      }
    }
  }

  // MARK: - App Lifecycle

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    activeStreamsTimer?.invalidate()
    updateCheckTimer?.invalidate()
  }
}
