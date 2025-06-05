//
//  AppDelegate.swift
//  MistTray
//

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, MenuBuilderDelegate {
  // MARK: - Core Properties
  var statusItem: NSStatusItem!
  var updateTimer: Timer?
  var activeStreamsTimer: Timer?

  // MARK: - State Properties (preserved for compatibility)
  var activeStreams: [String] = []
  var allStreams: [String: Any] = [:]
  var streamStats: [String: Any] = [:]
  var activePushes: [String: Any] = [:]
  var connectedClients: [String: Any] = [:]
  var serverRunning: Bool = false

  // MARK: - Data Cache Properties (for menu building)
  var lastProtocolData: [String: Any] = [:]

  // MARK: - Component Managers
  private var menuBuilder: MenuBuilder!
  private let mistServerManager = MistServerManager.shared
  private let streamManager = StreamManager.shared
  private let pushManager = PushManager.shared
  private let clientManager = ClientManager.shared

  override init() {
    super.init()
    print("🔧 AppDelegate init() is called")
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    print("🚀 MistTray: finished loading")

    // Initialize component managers
    menuBuilder = MenuBuilder(delegate: self)

    // 1) Create the menu bar icon
    setupStatusBarIcon()

    // 2) Build the menu using MenuBuilder
    statusItem.menu = menuBuilder.buildMainMenu(
      serverRunning: mistServerManager.isMistServerRunning(),
      streams: allStreams,
      pushes: activePushes,
      clients: connectedClients,
      protocols: lastProtocolData
    )

    // 3) Update status text
    updateStatusText()

    // 4) Check for updates
    checkForUpdates()

    // 5) Schedule hourly update checks
    updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
      self.checkForUpdates()
    }

    // 6) Schedule regular active streams updates (every 10 seconds)
    activeStreamsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
      if MistServerManager.shared.isMistServerRunning() {
        print("✅ Server is running, updating all data...")
        self.updateAllData()
      } else {
        print("❌ Server not running, skipping update")
      }
    }
  }

  // MARK: - Status Bar Setup

  private func setupStatusBarIcon() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      if let originalImage = NSImage(named: "StatusIcon") {
        // Create properly sized icon maintaining aspect ratio
        let targetSize = NSSize(width: 16, height: 16)
        let resizedImage = NSImage(size: targetSize)

        resizedImage.lockFocus()

        // Calculate aspect ratio to fit within 16x16 while maintaining proportions
        let originalSize = originalImage.size
        let aspectRatio = originalSize.width / originalSize.height

        var drawSize = targetSize
        if aspectRatio > 1 {
          // Wider than tall
          drawSize.height = targetSize.width / aspectRatio
        } else {
          // Taller than wide
          drawSize.width = targetSize.height * aspectRatio
        }

        // Center the image
        let drawRect = NSRect(
          x: (targetSize.width - drawSize.width) / 2,
          y: (targetSize.height - drawSize.height) / 2,
          width: drawSize.width,
          height: drawSize.height
        )

        originalImage.draw(in: drawRect)
        resizedImage.unlockFocus()
        resizedImage.isTemplate = true

        button.image = resizedImage
      }
      button.toolTip = "MistTray"
    }
  }

  // MARK: — Menu actions

  @objc func openWebUI() {
    print("🚀 MistTray: opening web UI...")
    guard let url = URL(string: "http://localhost:4242") else { return }
    NSWorkspace.shared.open(url)
  }

  @objc func toggleServer() {
    print("🚀 MistTray: toggling mistserver...")

    if MistServerManager.shared.isMistServerRunning() {
      // Server is running, so stop it
      MistServerManager.shared.stopServer()
    } else {
      // Server is not running, so start it
      MistServerManager.shared.startServer { [weak self] success in
        DispatchQueue.main.async {
          if success {
            print("✅ Server started successfully")
          } else {
            print("❌ Failed to start server")
          }
          self?.updateStatusText()
          // Give server time to start before checking streams
          DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self?.updateAllData()
          }
        }
      }
    }

    // Update status immediately, then again after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      self.updateStatusText()
    }
  }

  @objc func restartServer() {
    print("🚀 MistTray: restarting mistserver...")

    MistServerManager.shared.restartServer { [weak self] success in
      DispatchQueue.main.async {
        if success {
          print("✅ Server restarted successfully")
        } else {
          print("❌ Failed to restart server")
        }
        self?.updateStatusText()
        // Give server time to restart before checking streams
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          self?.updateAllData()
        }
      }
    }
  }

  @objc func nukeStream(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }

    // Get stream details for confirmation dialog
    var streamDetails = "Stream: \(streamName)"
    var viewerCount = 0
    var bandwidth = 0

    if let stats = streamStats[streamName] as? [String: Any] {
      viewerCount = stats["clients"] as? Int ?? 0
      bandwidth = stats["bps_out"] as? Int ?? 0
      let bandwidthStr = DataProcessor.shared.formatBandwidth(bandwidth)
      streamDetails += "\nViewers: \(viewerCount)"
      streamDetails += "\nBandwidth: \(bandwidthStr)"

      if let duration = stats["uptime"] as? Int {
        let durationStr = DataProcessor.shared.formatConnectionTime(duration)
        streamDetails += "\nUptime: \(durationStr)"
      }
    }

    print("🚀 MistTray: nuking stream: \(streamName)")

    DialogManager.shared.showConfirmationAlert(
      title: "Nuke Stream",
      message:
        "Are you sure you want to nuke this stream? This will immediately disconnect all \(viewerCount) viewers and stop the stream.\n\n\(streamDetails)",
      confirmButtonTitle: "Nuke Stream",
      isDestructive: true
    ) { [weak self] confirmed in
      guard confirmed else {
        print("🚫 Stream nuke cancelled by user")
        return
      }

      APIClient.shared.nukeStream(streamName) { [weak self] result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            print("✅ Stream nuked successfully")
          case .failure(let error):
            print("❌ Failed to nuke stream: \(error)")
          }

          // Update UI after operation
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self?.updateStatusText()
            self?.updateActiveStreams()
          }
        }
      }
    }
  }

  @objc func removeEmbeddedInstallation() {
    print("🚀 MistTray: removing embedded installation...")
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/MistTray/mistserver")
    try? FileManager.default.removeItem(at: appSupport)
    UserDefaults.standard.removeObject(forKey: "EmbeddedMistTag")
    updateStatusText()
  }

  // MARK: — Status control

  func updateStatusText(checkStreams: Bool = true) {
    guard let menu = statusItem.menu else { return }
    let statusLine = menu.items[0]

    let isRunning = isMistServerRunning()
    let totalViewers = getTotalViewers()

    statusLine.title = UtilityManager.shared.generateStatusText(
      isRunning: isRunning,
      activeStreams: activeStreams,
      activePushes: activePushes,
      totalViewers: totalViewers,
      serverType: findBrewMistserver() != nil ? "Brew" : "Embedded"
    )

    updateMenuItemStates(isRunning: isRunning)

    if checkStreams {
      updateActiveStreams()
    }
  }

  func getTotalViewers() -> Int {
    return UtilityManager.shared.getTotalViewers(from: streamStats)
  }

  func updateMenuItemStates(isRunning: Bool) {
    guard let menu = statusItem.menu else { return }

    print("🔧 Updating menu states - Server running: \(isRunning)")

    // Find and update menu items
    for (index, item) in menu.items.enumerated() {
      let oldTitle = item.title
      let oldEnabled = item.isEnabled

      if item.action == #selector(toggleServer) {
        // Update the toggle button title and state
        item.title = isRunning ? "🟥 Stop MistServer" : "▶️ Start MistServer"
        item.isEnabled = true  // Toggle button is always enabled
        print(
          "🎛️ Menu item [\(index)] toggle: '\(oldTitle)' -> '\(item.title)' (enabled: \(item.isEnabled))"
        )
      } else {
        switch item.title {
        case "Restart MistServer":
          item.isEnabled = isRunning
        case "Open Web UI":
          item.isEnabled = isRunning
        case "Active streams":
          item.isEnabled = isRunning
        case "Pushes":
          item.isEnabled = isRunning
        case "Connected Clients":
          item.isEnabled = isRunning
        case "Stream Configuration":
          item.isEnabled = isRunning
        case "System Monitoring":
          item.isEnabled = isRunning
        case "Protocol Management":
          item.isEnabled = isRunning
        case "Configuration Backup":
          item.isEnabled = isRunning
        default:
          continue
        }

        print("🎛️ Menu item [\(index)] '\(item.title)': \(oldEnabled) -> \(item.isEnabled)")
      }
    }

    // Also update submenu items that should be disabled when server is stopped
    updateSubmenuStates(menu: menu, isRunning: isRunning)
  }

  func updateSubmenuStates(menu: NSMenu, isRunning: Bool) {
    for item in menu.items {
      // Handle submenus recursively
      if let submenu = item.submenu {
        // Disable all submenu items that require server to be running
        for subItem in submenu.items {
          // Skip separators and disabled info items
          if subItem.isSeparatorItem || subItem.action == nil {
            continue
          }

          // Keep certain items always enabled even when server is stopped
          let alwaysEnabledActions = [
            #selector(showPreferences),
            #selector(NSApplication.terminate(_:)),
          ]

          if let action = subItem.action, alwaysEnabledActions.contains(action) {
            continue
          }

          // Disable all other interactive submenu items when server is stopped
          if !isRunning && subItem.isEnabled {
            subItem.isEnabled = false
            print("🎛️ Disabled submenu item: '\(subItem.title)'")
          } else if isRunning && !subItem.isEnabled && subItem.action != nil {
            // Re-enable items when server starts (except info items)
            let infoTitles = ["No active streams", "No active pushes", "No connected clients"]
            if !infoTitles.contains(subItem.title) {
              subItem.isEnabled = true
              print("🎛️ Enabled submenu item: '\(subItem.title)'")
            }
          }

          // Handle nested submenus
          if let nestedSubmenu = subItem.submenu {
            updateSubmenuStates(menu: nestedSubmenu, isRunning: isRunning)
          }
        }
      }
    }
  }

  func updateActiveStreams(retryCount: Int = 0) {
    print("🔄 Updating active streams (attempt \(retryCount + 1))...")

    refreshAllData()
  }

  // MARK: - Server Management (delegated to MistServerManager)

  func isMistServerRunning() -> Bool {
    return mistServerManager.isMistServerRunning()
  }

  func isEmbeddedRunning() -> Bool {
    return mistServerManager.isEmbeddedRunning()
  }

  func findBrewMistserver() -> String? {
    return mistServerManager.findBrewMistserver()
  }

  func findEmbeddedMistserver() -> String? {
    return mistServerManager.findEmbeddedMistserver()
  }

  func checkForEmbeddedUpdate() {
    mistServerManager.checkForUpdates { result in
      // Handle update check result if needed
    }
  }

  func downloadAndInstallLatestMistserver(completion: @escaping (String?) -> Void) {
    MistServerManager.shared.downloadAndInstallLatestMistserver(completion: completion)
  }

  // MARK: — Shell helpers

  @discardableResult
  func runShellCommand(_ launchPath: String, arguments: [String]) -> Int32 {
    let command = "\(launchPath) \(arguments.joined(separator: " "))"
    let result = UtilityManager.shared.runShellCommand(command)
    return result.exitCode
  }

  @discardableResult
  func runMistServer(executablePath: String) -> Process {
    // Delegate to MistServerManager
    return mistServerManager.runMistServer(executablePath: executablePath)
  }

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

    mistServerManager.createDefaultConfig(in: baseDir)
    return baseDir.appendingPathComponent("config.json").path
  }

  func runShellCommandWithOutput(_ launchPath: String, arguments: [String]) -> String {
    let command = "\(launchPath) \(arguments.joined(separator: " "))"
    let result = UtilityManager.shared.runShellCommand(command)
    return result.output
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    updateTimer?.invalidate()
    activeStreamsTimer?.invalidate()
  }

  // MARK: — Hybrid update system

  func checkForUpdates() {
    print("🔧 Checking for updates using hybrid system...")

    if isMistServerRunning() {
      print("📡 Server running - using API-based update check")
      checkForUpdatesViaAPI()
    } else if findEmbeddedMistserver() != nil || findBrewMistserver() != nil {
      print("📦 Server installed but not running - using manual update check")
      checkForEmbeddedUpdate()
    } else {
      print("📦 No server found - need initial installation")
      downloadAndInstallLatestMistserver { [weak self] installedPath in
        if installedPath != nil {
          print("✅ Initial installation completed")
          DispatchQueue.main.async {
            self?.updateStatusText()
          }
        }
      }
    }
  }

  func checkForUpdatesViaAPI() {
    print("🔧 Checking for updates via MistServer API...")

    // Check if auto-update is enabled
    let autoUpdateEnabled = UserDefaults.standard.bool(forKey: "AutoUpdateEnabled")
    print("📊 Auto-update enabled: \(autoUpdateEnabled)")

    APIClient.shared.checkForUpdates { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let json):
          print("📡 Update check response: \(json)")

          if let updateInfo = json["checkupdate"] as? [String: Any] {
            if let updateAvailable = updateInfo["update"] as? Bool, updateAvailable {
              print("🔄 Update available via API")

              if autoUpdateEnabled {
                print("✅ Auto-update enabled, performing update automatically")
                self?.performUpdateViaAPI()
              } else {
                print("⚠️ Auto-update disabled, skipping automatic update")
                // Could show notification here in the future
              }
            } else {
              print("✅ No updates available via API")
            }
          } else {
            print("❌ Unexpected update check response format")
          }
        case .failure(let error):
          print("❌ API update check error: \(error)")
          // Fallback to manual check
          self?.checkForEmbeddedUpdate()
        }
      }
    }
  }

  func performUpdateViaAPI() {
    print("🔧 Performing update via MistServer API...")

    APIClient.shared.performUpdate { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let json):
          print("📡 Update response: \(json)")

          if let updateResult = json["update"] {
            print("✅ Update completed via API: \(updateResult)")

            // Update status after a delay to let server restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
              self?.updateStatusText()
            }
          }
        case .failure(let error):
          print("❌ API update error: \(error)")
        }
      }
    }
  }

  // MARK: — Legacy update system (for initial installation)

  @objc func dismissModalWindow(_ sender: NSButton) {
    NSApp.stopModal(withCode: .cancel)
  }

  @objc func acceptModalWindow(_ sender: NSButton) {
    NSApp.stopModal(withCode: .OK)
  }

  func performPushStart(streamName: String, targetURL: String) {
    print("🚀 MistTray: starting push for stream '\(streamName)' to '\(targetURL)'")

    pushManager.performPushStart(streamName: streamName, targetURL: targetURL) {
      [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Push Started",
            message: "Push from '\(streamName)' to '\(targetURL)' has been started successfully.")
          self?.updateAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Push Start Failed",
            message: "Failed to start push: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func showPreferences() {
    let currentSettings = PreferencesSettings(
      autoUpdateEnabled: UserDefaults.standard.bool(forKey: "AutoUpdateEnabled"),
      startServerOnLaunch: UserDefaults.standard.bool(forKey: "LaunchAtStartup"),
      showNotifications: UserDefaults.standard.bool(forKey: "ShowNotifications")
    )

    DialogManager.shared.showPreferencesDialog(currentSettings: currentSettings) {
      [weak self] preferences in
      guard let preferences = preferences else { return }

      // Save preferences to UserDefaults
      UserDefaults.standard.set(preferences.autoUpdateEnabled, forKey: "AutoUpdateEnabled")
      UserDefaults.standard.set(preferences.startServerOnLaunch, forKey: "LaunchAtStartup")
      UserDefaults.standard.set(preferences.showNotifications, forKey: "ShowNotifications")

      // Apply any immediate changes
      if preferences.autoUpdateEnabled {
        self?.checkForUpdates()
      }
    }
  }

  // MARK: - Data Updates

  private func updateAllData() {
    refreshAllData()
  }

  // MARK: - Unified State Management

  /// Refreshes ALL application data from the server and updates the complete state
  /// This is the single source of truth for application state updates
  private func refreshAllData() {
    print("🔄 Refreshing complete application state...")

    // Fetch all server data in one comprehensive call
    APIClient.shared.fetchAllServerData { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let data):
          self?.updateCompleteState(from: data)
        case .failure(let error):
          print("❌ Failed to refresh application state: \(error)")
        }
      }
    }
  }

  /// Updates the complete application state from server data
  /// This ensures all state variables are consistent and the menu reflects reality
  private func updateCompleteState(from serverData: [String: Any]) {
    print("📊 Updating complete application state...")

    // 1. Process all streams (configured streams, whether online or offline)
    allStreams = DataProcessor.shared.processAllStreams(serverData["streams"])

    // 2. Process active streams (only the ones currently streaming)
    if let activeStreamsList = serverData["active_streams"] as? [String] {
      activeStreams = activeStreamsList
    } else {
      activeStreams = []
    }

    // 3. Process stream statistics (for active streams only)
    streamStats = DataProcessor.shared.processStreamStats(serverData["stats_streams"])

    // 4. Process pushes
    activePushes = DataProcessor.shared.processPushList(serverData["push_list"])

    // 5. Process clients
    connectedClients = DataProcessor.shared.processClients(serverData["clients"])

    // 6. Process protocols (extract from config)
    if let config = serverData["config"] as? [String: Any],
      let protocols = config["protocols"] as? [String: Any]
    {
      lastProtocolData = protocols
    } else {
      lastProtocolData = [:]
    }

    // 7. Update UI with the complete, consistent state
    updateStatusText(checkStreams: false)
    rebuildMenu()

    print("✅ Application state updated successfully")
    print(
      "📊 State summary: \(allStreams.count) configured streams, \(activeStreams.count) active, \(activePushes.count) pushes, \(connectedClients.count) clients"
    )
  }

  // MARK: - Menu Management

  private func rebuildMenu() {
    buildMenu()
  }

  func buildMenu() {
    statusItem.menu = menuBuilder.buildMainMenu(
      serverRunning: mistServerManager.isMistServerRunning(),
      streams: allStreams,
      pushes: activePushes,
      clients: connectedClients,
      protocols: lastProtocolData
    )
  }

  func updateAllMenus() {
    buildMenu()
  }

  @objc func resetToFactoryDefaults() {
    if DialogManager.shared.confirmFactoryReset() {
      performFactoryReset()
    }
  }

  func performFactoryReset() {
    ConfigurationManager.shared.performFactoryReset { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Factory Reset Complete",
            message: "Configuration has been reset to factory defaults.")
          self?.updateAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Factory Reset Failed",
            message: "Failed to reset configuration: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func manageSessionTags() {
    // Simple implementation for session tag management
    DialogManager.shared.showInfoAlert(
      title: "Session Tag Management",
      message:
        "Session tag management functionality is available through the client management system."
    )
  }

  func processConfigurationExport(_ data: Data) {
    do {
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        DialogManager.shared.showErrorAlert(
          title: "Error", message: "Invalid configuration data received")
        return
      }
      ConfigurationManager.shared.saveConfigurationExport(configData: json) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Export Complete", message: "Configuration exported successfully.")
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Export Failed",
              message: "Failed to export configuration: \(error.localizedDescription)")
          }
        }
      }
    } catch {
      DialogManager.shared.showErrorAlert(
        title: "Error",
        message: "Failed to process configuration data: \(error.localizedDescription)")
    }
  }

  // MARK: — System Monitoring

  @objc func showServerStatistics() {
    print("🚀 MistTray: showing server statistics...")

    // Use existing state data - no need for separate API call
    DialogManager.shared.showServerStatistics(
      activeStreams: activeStreams.count,
      totalViewers: getTotalViewers(),
      activePushes: activePushes.count,
      totals: [:]  // Server totals will be included in unified state later
    )
  }

  // MARK: — Protocol Management

  @objc func viewActiveProtocols() {
    print("🚀 MistTray: viewing active protocols...")

    // Use existing protocol data from unified state
    DialogManager.shared.showActiveProtocols(protocols: lastProtocolData)
  }

  func showProtocolConfigWindow(_ protocolName: String) {
    DialogManager.shared.showProtocolConfigurationDialog(protocolName: protocolName) {
      [weak self] config in
      if let protocolConfig = config {
        print("✅ Protocol configuration updated: \(protocolConfig)")
        self?.refreshAllData()
      }
    }
  }

  func getDefaultPort(for protocolName: String) -> String {
    return UtilityManager.shared.getDefaultPort(for: protocolName)
  }

  func performProtocolAction(apiCall: [String: Any], actionName: String, protocolName: String) {
    print("📡 Sending \(actionName) protocol request for \(protocolName)...")

    APIClient.shared.performProtocolAction(apiCall: apiCall) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let data):
          print("📡 \(actionName.capitalized) protocol response: \(data)")
          DialogManager.shared.showSuccessAlert(
            title: "Protocol \(actionName.capitalized)d",
            message: "\(protocolName) protocol has been \(actionName)d successfully.")
        case .failure(let error):
          print("❌ \(actionName.capitalized) protocol error: \(error)")
          DialogManager.shared.showErrorAlert(
            title: "Protocol \(actionName.capitalized) Failed",
            message:
              "Failed to \(actionName) \(protocolName) protocol: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: — Auto-Push Rules Management

  @objc func manageAutoPushRules() {
    print("🚀 MistTray: managing auto-push rules...")

    // Fetch rules and show dialog
    pushManager.listAutoPushRules { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let rules):
          self?.showAutoPushRulesDialog(existingRules: rules)
        case .failure(let error):
          print("❌ Failed to fetch auto-push rules: \(error)")
          self?.showAutoPushRulesDialog(existingRules: [:])
        }
      }
    }
  }

  func showAutoPushRulesDialog(existingRules: [String: Any]) {
    DialogManager.shared.showAutoPushRulesDialog(existingRules: existingRules) {
      [weak self] action in
      switch action {
      case .addRule:
        self?.showAddAutoPushRuleDialog()
      case .deleteRule(let ruleId):
        self?.deleteAutoPushRule(withId: ruleId)
      case .close:
        break
      }
    }
  }

  func showAddAutoPushRuleDialog() {
    DialogManager.shared.showAddAutoPushRuleDialog { [weak self] streamPattern, targetURL in
      guard let streamPattern = streamPattern, let targetURL = targetURL else { return }
      self?.createAutoPushRule(streamPattern: streamPattern, targetURL: targetURL)
    }
  }

  func createAutoPushRule(streamPattern: String, targetURL: String) {
    print("🚀 MistTray: creating auto-push rule for '\(streamPattern)' to '\(targetURL)'")

    APIClient.shared.createAutoPushRule(streamPattern: streamPattern, targetURL: targetURL) {
      [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Auto-Push Rule Created",
            message: "Successfully created auto-push rule for '\(streamPattern)' → '\(targetURL)'")
          // Refresh the rules dialog
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self?.manageAutoPushRules()
          }
        case .failure(let error):
          print("❌ Auto-push rule creation error: \(error)")
          DialogManager.shared.showErrorAlert(
            title: "Rule Creation Failed",
            message: "Failed to create auto-push rule: \(error.localizedDescription)")
        }
      }
    }
  }

  func deleteAutoPushRule(withId ruleId: String) {
    print("🚀 MistTray: deleting auto-push rule: \(ruleId)")

    DialogManager.shared.showConfirmationAlert(
      title: "Delete Auto-Push Rule",
      message: "Are you sure you want to delete this auto-push rule? This action cannot be undone.",
      confirmButtonTitle: "Delete Rule",
      isDestructive: true
    ) { confirmed in
      guard confirmed else {
        print("🚫 Auto-push rule deletion cancelled by user")
        return
      }

      PushManager.shared.deleteAutoPushRule(ruleId: ruleId) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Auto-Push Rule Deleted", message: "Successfully deleted auto-push rule.")
          case .failure(let error):
            print("❌ Auto-push rule deletion error: \(error)")
            DialogManager.shared.showErrorAlert(
              title: "Deletion Failed",
              message: "Failed to delete auto-push rule: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  // MARK: - MenuBuilderDelegate Methods

  @objc func createNewStream() {
    print("🚀 MistTray: creating new stream...")

    DialogManager.shared.showCreateStreamDialog { [weak self] config in
      guard let streamConfig = config else { return }

      self?.streamManager.createStream(name: streamConfig.name, source: streamConfig.source) {
        result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Stream Created",
              message: "Stream '\(streamConfig.name)' has been created successfully.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Creation Failed",
              message: "Failed to create stream: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func editStream(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }
    print("🚀 MistTray: editing stream: \(streamName)")

    let currentConfig = allStreams[streamName] as? [String: Any] ?? [:]
    DialogManager.shared.showEditStreamDialog(streamName: streamName, currentConfig: currentConfig)
    { [weak self] config in
      guard let streamConfig = config else { return }

      // Update stream configuration
      self?.streamManager.updateStream(name: streamName, config: ["source": streamConfig.source]) {
        result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Stream Updated",
              message: "Stream '\(streamName)' has been updated successfully.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Update Failed",
              message: "Failed to update stream: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func deleteStream(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }
    print("🚀 MistTray: deleting stream: \(streamName)")

    DialogManager.shared.showConfirmationAlert(
      title: "Delete Stream",
      message:
        "Are you sure you want to delete the stream '\(streamName)'? This action cannot be undone.",
      confirmButtonTitle: "Delete",
      isDestructive: true
    ) { [weak self] confirmed in
      guard confirmed else { return }

      self?.streamManager.deleteStream(name: streamName) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Stream Deleted",
              message: "Stream '\(streamName)' has been deleted successfully.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Deletion Failed",
              message: "Failed to delete stream: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func manageStreamTags(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }
    print("🚀 MistTray: managing tags for stream: \(streamName)")

    DialogManager.shared.showStreamTagsDialog(streamName: streamName) { [weak self] tags in
      guard let tags = tags else { return }

      // Update stream tags
      self?.streamManager.updateStreamTags(streamName: streamName, tags: tags) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Tags Updated",
              message: "Tags for stream '\(streamName)' have been updated successfully.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Update Failed",
              message: "Failed to update tags: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func startNewPush() {
    print("🚀 MistTray: starting new push...")

    // Use existing stream data instead of separate API call
    let streamNames = Array(allStreams.keys)
    DialogManager.shared.showCreatePushDialog(availableStreams: streamNames) { [weak self] config in
      guard let pushConfig = config else { return }

      self?.pushManager.startPush(
        streamName: pushConfig.streamName, targetURL: pushConfig.targetURL
      ) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Push Started",
              message:
                "Push from '\(pushConfig.streamName)' to '\(pushConfig.targetURL)' has been started successfully."
            )
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Push Failed", message: "Failed to start push: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func stopPush(_ sender: NSMenuItem) {
    guard let pushId = sender.representedObject as? String else { return }
    print("🚀 MistTray: stopping push: \(pushId)")

    pushManager.stopPush(streamName: pushId) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Push Stopped", message: "Push has been stopped successfully.")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Stop Failed", message: "Failed to stop push: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func disconnectClient(_ sender: NSMenuItem) {
    guard let sessionId = sender.representedObject as? String else { return }
    print("🚀 MistTray: disconnecting client: \(sessionId)")

    clientManager.disconnectClient(sessionId: sessionId) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Client disconnected successfully")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Disconnect Failed",
            message: "Failed to disconnect client: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func kickAllViewers(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }
    print("🚀 MistTray: kicking all viewers from stream: \(streamName)")

    DialogManager.shared.showConfirmationAlert(
      title: "Kick All Viewers",
      message: "Are you sure you want to disconnect all viewers from stream '\(streamName)'?",
      confirmButtonTitle: "Kick All",
      isDestructive: true
    ) { [weak self] confirmed in
      guard confirmed else { return }

      self?.clientManager.kickAllViewers(streamName: streamName) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Viewers Kicked",
              message: "All viewers have been disconnected from stream '\(streamName)'.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Kick Failed", message: "Failed to kick viewers: \(error.localizedDescription)"
            )
          }
        }
      }
    }
  }

  @objc func forceReauth(_ sender: NSMenuItem) {
    guard let streamName = sender.representedObject as? String else { return }
    clientManager.forceReauthentication(streamName: streamName) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Re-authentication Forced",
            message: "All clients have been forced to re-authenticate.")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Re-auth Failed",
            message: "Failed to force re-authentication: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func enableProtocol(_ sender: NSMenuItem) {
    guard let protocolName = sender.representedObject as? String else { return }
    print("🚀 MistTray: enabling protocol: \(protocolName)")

    let apiCall = ["protocol_enable": protocolName]
    APIClient.shared.performProtocolAction(apiCall: apiCall) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Protocol enabled successfully")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Error", message: "Failed to enable protocol: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func disableProtocol(_ sender: NSMenuItem) {
    guard let protocolName = sender.representedObject as? String else { return }
    print("🚀 MistTray: disabling protocol: \(protocolName)")

    let apiCall = ["protocol_disable": protocolName]
    APIClient.shared.performProtocolAction(apiCall: apiCall) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Protocol disabled successfully")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Error", message: "Failed to disable protocol: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func configureProtocol(_ sender: NSMenuItem) {
    guard let protocolName = sender.representedObject as? String else { return }
    print("🚀 MistTray: configuring protocol: \(protocolName)")

    DialogManager.shared.showProtocolConfigurationDialog(protocolName: protocolName) {
      [weak self] config in
      if let protocolConfig = config {
        print("✅ Protocol configuration updated: \(protocolConfig)")
        self?.refreshAllData()
      }
    }
  }

  @objc func backupConfiguration() {
    print("🚀 MistTray: backing up configuration...")

    DialogManager.shared.showBackupConfigurationDialog { url in
      guard let url = url else { return }

      ConfigurationManager.shared.backupConfiguration(to: url) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Backup Complete",
              message: "Configuration backed up successfully to \(url.lastPathComponent)")
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Backup Failed",
              message: "Failed to save backup file: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func restoreConfiguration() {
    print("🚀 MistTray: restoring configuration...")

    DialogManager.shared.showRestoreConfigurationDialog { [weak self] url in
      guard let url = url else { return }

      if DialogManager.shared.confirmRestoreConfiguration() {
        ConfigurationManager.shared.restoreConfiguration(from: url) { result in
          DispatchQueue.main.async {
            switch result {
            case .success:
              DialogManager.shared.showSuccessAlert(
                title: "Configuration Restored",
                message: "Configuration has been successfully restored. The server will restart.")
              self?.mistServerManager.restartServer { success in
                DispatchQueue.main.async {
                  if success {
                    self?.refreshAllData()
                  }
                }
              }
            case .failure(let error):
              DialogManager.shared.showErrorAlert(
                title: "Restore Failed",
                message: "Failed to restore configuration: \(error.localizedDescription)")
            }
          }
        }
      }
    }
  }

  @objc func saveConfiguration() {
    print("🚀 MistTray: saving configuration...")

    ConfigurationManager.shared.saveConfiguration { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Configuration Saved", message: "Configuration has been saved successfully.")
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Save Failed",
            message: "Failed to save configuration: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func factoryReset() {
    print("🚀 MistTray: performing factory reset...")

    if DialogManager.shared.confirmFactoryReset() {
      ConfigurationManager.shared.performFactoryReset { [weak self] result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            DialogManager.shared.showSuccessAlert(
              title: "Factory Reset Complete",
              message: "Configuration has been reset to factory defaults.")
            self?.refreshAllData()
          case .failure(let error):
            DialogManager.shared.showErrorAlert(
              title: "Factory Reset Failed",
              message: "Failed to reset configuration: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  @objc func refreshMonitoring() {
    print("🚀 MistTray: refreshing monitoring data...")
    refreshAllData()
  }

  @objc func refreshProtocols() {
    print("🚀 MistTray: refreshing protocols...")
    refreshAllData()
  }

  // MARK: - Session Management

  func tagSessions(sessionIds: [String], tag: String) {
    ClientManager.shared.tagSessions(sessionIds: sessionIds, tag: tag) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let successCount):
          DialogManager.shared.showSuccessAlert(
            title: "Success", message: "Tagged \(successCount) session(s) with '\(tag)'")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Tagging Failed",
            message: "Failed to tag sessions: \(error.localizedDescription)")
        }
      }
    }
  }

  func showStopTaggedSessionsDialog() {
    DialogManager.shared.showStopTaggedSessionsDialog { [weak self] tagName in
      guard let tagName = tagName else { return }
      self?.stopTaggedSessions(tag: tagName)
    }
  }

  func stopTaggedSessions(tag: String) {
    print("🛑 Stopping all sessions with tag: \(tag)")

    APIClient.shared.stopTaggedSessions(tag: tag) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Successfully stopped sessions with tag: \(tag)")
          DialogManager.shared.showSuccessAlert(
            title: "Success", message: "Stopped all sessions tagged with '\(tag)'")
          self?.refreshAllData()
        case .failure(let error):
          print("❌ Failed to stop sessions with tag: \(tag)")
          DialogManager.shared.showErrorAlert(
            title: "Error",
            message: "Failed to stop sessions with tag '\(tag)': \(error.localizedDescription)")
        }
      }
    }
  }

  func showTaggedSessionsViewer() {
    DialogManager.shared.showTaggedSessionsViewer()
  }

  @objc func configurePushSettings() {
    print("⚙️ MistTray: configuring push settings...")

    DialogManager.shared.showPushSettingsDialog { [weak self] settings in
      guard let settings = settings else { return }
      self?.applyPushSettings(
        maxSpeed: settings.maxSpeed, waitTime: settings.waitTime, autoRestart: settings.autoRestart)
    }
  }

  func applyPushSettings(maxSpeed: Int, waitTime: Int, autoRestart: Bool) {
    APIClient.shared.applyPushSettings(
      maxSpeed: maxSpeed, waitTime: waitTime, autoRestart: autoRestart
    ) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Success", message: "Push settings applied successfully")
          self?.refreshAllData()
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Error", message: "Failed to apply push settings: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc func exportConfigurationWithMetadata() {
    ConfigurationManager.shared.exportConfigurationWithMetadata { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          DialogManager.shared.showSuccessAlert(
            title: "Export Complete", message: "Configuration exported successfully with metadata.")
        case .failure(let error):
          DialogManager.shared.showErrorAlert(
            title: "Export Failed",
            message: "Failed to export configuration: \(error.localizedDescription)")
        }
      }
    }
  }

  func restoreConfigurationData(_ jsonData: Data) {
    do {
      // Parse the JSON data
      if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
        // Send the configuration to MistServer
        APIClient.shared.restoreConfiguration(json) { [weak self] result in
          DispatchQueue.main.async {
            switch result {
            case .success:
              DialogManager.shared.showSuccessAlert(
                title: "Configuration Restored",
                message: "Configuration has been successfully restored. The server will restart.")
              self?.mistServerManager.restartServer { success in
                DispatchQueue.main.async {
                  if success {
                    self?.refreshAllData()
                  }
                }
              }
            case .failure(let error):
              DialogManager.shared.showErrorAlert(
                title: "Restore Failed",
                message: "Failed to restore configuration: \(error.localizedDescription)")
            }
          }
        }
      }
    } catch {
      DialogManager.shared.showErrorAlert(
        title: "Invalid Backup",
        message: "The backup file is corrupted or invalid: \(error.localizedDescription)")
    }
  }

}
