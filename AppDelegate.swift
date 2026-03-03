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

  // MARK: - New Architecture
  let appState = AppState()
  private var panelManager: PanelManager!

  // MARK: - Component Managers
  private let mistServerManager = MistServerManager.shared

  override init() {
    super.init()
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    panelManager = PanelManager(appState: appState)

    // 1) Create the menu bar icon
    setupStatusBarIcon()

    // 2) Detect server mode and running state
    appState.serverMode = mistServerManager.detectServerMode()
    appState.serverRunning = mistServerManager.isMistServerRunning(mode: appState.serverMode)

    // 3) Fetch capabilities (rarely changes, fetch once on launch)
    fetchCapabilities()

    // 4) Initial data refresh with auth check
    if appState.serverRunning {
      checkAuthAndRefresh()
    }

    // 5) Schedule regular data updates (every 10 seconds)
    activeStreamsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      // Re-detect mode on background queue to avoid blocking main thread
      DispatchQueue.global(qos: .utility).async {
        let mode = self.mistServerManager.detectServerMode()
        let running = self.mistServerManager.isMistServerRunning(mode: mode)
        DispatchQueue.main.async {
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
             let status = authorize["status"] as? String,
             status == "NOACC" {
            self.appState.needsSetup = true
          } else {
            self.appState.needsSetup = false
            self.refreshAllData()
          }
        case .failure:
          self.appState.needsSetup = false
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
      if let originalImage = NSImage(named: "StatusIcon") {
        let targetSize = NSSize(width: 16, height: 16)
        let resizedImage = NSImage(size: targetSize)

        resizedImage.lockFocus()
        let originalSize = originalImage.size
        let aspectRatio = originalSize.width / originalSize.height

        var drawSize = targetSize
        if aspectRatio > 1 {
          drawSize.height = targetSize.width / aspectRatio
        } else {
          drawSize.width = targetSize.height * aspectRatio
        }

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
    guard let url = URL(string: "http://localhost:4242") else { return }
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
            self?.appState.serverMode = self?.mistServerManager.detectServerMode() ?? .notFound
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
            self?.appState.serverMode = self?.mistServerManager.detectServerMode() ?? mode
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
    appState.allStreams = DataProcessor.shared.processAllStreams(serverData["streams"])

    if let activeStreamsDict = serverData["active_streams"] as? [String: Any] {
      appState.activeStreams = Array(activeStreamsDict.keys).sorted()
    } else if let activeStreamsList = serverData["active_streams"] as? [String] {
      appState.activeStreams = activeStreamsList.sorted()
    } else {
      appState.activeStreams = []
    }

    appState.streamStats = DataProcessor.shared.processStreamStats(serverData["stats_streams"])
    appState.activePushes = DataProcessor.shared.processPushList(serverData["push_list"])
    appState.connectedClients = DataProcessor.shared.processClients(serverData["clients"])

    if let config = serverData["config"] as? [String: Any],
      let protocols = config["protocols"] as? [String: Any]
    {
      appState.lastProtocolData = protocols
    } else {
      appState.lastProtocolData = [:]
    }

    if let logs = serverData["log"] as? [[Any]] {
      appState.serverLogs = logs
    }

    if let totals = serverData["totals"] as? [String: Any] {
      appState.serverTotals = totals
    }

    appState.lastRefreshDate = Date()
    appState.serverRunning = mistServerManager.isMistServerRunning(mode: appState.serverMode)
  }

  // MARK: - App Lifecycle

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    activeStreamsTimer?.invalidate()
  }
}
