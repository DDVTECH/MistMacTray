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

  // MARK: - SF Symbol Helpers

  static func sfSymbolImage(
    _ name: String, accessibilityDescription: String? = nil
  ) -> NSImage? {
    guard
      let image = NSImage(
        systemSymbolName: name, accessibilityDescription: accessibilityDescription)
    else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    return image.withSymbolConfiguration(config)
  }

  static func tintedSFSymbolImage(
    _ name: String, color: NSColor, accessibilityDescription: String? = nil
  ) -> NSImage? {
    guard
      let image = NSImage(
        systemSymbolName: name, accessibilityDescription: accessibilityDescription)
    else { return nil }
    let config = NSImage.SymbolConfiguration(paletteColors: [color])
      .applying(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    return image.withSymbolConfiguration(config)
  }

  private func makeItem(
    title: String,
    symbol: String,
    action: Selector? = nil,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.image = MenuBuilder.sfSymbolImage(symbol, accessibilityDescription: title)
    return item
  }

  private func makeItem(
    title: String,
    symbol: String,
    tintColor: NSColor,
    action: Selector? = nil,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.image = MenuBuilder.tintedSFSymbolImage(
      symbol, color: tintColor, accessibilityDescription: title)
    return item
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
    let statusTitle = serverRunning ? "MistServer Running" : "MistServer Stopped"
    let statusColor: NSColor = serverRunning ? .systemGreen : .systemRed
    let statusItem = makeItem(title: statusTitle, symbol: "circle.fill", tintColor: statusColor)
    statusItem.isEnabled = false
    menu.addItem(statusItem)

    let webUIItem = makeItem(
      title: "Open Web UI", symbol: "globe",
      action: #selector(MenuBuilderDelegate.openWebUI))
    webUIItem.target = delegate
    webUIItem.isEnabled = serverRunning
    menu.addItem(webUIItem)

    let toggleTitle = serverRunning ? "Stop Server" : "Start Server"
    let toggleSymbol = serverRunning ? "stop.fill" : "play.fill"
    let toggleItem = makeItem(
      title: toggleTitle, symbol: toggleSymbol,
      action: #selector(MenuBuilderDelegate.toggleServer))
    toggleItem.target = delegate
    menu.addItem(toggleItem)

    let restartItem = makeItem(
      title: "Restart Server", symbol: "arrow.triangle.2.circlepath",
      action: #selector(MenuBuilderDelegate.restartServer))
    restartItem.target = delegate
    restartItem.isEnabled = serverRunning
    menu.addItem(restartItem)
  }

  // MARK: - Streams Section

  private func addStreamsSection(to menu: NSMenu, streams: [String: Any]) {
    let streamsHeader = makeItem(title: "Streams (\(streams.count))", symbol: "tv")
    streamsHeader.isEnabled = false
    menu.addItem(streamsHeader)

    let createStreamItem = makeItem(
      title: "Create New Stream", symbol: "plus",
      action: #selector(MenuBuilderDelegate.createNewStream))
    createStreamItem.target = delegate
    menu.addItem(createStreamItem)

    if !streams.isEmpty {
      for (streamName, streamData) in streams {
        let streamSubmenu = NSMenu()

        // Stream info
        if let data = streamData as? [String: Any] {
          let isOnline = (data["online"] as? Int) == 1
          let statusText = isOnline ? "Online" : "Offline"
          let statusColor: NSColor = isOnline ? .systemGreen : .systemRed
          let source = data["source"] as? String ?? "Unknown"

          let statusItem = makeItem(
            title: "\(statusText) \u{2014} \(source)", symbol: "circle.fill",
            tintColor: statusColor)
          statusItem.isEnabled = false
          streamSubmenu.addItem(statusItem)
          streamSubmenu.addItem(NSMenuItem.separator())
        }

        // Stream actions
        let editItem = makeItem(
          title: "Edit Stream", symbol: "pencil",
          action: #selector(MenuBuilderDelegate.editStream(_:)))
        editItem.target = delegate
        editItem.representedObject = streamName
        streamSubmenu.addItem(editItem)

        let tagsItem = makeItem(
          title: "Manage Tags", symbol: "tag",
          action: #selector(MenuBuilderDelegate.manageStreamTags(_:)))
        tagsItem.target = delegate
        tagsItem.representedObject = streamName
        streamSubmenu.addItem(tagsItem)

        let nukeItem = makeItem(
          title: "Nuke Stream", symbol: "flame",
          action: #selector(MenuBuilderDelegate.nukeStream(_:)))
        nukeItem.target = delegate
        nukeItem.representedObject = streamName
        streamSubmenu.addItem(nukeItem)

        let deleteItem = makeItem(
          title: "Delete Stream", symbol: "trash",
          action: #selector(MenuBuilderDelegate.deleteStream(_:)))
        deleteItem.target = delegate
        deleteItem.representedObject = streamName
        streamSubmenu.addItem(deleteItem)

        let streamItem = makeItem(title: streamName, symbol: "tv")
        streamItem.submenu = streamSubmenu
        menu.addItem(streamItem)
      }
    } else {
      let noStreamsItem = makeItem(title: "No configured streams", symbol: "tv")
      noStreamsItem.isEnabled = false
      menu.addItem(noStreamsItem)
    }
  }

  // MARK: - Pushes Section

  private func addPushesSection(to menu: NSMenu, pushes: [String: Any]) {
    let pushesHeader = makeItem(
      title: "Pushes (\(pushes.count))", symbol: "square.and.arrow.up")
    pushesHeader.isEnabled = false
    menu.addItem(pushesHeader)

    let createPushItem = makeItem(
      title: "Start New Push", symbol: "plus",
      action: #selector(MenuBuilderDelegate.startNewPush))
    createPushItem.target = delegate
    menu.addItem(createPushItem)

    let managePushRulesItem = makeItem(
      title: "Manage Auto-Push Rules", symbol: "wrench",
      action: #selector(MenuBuilderDelegate.manageAutoPushRules))
    managePushRulesItem.target = delegate
    menu.addItem(managePushRulesItem)

    if !pushes.isEmpty {
      for (pushId, pushData) in pushes {
        if let data = pushData as? [String: Any],
          let target = data["target"] as? String,
          let stream = data["stream"] as? String
        {
          let stopItem = makeItem(
            title: "Stop Push: \(stream) \u{2192} \(target)", symbol: "stop.fill",
            action: #selector(MenuBuilderDelegate.stopPush(_:)))
          stopItem.target = delegate
          stopItem.representedObject = pushId
          menu.addItem(stopItem)
        }
      }
    } else {
      let noPushesItem = makeItem(title: "No active pushes", symbol: "square.and.arrow.up")
      noPushesItem.isEnabled = false
      menu.addItem(noPushesItem)
    }
  }

  // MARK: - Clients Section

  private func addClientsSection(to menu: NSMenu, clients: [String: Any]) {
    let totalClients = clients.count
    let clientsHeader = makeItem(title: "Clients (\(totalClients))", symbol: "person.2")
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

        let kickAllItem = makeItem(
          title: "Kick All Viewers", symbol: "person.2.slash",
          action: #selector(MenuBuilderDelegate.kickAllViewers(_:)))
        kickAllItem.target = delegate
        kickAllItem.representedObject = streamName
        streamSubmenu.addItem(kickAllItem)

        let forceReauthItem = makeItem(
          title: "Force Re-authentication", symbol: "lock.shield",
          action: #selector(MenuBuilderDelegate.forceReauth(_:)))
        forceReauthItem.target = delegate
        forceReauthItem.representedObject = streamName
        streamSubmenu.addItem(forceReauthItem)

        streamSubmenu.addItem(NSMenuItem.separator())

        for (sessionId, clientData) in streamClientList {
          let host = clientData["host"] as? String ?? "Unknown"
          let protocolName = clientData["protocol"] as? String ?? "Unknown"

          let disconnectItem = makeItem(
            title: "Disconnect \(host) (\(protocolName))", symbol: "xmark.circle",
            action: #selector(MenuBuilderDelegate.disconnectClient(_:)))
          disconnectItem.target = delegate
          disconnectItem.representedObject = sessionId
          streamSubmenu.addItem(disconnectItem)
        }

        let streamItem = makeItem(
          title: "\(streamName) (\(streamClientList.count))", symbol: "tv")
        streamItem.submenu = streamSubmenu
        menu.addItem(streamItem)
      }
    } else {
      let noClientsItem = makeItem(title: "No connected clients", symbol: "person.2")
      noClientsItem.isEnabled = false
      menu.addItem(noClientsItem)
    }
  }

  // MARK: - Protocols Section

  private func addProtocolsSection(to menu: NSMenu, protocols: [String: Any]) {
    let protocolsHeader = makeItem(title: "Protocols", symbol: "network")
    protocolsHeader.isEnabled = false
    menu.addItem(protocolsHeader)

    let refreshItem = makeItem(
      title: "Refresh Protocols", symbol: "arrow.clockwise",
      action: #selector(MenuBuilderDelegate.refreshProtocols))
    refreshItem.target = delegate
    menu.addItem(refreshItem)

    if !protocols.isEmpty {
      for (protocolName, protocolData) in protocols {
        if let data = protocolData as? [String: Any] {
          let isEnabled = (data["online"] as? Int) == 1
          let statusColor: NSColor = isEnabled ? .systemGreen : .systemRed

          let protocolSubmenu = NSMenu()

          if isEnabled {
            let disableItem = makeItem(
              title: "Disable", symbol: "stop.fill",
              action: #selector(MenuBuilderDelegate.disableProtocol(_:)))
            disableItem.target = delegate
            disableItem.representedObject = protocolName
            protocolSubmenu.addItem(disableItem)
          } else {
            let enableItem = makeItem(
              title: "Enable", symbol: "play.fill",
              action: #selector(MenuBuilderDelegate.enableProtocol(_:)))
            enableItem.target = delegate
            enableItem.representedObject = protocolName
            protocolSubmenu.addItem(enableItem)
          }

          let configureItem = makeItem(
            title: "Configure", symbol: "gearshape",
            action: #selector(MenuBuilderDelegate.configureProtocol(_:)))
          configureItem.target = delegate
          configureItem.representedObject = protocolName
          protocolSubmenu.addItem(configureItem)

          let protocolItem = makeItem(
            title: protocolName, symbol: "circle.fill", tintColor: statusColor)
          protocolItem.submenu = protocolSubmenu
          menu.addItem(protocolItem)
        }
      }
    }
  }

  // MARK: - Configuration Section

  private func addConfigurationSection(to menu: NSMenu) {
    let configHeader = makeItem(title: "Configuration", symbol: "gearshape")
    configHeader.isEnabled = false
    menu.addItem(configHeader)

    let preferencesItem = makeItem(
      title: "Preferences", symbol: "wrench",
      action: #selector(MenuBuilderDelegate.showPreferences), keyEquivalent: ",")
    preferencesItem.target = delegate
    menu.addItem(preferencesItem)

    let backupItem = makeItem(
      title: "Backup Configuration", symbol: "externaldrive",
      action: #selector(MenuBuilderDelegate.backupConfiguration))
    backupItem.target = delegate
    menu.addItem(backupItem)

    let restoreItem = makeItem(
      title: "Restore Configuration", symbol: "square.and.arrow.down",
      action: #selector(MenuBuilderDelegate.restoreConfiguration))
    restoreItem.target = delegate
    menu.addItem(restoreItem)

    let saveItem = makeItem(
      title: "Save Configuration", symbol: "internaldrive",
      action: #selector(MenuBuilderDelegate.saveConfiguration))
    saveItem.target = delegate
    menu.addItem(saveItem)

    let factoryResetItem = makeItem(
      title: "Factory Reset", symbol: "arrow.counterclockwise",
      action: #selector(MenuBuilderDelegate.factoryReset))
    factoryResetItem.target = delegate
    menu.addItem(factoryResetItem)

    let refreshItem = makeItem(
      title: "Refresh Data", symbol: "arrow.triangle.2.circlepath",
      action: #selector(MenuBuilderDelegate.refreshMonitoring), keyEquivalent: "r")
    refreshItem.target = delegate
    menu.addItem(refreshItem)
  }

}
