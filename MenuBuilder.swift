//
//  MenuBuilder.swift
//  MistTray
//

import Cocoa

@objc protocol MenuBuilderDelegate: AnyObject {
  // Core Actions
  func openWebUI()
  func toggleServer()
  func restartServer()
  func showPreferences()

  // Stream Actions
  func createNewStream()
  func editStream(_ sender: NSMenuItem)
  func deleteStream(_ sender: NSMenuItem)
  func nukeStream(_ sender: NSMenuItem)
  func manageStreamTags(_ sender: NSMenuItem)

  // Push Actions
  func startNewPush()
  func stopPush(_ sender: NSMenuItem)
  func manageAutoPushRules()

  // Client Actions
  func disconnectClient(_ sender: NSMenuItem)
  func kickAllViewers(_ sender: NSMenuItem)
  func forceReauth(_ sender: NSMenuItem)

  // Protocol Actions
  func enableProtocol(_ sender: NSMenuItem)
  func disableProtocol(_ sender: NSMenuItem)
  func configureProtocol(_ sender: NSMenuItem)

  // Configuration Actions
  func backupConfiguration()
  func restoreConfiguration()
  func saveConfiguration()
  func factoryReset()

  // Monitoring Actions
  func refreshMonitoring()
  func refreshProtocols()
}

class MenuBuilder {
  weak var delegate: MenuBuilderDelegate?

  init(delegate: MenuBuilderDelegate) {
    self.delegate = delegate
  }

  // MARK: - Main Menu Building

