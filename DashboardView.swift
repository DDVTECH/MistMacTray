//
//  DashboardView.swift
//  MistTray
//

import SwiftUI

struct DashboardView: View {
  @Bindable var appState: AppState
  var closePanel: () -> Void

  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if appState.needsSetup && appState.serverRunning {
          VStack(spacing: 0) {
            serverStatusHeader
            Divider()
            SetupFormInline(appState: appState)
          }
        } else if appState.needsAuth && appState.serverRunning {
          VStack(spacing: 0) {
            serverStatusHeader
            Divider()
            LoginFormInline(appState: appState)
          }
        } else {
          ScrollView {
            VStack(spacing: 0) {
              serverStatusHeader
              Divider()
              if appState.serverMode == .external && appState.serverRunning {
                externalModeBanner
              }
              if appState.mistServerUpdateAvailable {
                mistServerUpdateBanner
              }
              if appState.mistTrayUpdateAvailable {
                mistTrayUpdateBanner
              }
              serverActions
              Divider()
              streamsSection
              Divider()
              pushesSection
              Divider()
              footerActions
            }
          }
        }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .createStream:
          CreateStreamForm(appState: appState) { path.removeLast() }
        case .editStream(let name):
          StreamEditWizardView(appState: appState, originalName: name) { path.removeLast() }
        case .streamDetail(let name):
          StreamDetailView(appState: appState, streamName: name, path: $path)
        case .createPush:
          CreatePushForm(appState: appState) { path.removeLast() }
        case .settings:
          SettingsView(appState: appState)
        case .statistics:
          StatisticsView(appState: appState)
        case .addStreamTag(let name):
          AddStreamTagForm(streamName: name) { path.removeLast() }
        case .addAutoPushRule:
          AddAutoPushRuleForm { path.removeLast() }
        case .autoPushRules:
          AutoPushRulesView(appState: appState, path: $path)
        case .protocolConfig(let name, let index):
          ProtocolConfigForm(appState: appState, protocolName: name, protocolIndex: index) { path.removeLast() }
        case .pushSettings:
          PushSettingsForm { path.removeLast() }
        case .clients:
          ClientsView(appState: appState)
        case .logs:
          LogsView(appState: appState)
        case .pushWizard:
          PushWizardView(appState: appState) { path.removeLast() }
        case .streamWizard:
          StreamWizardView(appState: appState) { path.removeLast() }
        case .protocols:
          ProtocolsView(appState: appState, path: $path)
        case .triggers:
          TriggersView(appState: appState, path: $path)
        case .variables:
          VariablesView(appState: appState)
        case .externalWriters:
          ExternalWritersView(appState: appState)
        case .jwkManagement:
          JWKManagementView(appState: appState)
        case .cameras:
          CamerasView(appState: appState)
        case .embedURLs(let name):
          EmbedURLsView(appState: appState, streamName: name)
        case .triggerWizard:
          TriggerWizardView(appState: appState) { path.removeLast() }
        case .editTrigger(let event, let index):
          TriggerEditView(appState: appState, eventName: event, handlerIndex: index) { path.removeLast() }
        case .streamKeys:
          StreamKeysView(appState: appState)
        }
      }
    }
    .tint(Color.tnAccent)
    .frame(width: 380, height: 520)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Server Status Header

  private var serverStatusHeader: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(appState.serverRunning ? Color.tnGreen : Color.tnRed)
        .frame(width: 10, height: 10)

      VStack(alignment: .leading, spacing: 2) {
        Text("MistServer")
          .font(.headline)
        HStack(spacing: 6) {
          Text(serverStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
          if appState.serverRunning && !appState.serverCapabilities.isEmpty {
            Text("CPU \(DataProcessor.shared.formatPercentage(appState.cpuUsagePercent))")
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .foregroundStyle(appState.cpuUsagePercent > 80 ? Color.tnOrange : Color.secondary)
            Text("MEM \(DataProcessor.shared.formatPercentage(appState.memoryPercent))")
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .foregroundStyle(appState.memoryPercent > 80 ? Color.tnOrange : Color.secondary)
          }
        }
      }

      Spacer()

      if appState.serverRunning && !appState.needsSetup {
        HStack(spacing: 16) {
          statBadge(value: "\(appState.streamCount)", label: "streams")
          statBadge(value: "\(appState.viewerCount)", label: "viewers")
          statBadge(value: "\(appState.pushCount)", label: "pushes")
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var serverStatusText: String {
    let mode = appState.serverMode
    if appState.serverRunning {
      switch mode {
      case .brew: return "Running (Homebrew)"
      case .binary: return "Running (Binary)"
      case .external: return "Running (External)"
      case .notFound: return "Running"
      }
    } else {
      if mode == .notFound { return "Not Installed" }
      return "Stopped"
    }
  }

  private func statBadge(value: String, label: String) -> some View {
    VStack(spacing: 1) {
      Text(value)
        .font(.system(.body, design: .rounded, weight: .semibold))
      Text(label)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - External Mode Banner

  private var externalModeBanner: some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.caption2)
      Text("Connected to an external instance. Start/restart controls are limited.")
        .font(.caption2)
    }
    .foregroundStyle(Color.tnOrange)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tnOrange.opacity(0.1))
  }

  // MARK: - Update Banners

  private var mistServerUpdateBanner: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.up.circle.fill")
        .font(.caption2)
      VStack(alignment: .leading, spacing: 1) {
        Text("MistServer \(appState.mistServerLatestVersion ?? "") available")
          .font(.caption2)
        if let current = appState.mistServerBaseVersion {
          Text("Current: \(current)")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if appState.serverMode == .brew {
        Button {
          updateMistServerBrew()
        } label: {
          Text("Update")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.tnAccent.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
      } else if case .binary = appState.serverMode {
        Button {
          if let url = URL(string: "https://github.com/DDVTECH/mistserver/releases/latest") {
            NSWorkspace.shared.open(url)
          }
        } label: {
          Text("Download")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.tnAccent.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
      }
    }
    .foregroundStyle(Color.tnAccent)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tnAccent.opacity(0.1))
  }

  private var mistTrayUpdateBanner: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.down.app.fill")
        .font(.caption2)
      Text("MistTray \(appState.mistTrayLatestVersion ?? "") available")
        .font(.caption2)
      Spacer()
      if appState.isInstallingTrayUpdate {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.installMistTrayUpdate()
          }
        } label: {
          Text("Install")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.tnGreen.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
      }
    }
    .foregroundStyle(Color.tnGreen)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tnGreen.opacity(0.1))
  }

  private func updateMistServerBrew() {
    DispatchQueue.global(qos: .userInitiated).async {
      let manager = MistServerManager.shared
      guard let brewCmd = manager.findBrew() else { return }
      manager.runShellCommand(brewCmd, arguments: ["upgrade", "mistserver"])
      DispatchQueue.main.async { [self] in
        if appState.serverRunning {
          restartServer()
        }
        if let appDelegate = NSApp.delegate as? AppDelegate {
          appDelegate.checkForAllUpdates()
        }
      }
    }
  }

  // MARK: - Server Actions

  private var serverActions: some View {
    HStack(spacing: 8) {
      Button {
        toggleServer()
      } label: {
        HStack(spacing: 4) {
          if appState.isTogglingServer {
            ProgressView()
              .controlSize(.small)
              .frame(width: 12, height: 12)
            Text(appState.serverRunning ? "Stopping..." : "Starting...")
              .font(.caption)
          } else {
            Label(
              appState.serverRunning ? "Stop" : "Start",
              systemImage: appState.serverRunning ? "stop.fill" : "play.fill"
            )
            .font(.caption)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .pointerOnHover()
      .disabled(
        appState.isTogglingServer || appState.isRestartingServer
        || (!appState.serverRunning && !appState.serverMode.canStart))

      if appState.serverRunning {
        if appState.serverMode.canRestart {
          Button {
            restartServer()
          } label: {
            HStack(spacing: 4) {
              if appState.isRestartingServer {
                ProgressView()
                  .controlSize(.small)
                  .frame(width: 12, height: 12)
                Text("Restarting...")
                  .font(.caption)
              } else {
                Label("Restart", systemImage: "arrow.clockwise")
                  .font(.caption)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .pointerOnHover()
          .disabled(appState.isTogglingServer || appState.isRestartingServer)
        }

        Button {
          if let url = URL(string: appState.serverURL) {
            NSWorkspace.shared.open(url)
          }
        } label: {
          Label("Web UI", systemImage: "globe")
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .pointerOnHover()
      }

      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func toggleServer() {
    let manager = MistServerManager.shared
    let mode = appState.serverMode

    appState.isTogglingServer = true
    if manager.isMistServerRunning() {
      manager.stopServer(mode: mode) { success in
        DispatchQueue.main.async {
          appState.serverRunning = !success
          appState.isTogglingServer = false
          if success {
            if let appDelegate = NSApp.delegate as? AppDelegate {
              appDelegate.redetectServerMode()
            }
          }
        }
      }
    } else {
      guard mode.canStart else {
        appState.isTogglingServer = false
        DialogManager.shared.showInfoAlert(
          title: "MistServer Not Found",
          message:
            "MistServer is not installed. You can install it via:\n\n"
            + "Homebrew:\n  brew tap ddvtech/mistserver\n  brew install mistserver\n\n"
            + "Or download from:\n  releases.mistserver.org"
        )
        return
      }
      manager.startServer(mode: mode) { success in
        DispatchQueue.main.async {
          appState.serverRunning = success
          appState.isTogglingServer = false
          if success {
            if let appDelegate = NSApp.delegate as? AppDelegate {
              appDelegate.redetectServerMode()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
              refreshData()
            }
          }
        }
      }
    }
  }

  private func restartServer() {
    let mode = appState.serverMode
    appState.isRestartingServer = true
    MistServerManager.shared.restartServer(mode: mode) { success in
      DispatchQueue.main.async {
        appState.serverRunning = success
        appState.isRestartingServer = false
        if success {
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            refreshData()
          }
        }
      }
    }
  }

  private func refreshData() {
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.refreshAllData()
    }
  }

  private func statusColor(_ name: String) -> Color {
    switch name {
    case "green": return .tnGreen
    case "yellow": return .tnYellow
    case "orange": return .tnOrange
    case "red": return .tnRed
    default: return .gray
    }
  }

  // MARK: - Streams Section

  private var streamsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("Streams", systemImage: "tv")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if appState.serverRunning {
          Button {
            path.append(Route.streamWizard)
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(Color.tnAccent)
              .frame(width: 24, height: 24)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .pointerOnHover()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)

      if appState.allStreams.isEmpty {
        Text("No configured streams")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      } else {
        ForEach(appState.sortedStreamNames, id: \.self) { name in
          streamRow(name: name)
        }
      }
    }
  }

  private func streamRow(name: String) -> some View {
    Button {
      path.append(Route.streamDetail(name))
    } label: {
      HStack(spacing: 10) {
        let status = appState.streamStatusLabel(name)
        Circle()
          .fill(statusColor(status.color))
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(.system(.body, weight: .medium))
            .foregroundStyle(.primary)
          HStack(spacing: 4) {
            if status.text != "Online" && status.text != "Offline" {
              Text(status.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor(status.color))
            }
            Text(appState.streamSource(name))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }

        Spacer()

        if appState.isStreamOnline(name) {
          let viewers = appState.streamViewerCount(name)
          if viewers > 0 {
            Label("\(viewers)", systemImage: "person.fill")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          let bw = appState.streamBandwidth(name)
          if bw > 0 {
            Text(DataProcessor.shared.formatBandwidth(bw))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverHighlight()
  }

  // MARK: - Pushes Section

  private var pushesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("Pushes", systemImage: "arrow.up.circle")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if appState.serverRunning {
          Button {
            path.append(Route.pushWizard)
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(Color.tnAccent)
              .frame(width: 24, height: 24)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .pointerOnHover()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)

      if appState.activePushes.isEmpty && appState.autoPushRules.isEmpty {
        Text("No active pushes")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      } else {
        // Auto-push rules
        if !appState.autoPushRules.isEmpty {
          ForEach(Array(appState.autoPushRules.keys.sorted()), id: \.self) { ruleId in
            if let rule = appState.autoPushRules[ruleId] as? [String: Any] {
              autoPushRow(ruleId: ruleId, rule: rule)
            }
          }
        }
        // Active pushes
        ForEach(appState.sortedEnhancedPushes) { push in
          pushRow(push: push)
        }
      }
    }
  }

  private static let deactivationMarker = "\u{1F4A4}deactivated\u{1F4A4}_"

  private func autoPushRow(ruleId: String, rule: [String: Any]) -> some View {
    let rawStream = rule["stream"] as? String ?? "?"
    let isDeactivated = rawStream.hasPrefix(Self.deactivationMarker)
    let stream = isDeactivated ? String(rawStream.dropFirst(Self.deactivationMarker.count)) : rawStream
    let target = rule["target"] as? String ?? "?"
    let notes = rule["x-LSP-notes"] as? String

    return HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Circle()
            .fill(isDeactivated ? Color.gray : Color.tnAccent)
            .frame(width: 6, height: 6)
          Text("Auto")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(isDeactivated ? .secondary : .tnAccent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background((isDeactivated ? Color.gray : Color.tnAccent).opacity(0.15))
            .clipShape(Capsule())
          Text(stream)
            .font(.system(.body, weight: .medium))
            .foregroundStyle(isDeactivated ? .secondary : .primary)
        }
        Text(target)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        if let notes = notes, !notes.isEmpty {
          Text(notes)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
      }

      Spacer()

      // Toggle enable/disable
      Button {
        toggleAutoPush(ruleId: ruleId, rule: rule, currentlyDeactivated: isDeactivated)
      } label: {
        Image(systemName: isDeactivated ? "play.circle" : "pause.circle")
          .foregroundStyle(isDeactivated ? .green : .orange)
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()

      Button {
        APIClient.shared.deleteAutoPushRule(ruleId: ruleId) { _ in
          DispatchQueue.main.async { appState.onDataChanged?() }
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
  }

  private func toggleAutoPush(ruleId: String, rule: [String: Any], currentlyDeactivated: Bool) {
    var updatedRule = rule
    let rawStream = rule["stream"] as? String ?? ""
    if currentlyDeactivated {
      // Activate: remove prefix
      updatedRule["stream"] = String(rawStream.dropFirst(Self.deactivationMarker.count))
    } else {
      // Deactivate: add prefix
      updatedRule["stream"] = Self.deactivationMarker + rawStream
    }
    // Remove then re-add with updated stream
    APIClient.shared.deleteAutoPushRule(ruleId: ruleId) { _ in
      APIClient.shared.addAutoPush(updatedRule) { _ in
        DispatchQueue.main.async { self.appState.onDataChanged?() }
      }
    }
  }

  private func pushRow(push: AppState.EnhancedPush) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(push.stream)
          .font(.system(.body, weight: .medium))
        Text(push.resolvedTarget != push.target ? push.resolvedTarget : push.target)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        HStack(spacing: 8) {
          if push.activeMs > 0 {
            Text(DataProcessor.shared.formatDuration(push.activeMs / 1000))
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(.secondary)
          }
          if push.bytes > 0 {
            Text(DataProcessor.shared.formatBytes(push.bytes))
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(.secondary)
          }
          if push.latency > 0 {
            Text("\(push.latency)ms")
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(push.latency > 1000 ? .orange : .secondary)
          }
          if push.pktLossCount > 0 {
            Text("loss:\(push.pktLossCount)")
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(.red)
          }
        }
      }

      Spacer()

      if appState.isStoppingPush.contains(push.id) {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          appState.isStoppingPush.insert(push.id)
          PushManager.shared.stopPush(pushId: push.id) { _ in
            DispatchQueue.main.async {
              appState.isStoppingPush.remove(push.id)
              appState.onDataChanged?()
            }
          }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  // MARK: - Footer Actions

  private var footerActions: some View {
    VStack(spacing: 6) {
      HStack(spacing: 10) {
        footerButton("Auto-Push", icon: "arrow.triangle.2.circlepath") {
          path.append(Route.autoPushRules)
        }
        .disabled(!appState.serverRunning)

        footerButton("Clients", icon: "person.2") {
          path.append(Route.clients)
        }
        .disabled(!appState.serverRunning)

        footerButton("Protocols", icon: "network") {
          path.append(Route.protocols)
        }
        .disabled(!appState.serverRunning)

        footerButton("Triggers", icon: "bolt.fill") {
          path.append(Route.triggers)
        }
        .disabled(!appState.serverRunning)

        Spacer()
      }

      HStack(spacing: 10) {
        footerButton("Stats", icon: "chart.bar") {
          path.append(Route.statistics)
        }

        footerButton("Logs", icon: "doc.text") {
          path.append(Route.logs)
        }
        .disabled(!appState.serverRunning)

        footerButton("Settings", icon: "gear") {
          path.append(Route.settings)
        }

        Menu {
          Button { path.append(Route.variables) } label: {
            Label("Variables", systemImage: "textformat.abc")
          }
          Button { path.append(Route.externalWriters) } label: {
            Label("External Writers", systemImage: "cloud")
          }
          Button { path.append(Route.jwkManagement) } label: {
            Label("JSON Web Keys", systemImage: "key")
          }
          Button { path.append(Route.streamKeys) } label: {
            Label("Stream Keys", systemImage: "lock.shield")
          }
          // Cameras & Devices - hidden until merged upstream
          // Button { path.append(Route.cameras) } label: {
          //   Label("Cameras & Devices", systemImage: "video")
          // }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!appState.serverRunning)

        Spacer()

        if let lastRefresh = appState.lastRefreshDate {
          Text(lastRefresh, style: .relative)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }

        Button {
          refreshData()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.caption)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .disabled(!appState.serverRunning)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.caption)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointerOnHover()
  }
}

// MARK: - Navigation Routes

enum Route: Hashable {
  case createStream
  case editStream(String)
  case streamDetail(String)
  case createPush
  case pushWizard
  case streamWizard
  case settings
  case statistics
  case addStreamTag(String)
  case addAutoPushRule
  case autoPushRules
  case protocolConfig(String, Int)
  case pushSettings
  case clients
  case logs
  case protocols
  case triggers
  case variables
  case externalWriters
  case jwkManagement
  case cameras
  case embedURLs(String)
  case triggerWizard
  case editTrigger(String, Int)
  case streamKeys
}

// MARK: - Reusable Navigation Header

struct NavHeader: View {
  let title: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "chevron.left")
            .font(.system(size: 12, weight: .semibold))
          Text("Back")
            .font(.subheadline)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
      }
      .buttonStyle(.plain)
      .pointerOnHover()
      .foregroundStyle(Color.tnAccent)

      Spacer()

      Text(title)
        .font(.headline)

      Spacer()

      Color.clear
        .frame(width: 50, height: 1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

// MARK: - Hover Modifiers

extension View {
  /// Shows pointing hand cursor on hover.
  func pointerOnHover() -> some View {
    self.onHover { inside in
      if inside {
        NSCursor.pointingHand.set()
      } else {
        NSCursor.arrow.set()
      }
    }
  }

  /// Shows pointing hand cursor + subtle background highlight on hover.
  func hoverHighlight() -> some View {
    modifier(HoverHighlightModifier())
  }
}

private struct HoverHighlightModifier: ViewModifier {
  @State private var isHovered = false

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
          .padding(.horizontal, 4)
      )
      .onHover { hovering in
        isHovered = hovering
        if hovering {
          NSCursor.pointingHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }
}

// MARK: - Tokyo Night Color Palette

extension Color {
  /// Soft blue — primary interactive accent (#7aa2f7)
  static let tnAccent = Color(red: 0.478, green: 0.635, blue: 0.969)
  /// Subtle accent background
  static let tnAccentBg = Color(red: 0.478, green: 0.635, blue: 0.969).opacity(0.12)
  /// Green — online / success (#9ece6a)
  static let tnGreen = Color(red: 0.620, green: 0.808, blue: 0.416)
  /// Red-pink — error / destructive (#f7768e)
  static let tnRed = Color(red: 0.969, green: 0.463, blue: 0.557)
  /// Orange — caution / warning (#ff9e64)
  static let tnOrange = Color(red: 1.0, green: 0.620, blue: 0.392)
  /// Yellow — initializing / pending (#e0af68)
  static let tnYellow = Color(red: 0.878, green: 0.686, blue: 0.408)
  /// Purple — pushes / secondary accent (#bb9af7)
  static let tnPurple = Color(red: 0.733, green: 0.604, blue: 0.969)
  /// Cyan — info badges / protocols (#7dcfff)
  static let tnCyan = Color(red: 0.490, green: 0.812, blue: 1.0)
  /// Teal — alternate highlight (#73daca)
  static let tnTeal = Color(red: 0.451, green: 0.855, blue: 0.792)
}