  func buildMainMenu(
    serverRunning: Bool, streams: [String: Any], pushes: [String: Any], clients: [String: Any],
    protocols: [String: Any]
  ) -> NSMenu {
    let menu = NSMenu()

    // Server Status Section
    addServerSection(to: menu, serverRunning: serverRunning)
    menu.addItem(NSMenuItem.separator())

    // Streams Section
    addStreamsSection(to: menu, streams: streams)
    menu.addItem(NSMenuItem.separator())

    // Pushes Section
    addPushesSection(to: menu, pushes: pushes)
    menu.addItem(NSMenuItem.separator())

    // Clients Section
    addClientsSection(to: menu, clients: clients)
    menu.addItem(NSMenuItem.separator())

    // Protocols Section
    addProtocolsSection(to: menu, protocols: protocols)
    menu.addItem(NSMenuItem.separator())

    // Configuration Section
    addConfigurationSection(to: menu)
    menu.addItem(NSMenuItem.separator())

    // Quit
    let quitItem = NSMenuItem(
      title: "Quit MistTray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

    return menu
  }

  // MARK: - Server Section

  private func addServerSection(to menu: NSMenu, serverRunning: Bool) {
    let statusTitle = serverRunning ? "🟢 MistServer Running" : "🔴 MistServer Stopped"
    let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
    statusItem.isEnabled = false
    menu.addItem(statusItem)

    // Add basic server controls
    let webUIItem = NSMenuItem(
      title: "🌐 Open Web UI", action: #selector(MenuBuilderDelegate.openWebUI), keyEquivalent: "")
    webUIItem.target = delegate
    webUIItem.isEnabled = serverRunning
    menu.addItem(webUIItem)

    let toggleTitle = serverRunning ? "⏹ Stop Server" : "▶️ Start Server"
    let toggleItem = NSMenuItem(
      title: toggleTitle, action: #selector(MenuBuilderDelegate.toggleServer), keyEquivalent: "")
    toggleItem.target = delegate
    menu.addItem(toggleItem)

    let restartItem = NSMenuItem(
      title: "🔄 Restart Server", action: #selector(MenuBuilderDelegate.restartServer),
      keyEquivalent: "")
    restartItem.target = delegate
    restartItem.isEnabled = serverRunning
    menu.addItem(restartItem)
  }

  // MARK: - Streams Section

  private func addStreamsSection(to menu: NSMenu, streams: [String: Any]) {
    let streamsHeader = NSMenuItem(
      title: "📺 Streams (\(streams.count))", action: nil, keyEquivalent: "")
    streamsHeader.isEnabled = false
    menu.addItem(streamsHeader)

    let createStreamItem = NSMenuItem(
      title: "➕ Create New Stream", action: #selector(MenuBuilderDelegate.createNewStream),
      keyEquivalent: "")
    createStreamItem.target = delegate
    menu.addItem(createStreamItem)

    if !streams.isEmpty {
      for (streamName, streamData) in streams {
        let streamSubmenu = NSMenu()

        // Stream info
        if let data = streamData as? [String: Any] {
          let isOnline = (data["online"] as? Int) == 1
          let statusIcon = isOnline ? "🟢" : "🔴"
          let statusText = isOnline ? "Online" : "Offline"
          let source = data["source"] as? String ?? "Unknown"

          let statusItem = NSMenuItem(
            title: "\(statusIcon) \(statusText) • 📡 \(source)", action: nil, keyEquivalent: "")
          statusItem.isEnabled = false
          streamSubmenu.addItem(statusItem)
          streamSubmenu.addItem(NSMenuItem.separator())
        }

        // Stream actions
        let editItem = NSMenuItem(
          title: "✏️ Edit Stream", action: #selector(MenuBuilderDelegate.editStream(_:)),
          keyEquivalent: "")
        editItem.target = delegate
        editItem.representedObject = streamName
        streamSubmenu.addItem(editItem)

        let tagsItem = NSMenuItem(
          title: "🏷️ Manage Tags", action: #selector(MenuBuilderDelegate.manageStreamTags(_:)),
          keyEquivalent: "")
        tagsItem.target = delegate
        tagsItem.representedObject = streamName
        streamSubmenu.addItem(tagsItem)

        let nukeItem = NSMenuItem(
          title: "💥 Nuke Stream", action: #selector(MenuBuilderDelegate.nukeStream(_:)),
          keyEquivalent: "")
        nukeItem.target = delegate
        nukeItem.representedObject = streamName
        streamSubmenu.addItem(nukeItem)

        let deleteItem = NSMenuItem(
          title: "🗑 Delete Stream", action: #selector(MenuBuilderDelegate.deleteStream(_:)),
          keyEquivalent: "")
        deleteItem.target = delegate
        deleteItem.representedObject = streamName
        streamSubmenu.addItem(deleteItem)

        let streamItem = NSMenuItem(title: "📺 \(streamName)", action: nil, keyEquivalent: "")
        streamItem.submenu = streamSubmenu
        menu.addItem(streamItem)
      }
    } else {
      let noStreamsItem = NSMenuItem(
        title: "   📺 No configured streams", action: nil, keyEquivalent: "")
      noStreamsItem.isEnabled = false
      menu.addItem(noStreamsItem)
    }
  }

  // MARK: - Pushes Section

  private func addPushesSection(to menu: NSMenu, pushes: [String: Any]) {
    let pushesHeader = NSMenuItem(
      title: "📤 Pushes (\(pushes.count))", action: nil, keyEquivalent: "")
    pushesHeader.isEnabled = false
    menu.addItem(pushesHeader)

    let createPushItem = NSMenuItem(
      title: "➕ Start New Push", action: #selector(MenuBuilderDelegate.startNewPush),
      keyEquivalent: "")
    createPushItem.target = delegate
    menu.addItem(createPushItem)

    let managePushRulesItem = NSMenuItem(
      title: "🔧 Manage Auto-Push Rules", action: #selector(MenuBuilderDelegate.manageAutoPushRules),
      keyEquivalent: "")
    managePushRulesItem.target = delegate
    menu.addItem(managePushRulesItem)

    if !pushes.isEmpty {
      for (pushId, pushData) in pushes {
        if let data = pushData as? [String: Any],
          let target = data["target"] as? String,
          let stream = data["stream"] as? String
        {

          let stopItem = NSMenuItem(
            title: "⏹ Stop Push: \(stream) → \(target)",
            action: #selector(MenuBuilderDelegate.stopPush(_:)), keyEquivalent: "")
          stopItem.target = delegate
          stopItem.representedObject = pushId
          menu.addItem(stopItem)
        }
      }
    } else {
      let noPushesItem = NSMenuItem(title: "   📤 No active pushes", action: nil, keyEquivalent: "")
      noPushesItem.isEnabled = false
      menu.addItem(noPushesItem)
    }
  }

  // MARK: - Clients Section

  private func addClientsSection(to menu: NSMenu, clients: [String: Any]) {
    let totalClients = clients.count
    let clientsHeader = NSMenuItem(
      title: "👥 Clients (\(totalClients))", action: nil, keyEquivalent: "")
    clientsHeader.isEnabled = false
    menu.addItem(clientsHeader)

    if !clients.isEmpty {
      // Group clients by stream
      var streamClients: [String: [(String, [String: Any])]] = [:]

      for (sessionId, clientData) in clients {
        if let data = clientData as? [String: Any],
          let stream = data["stream"] as? String
        {
          if streamClients[stream] == nil {
            streamClients[stream] = []
          }
          streamClients[stream]?.append((sessionId, data))
        }
      }

      for (streamName, streamClientList) in streamClients {
        let streamSubmenu = NSMenu()

        let kickAllItem = NSMenuItem(
          title: "💥 Kick All Viewers", action: #selector(MenuBuilderDelegate.kickAllViewers(_:)),
          keyEquivalent: "")
        kickAllItem.target = delegate
        kickAllItem.representedObject = streamName
        streamSubmenu.addItem(kickAllItem)

        let forceReauthItem = NSMenuItem(
          title: "🔐 Force Re-authentication",
          action: #selector(MenuBuilderDelegate.forceReauth(_:)), keyEquivalent: "")
        forceReauthItem.target = delegate
        forceReauthItem.representedObject = streamName
        streamSubmenu.addItem(forceReauthItem)

        streamSubmenu.addItem(NSMenuItem.separator())

        for (sessionId, clientData) in streamClientList {
          let host = clientData["host"] as? String ?? "Unknown"
          let protocolName = clientData["protocol"] as? String ?? "Unknown"

          let disconnectItem = NSMenuItem(
            title: "🔌 Disconnect \(host) (\(protocolName))",
            action: #selector(MenuBuilderDelegate.disconnectClient(_:)), keyEquivalent: "")
          disconnectItem.target = delegate
          disconnectItem.representedObject = sessionId
          streamSubmenu.addItem(disconnectItem)
        }

        let streamItem = NSMenuItem(
          title: "📺 \(streamName) (\(streamClientList.count))", action: nil, keyEquivalent: "")
        streamItem.submenu = streamSubmenu
        menu.addItem(streamItem)
      }
    } else {
      let noClientsItem = NSMenuItem(
        title: "   👥 No connected clients", action: nil, keyEquivalent: "")
      noClientsItem.isEnabled = false
      menu.addItem(noClientsItem)
    }
  }

  // MARK: - Protocols Section

  private func addProtocolsSection(to menu: NSMenu, protocols: [String: Any]) {
    let protocolsHeader = NSMenuItem(title: "🔌 Protocols", action: nil, keyEquivalent: "")
    protocolsHeader.isEnabled = false
    menu.addItem(protocolsHeader)

    let refreshItem = NSMenuItem(
      title: "🔃 Refresh Protocols", action: #selector(MenuBuilderDelegate.refreshProtocols),
      keyEquivalent: "")
    refreshItem.target = delegate
    menu.addItem(refreshItem)

    if !protocols.isEmpty {
      for (protocolName, protocolData) in protocols {
        if let data = protocolData as? [String: Any] {
          let isEnabled = (data["online"] as? Int) == 1
          let statusIcon = isEnabled ? "🟢" : "🔴"

          let protocolSubmenu = NSMenu()

          if isEnabled {
            let disableItem = NSMenuItem(
              title: "⏹ Disable", action: #selector(MenuBuilderDelegate.disableProtocol(_:)),
              keyEquivalent: "")
            disableItem.target = delegate
            disableItem.representedObject = protocolName
            protocolSubmenu.addItem(disableItem)
          } else {
            let enableItem = NSMenuItem(
              title: "▶️ Enable", action: #selector(MenuBuilderDelegate.enableProtocol(_:)),
              keyEquivalent: "")
            enableItem.target = delegate
            enableItem.representedObject = protocolName
            protocolSubmenu.addItem(enableItem)
          }

          let configureItem = NSMenuItem(
            title: "⚙️ Configure", action: #selector(MenuBuilderDelegate.configureProtocol(_:)),
            keyEquivalent: "")
          configureItem.target = delegate
          configureItem.representedObject = protocolName
          protocolSubmenu.addItem(configureItem)

          let protocolItem = NSMenuItem(
            title: "\(statusIcon) \(protocolName)", action: nil, keyEquivalent: "")
          protocolItem.submenu = protocolSubmenu
          menu.addItem(protocolItem)
        }
      }
    }
  }

  // MARK: - Configuration Section

  private func addConfigurationSection(to menu: NSMenu) {
    let configHeader = NSMenuItem(title: "⚙️ Configuration", action: nil, keyEquivalent: "")
    configHeader.isEnabled = false
    menu.addItem(configHeader)

    let preferencesItem = NSMenuItem(
      title: "🔧 Preferences", action: #selector(MenuBuilderDelegate.showPreferences),
      keyEquivalent: ",")
    preferencesItem.target = delegate
    menu.addItem(preferencesItem)

    let backupItem = NSMenuItem(
      title: "💾 Backup Configuration", action: #selector(MenuBuilderDelegate.backupConfiguration),
      keyEquivalent: "")
    backupItem.target = delegate
    menu.addItem(backupItem)

    let restoreItem = NSMenuItem(
      title: "📥 Restore Configuration", action: #selector(MenuBuilderDelegate.restoreConfiguration),
      keyEquivalent: "")
    restoreItem.target = delegate
    menu.addItem(restoreItem)

    let saveItem = NSMenuItem(
      title: "💿 Save Configuration", action: #selector(MenuBuilderDelegate.saveConfiguration),
      keyEquivalent: "")
    saveItem.target = delegate
    menu.addItem(saveItem)

    let factoryResetItem = NSMenuItem(
      title: "🏭 Factory Reset", action: #selector(MenuBuilderDelegate.factoryReset),
      keyEquivalent: "")
    factoryResetItem.target = delegate
    menu.addItem(factoryResetItem)

    let refreshItem = NSMenuItem(
      title: "🔄 Refresh Data", action: #selector(MenuBuilderDelegate.refreshMonitoring),
      keyEquivalent: "r")
    refreshItem.target = delegate
    menu.addItem(refreshItem)
  }

  // MARK: - Helper Methods

  private func formatBandwidth(_ bps: Int) -> String {
    let units = ["bps", "Kbps", "Mbps", "Gbps"]
    var value = Double(bps)
    var unitIndex = 0

    while value >= 1000 && unitIndex < units.count - 1 {
      value /= 1000
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }
}
