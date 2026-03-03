//
//  DetailViews.swift
//  MistTray
//

import SwiftUI

// MARK: - Stream Detail View

struct StreamDetailView: View {
  @Bindable var appState: AppState
  let streamName: String
  @Binding var path: NavigationPath

  @State private var tags: [String] = []
  @State private var isLoadingTags = false
  @State private var showDeleteConfirm = false
  @State private var showNukeConfirm = false

  private var isOnline: Bool { appState.isStreamOnline(streamName) }
  private var source: String { appState.streamSource(streamName) }
  private var viewers: Int { appState.streamViewerCount(streamName) }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: streamName)
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Circle()
              .fill(isOnline ? Color.green : Color.gray.opacity(0.4))
              .frame(width: 10, height: 10)
            Text(isOnline ? "Online" : "Offline")
              .font(.subheadline)
              .foregroundStyle(isOnline ? .primary : .secondary)
            Spacer()
            if isOnline && viewers > 0 {
              Label("\(viewers) viewers", systemImage: "person.2.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          GroupBox("Source") {
            HStack {
              Text(source)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
              Spacer()
            }
          }

          GroupBox {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("Tags")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                  path.append(Route.addStreamTag(streamName))
                } label: {
                  Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerOnHover()
              }

              if isLoadingTags {
                ProgressView()
                  .controlSize(.small)
              } else if tags.isEmpty {
                Text("No tags")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                FlowLayout(spacing: 6) {
                  ForEach(tags, id: \.self) { tag in
                    TagChip(tag: tag) {
                      removeTag(tag)
                    }
                  }
                }
              }
            }
          }

          if isOnline {
            let bw = appState.streamBandwidth(streamName)
            if bw > 0 {
              GroupBox("Bandwidth") {
                HStack {
                  Text(DataProcessor.shared.formatBandwidth(bw))
                    .font(.system(.body, design: .rounded))
                  Spacer()
                }
              }
            }
          }

          Divider()

          HStack(spacing: 12) {
            Button {
              path.append(Route.editStream(streamName))
            } label: {
              Label("Edit", systemImage: "pencil")
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerOnHover()

            if isOnline {
              Button(role: .destructive) {
                showNukeConfirm = true
              } label: {
                Label("Nuke", systemImage: "flame")
                  .contentShape(Rectangle())
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .pointerOnHover()
            }

            Spacer()

            Button(role: .destructive) {
              showDeleteConfirm = true
            } label: {
              Label("Delete", systemImage: "trash")
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerOnHover()
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { loadTags() }
    .confirmationDialog("Delete Stream", isPresented: $showDeleteConfirm) {
      Button("Delete", role: .destructive) { deleteStream() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete '\(streamName)'. Active viewers will be disconnected.")
    }
    .confirmationDialog("Nuke Stream", isPresented: $showNukeConfirm) {
      Button("Nuke", role: .destructive) { nukeStream() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will immediately disconnect all viewers and stop the stream.")
    }
  }

  private func loadTags() {
    isLoadingTags = true
    StreamManager.shared.fetchStreamTags(for: streamName) { result in
      DispatchQueue.main.async {
        isLoadingTags = false
        if case .success(let fetchedTags) = result {
          tags = fetchedTags
        }
      }
    }
  }

  private func removeTag(_ tag: String) {
    StreamManager.shared.removeStreamTag(streamName, tag: tag) { result in
      DispatchQueue.main.async {
        if case .success = result {
          tags.removeAll { $0 == tag }
        }
      }
    }
  }

  private func deleteStream() {
    StreamManager.shared.deleteStream(name: streamName) { result in
      DispatchQueue.main.async {
        if case .success = result {
          path.removeLast()
        }
      }
    }
  }

  private func nukeStream() {
    StreamManager.shared.nukeStream(name: streamName) { result in
      DispatchQueue.main.async {
        if case .success = result {
          path.removeLast()
        }
      }
    }
  }
}

// MARK: - Tag Chip

struct TagChip: View {
  let tag: String
  var onRemove: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Text(tag)
        .font(.caption)
      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.blue.opacity(0.1))
    .clipShape(Capsule())
  }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = arrangeSubviews(proposal: proposal, subviews: subviews)
    return result.size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = arrangeSubviews(proposal: proposal, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
    }
  }

  private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
    let maxWidth = proposal.width ?? .infinity
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth && x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x)
    }

    return (CGSize(width: maxX, height: y + rowHeight), positions)
  }
}

// MARK: - Statistics View

struct StatisticsView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Statistics")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Server overview
          if appState.serverRunning {
            GroupBox("Server") {
              VStack(alignment: .leading, spacing: 8) {
                statRow(label: "Uptime", value: appState.formattedUptime)
                statRow(label: "Bandwidth Out", value: appState.formattedTotalBandwidth)
                if appState.totalBandwidthIn > 0 {
                  statRow(
                    label: "Bandwidth In",
                    value: DataProcessor.shared.formatBandwidth(appState.totalBandwidthIn))
                }
              }
            }
          }

          // Current counts
          GroupBox("Current") {
            VStack(alignment: .leading, spacing: 8) {
              statRow(label: "Active Streams", value: "\(appState.activeStreamCount)")
              statRow(label: "Connected Viewers", value: "\(appState.viewerCount)")
              statRow(label: "Active Pushes", value: "\(appState.pushCount)")
            }
          }

          // System info from capabilities
          if !appState.serverCapabilities.isEmpty {
            let sysInfo = UtilityManager.shared.formatSystemStats(appState.serverCapabilities)
            if !sysInfo.isEmpty {
              GroupBox("System") {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(sysInfo.components(separatedBy: " | "), id: \.self) { part in
                    let pieces = part.split(separator: ":", maxSplits: 1)
                    if pieces.count == 2 {
                      statRow(
                        label: String(pieces[0]).trimmingCharacters(in: .whitespaces),
                        value: String(pieces[1]).trimmingCharacters(in: .whitespaces))
                    } else {
                      Text(part)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
              }
            }
          }

          // Per-stream breakdown
          if !appState.activeStreams.isEmpty {
            GroupBox("Active Streams") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.activeStreams, id: \.self) { name in
                  HStack {
                    Circle()
                      .fill(Color.green)
                      .frame(width: 6, height: 6)
                    Text(name)
                      .font(.system(.body, weight: .medium))
                    Spacer()
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
                }
              }
            }
          }

          // Protocols
          if !appState.lastProtocolData.isEmpty {
            GroupBox("Protocols") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.lastProtocolData.keys.sorted(), id: \.self) { name in
                  if let data = appState.lastProtocolData[name] as? [String: Any] {
                    HStack {
                      Circle()
                        .fill(
                          (data["online"] as? Int) == 1 ? Color.green : Color.gray.opacity(0.4)
                        )
                        .frame(width: 8, height: 8)
                      Text(name.uppercased())
                        .font(.system(.body, weight: .medium))
                      Spacer()
                      if let port = data["port"] as? Int {
                        Text(":\(port)")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                }
              }
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func statRow(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.system(.body, design: .rounded, weight: .semibold))
    }
  }
}

// MARK: - Connected Clients View

struct ClientsView: View {
  @Bindable var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Connected Clients")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("\(appState.viewerCount) connected client(s)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Spacer()
          }

          if appState.connectedClients.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "person.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No clients connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(appState.sortedClientStreamNames, id: \.self) { streamName in
              clientStreamGroup(streamName: streamName)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func clientStreamGroup(streamName: String) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label(streamName, systemImage: "tv")
            .font(.subheadline.weight(.semibold))
          Spacer()
          Menu {
            Button("Kick All Viewers") {
              ClientManager.shared.kickAllViewers(streamName: streamName) { _ in }
            }
            Button("Force Re-auth") {
              ClientManager.shared.forceReauthentication(streamName: streamName) { _ in }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .font(.caption)
              .frame(width: 24, height: 24)
              .contentShape(Rectangle())
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .pointerOnHover()
        }

        let clients = appState.clientsByStream[streamName] ?? []
        ForEach(clients, id: \.id) { client in
          clientRow(clientId: client.id, info: client.info)
        }
      }
    }
  }

  private func clientRow(clientId: String, info: [String: Any]) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(info["host"] as? String ?? "Unknown")
          .font(.system(.body, design: .monospaced))
        HStack(spacing: 8) {
          Text(info["protocol"] as? String ?? "?")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.blue.opacity(0.1))
            .clipShape(Capsule())
          if let conntime = info["conntime"] as? Int {
            let elapsed = Int(Date().timeIntervalSince1970) - conntime
            Text(DataProcessor.shared.formatDuration(elapsed))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer()
      if let sessId = info["sessId"] as? String {
        Button {
          ClientManager.shared.disconnectClient(sessionId: sessId) { _ in }
        } label: {
          Image(systemName: "xmark.circle")
            .font(.caption)
            .foregroundStyle(.red.opacity(0.7))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerOnHover()
      }
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Server Logs View

struct LogsView: View {
  @Bindable var appState: AppState
  @State private var filterText = ""

  private var filteredLogs: [[Any]] {
    let logs = appState.serverLogs.reversed()
    if filterText.isEmpty { return Array(logs) }
    return logs.filter { entry in
      entry.contains { item in
        String(describing: item).localizedCaseInsensitiveContains(filterText)
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Server Logs")
      Divider()

      // Filter bar
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.caption)
        TextField("Filter logs...", text: $filterText)
          .textFieldStyle(.plain)
          .font(.caption)
        if !filterText.isEmpty {
          Button {
            filterText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .frame(width: 16, height: 16)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .pointerOnHover()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 6)

      Divider()

      if appState.serverLogs.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "doc.text")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
          Text("No log entries")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, entry in
              logEntryRow(entry: entry)
            }
          }
          .padding(16)
        }
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func logEntryRow(entry: [Any]) -> some View {
    let timestamp: String = {
      if let ts = entry.first as? Int {
        return DataProcessor.shared.formatConnectionTime(ts)
      }
      return ""
    }()
    let category: String = entry.count > 1 ? String(describing: entry[1]) : ""
    let message: String = entry.count > 2 ? String(describing: entry[2]) : ""

    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        if !timestamp.isEmpty {
          Text(timestamp)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        if !category.isEmpty {
          Text(category)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(logCategoryColor(category))
        }
      }
      if !message.isEmpty {
        Text(message)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.primary)
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 2)
  }

  private func logCategoryColor(_ category: String) -> Color {
    let lower = category.lowercased()
    if lower.contains("error") || lower.contains("fail") { return .red }
    if lower.contains("warn") { return .orange }
    if lower.contains("info") { return .blue }
    return .secondary
  }
}

// MARK: - Auto Push Rules View

struct AutoPushRulesView: View {
  @Bindable var appState: AppState
  @Binding var path: NavigationPath

  @State private var rules: [String: Any] = [:]
  @State private var isLoading = true

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Auto-Push Rules")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Auto-push rules trigger when matching streams start.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              path.append(Route.addAutoPushRule)
            } label: {
              Label("Add Rule", systemImage: "plus.circle.fill")
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else if rules.isEmpty {
            Text("No auto-push rules configured")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 20)
          } else {
            ForEach(Array(rules.keys.sorted()), id: \.self) { ruleId in
              if let rule = rules[ruleId] as? [String: Any] {
                ruleRow(ruleId: ruleId, rule: rule)
              }
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { loadRules() }
  }

  private func ruleRow(ruleId: String, rule: [String: Any]) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(rule["stream"] as? String ?? "Unknown")
          .font(.system(.body, weight: .medium))
        Text(rule["target"] as? String ?? "Unknown")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Button(role: .destructive) {
        deleteRule(ruleId: ruleId)
      } label: {
        Image(systemName: "trash")
          .font(.caption)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()
    }
    .padding(.vertical, 4)
  }

  private func loadRules() {
    isLoading = true
    PushManager.shared.listAutoPushRules { result in
      DispatchQueue.main.async {
        isLoading = false
        if case .success(let fetchedRules) = result {
          rules = fetchedRules
        }
      }
    }
  }

  private func deleteRule(ruleId: String) {
    PushManager.shared.deleteAutoPushRule(ruleId: ruleId) { result in
      DispatchQueue.main.async {
        if case .success = result {
          rules.removeValue(forKey: ruleId)
        }
      }
    }
  }
}

// MARK: - Settings View

struct SettingsView: View {
  @Bindable var appState: AppState

  @State private var autoUpdate: Bool = false
  @State private var startOnLaunch: Bool = false
  @State private var showNotifications: Bool = false
  @State private var customBinaryPath: String = ""
  @State private var customConfigPath: String = ""
  @State private var hasChanges = false

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Settings")
      Divider()

      Form {
        Section("Server") {
          Toggle("Auto-update MistServer", isOn: $autoUpdate)
            .onChange(of: autoUpdate) { hasChanges = true }
          Toggle("Start server on app launch", isOn: $startOnLaunch)
            .onChange(of: startOnLaunch) { hasChanges = true }
          Toggle("Show notifications", isOn: $showNotifications)
            .onChange(of: showNotifications) { hasChanges = true }
        }

        Section {
          HStack {
            Text("Mode:")
              .foregroundStyle(.secondary)
            Text(appState.serverMode.description)
          }
          .font(.caption)

          VStack(alignment: .leading, spacing: 4) {
            Text("Custom Binary Path")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            HStack(spacing: 4) {
              TextField("Leave empty for auto-detection", text: $customBinaryPath)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: customBinaryPath) { hasChanges = true }
              Button("Browse...") {
                browseForBinary()
              }
              .font(.caption)
              .pointerOnHover()
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Custom Config Path")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            HStack(spacing: 4) {
              TextField("Leave empty for auto-detection", text: $customConfigPath)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: customConfigPath) { hasChanges = true }
              Button("Browse...") {
                browseForConfig()
              }
              .font(.caption)
              .pointerOnHover()
            }
          }
        } header: {
          Text("MistServer Binary")
        }

        Section("Configuration") {
          Button("Backup Configuration") {
            DialogManager.shared.showBackupConfigurationDialog { url in
              guard let url = url else { return }
              ConfigurationManager.shared.backupConfiguration(to: url) { _ in }
            }
          }

          Button("Restore Configuration") {
            DialogManager.shared.showRestoreConfigurationDialog { url in
              guard let url = url else { return }
              ConfigurationManager.shared.restoreConfiguration(from: url) { _ in }
            }
          }

          Button("Save Configuration") {
            ConfigurationManager.shared.saveConfiguration { _ in }
          }
        }

        Section("Advanced") {
          Button("Factory Reset", role: .destructive) {
            if DialogManager.shared.confirmFactoryReset() {
              appState.resetData()
              appState.serverRunning = false
              let mode = appState.serverMode

              ConfigurationManager.shared.performFactoryReset { result in
                guard case .success = result else { return }
                guard mode.canRestart else { return }
                MistServerManager.shared.restartServer(mode: mode) { success in
                  DispatchQueue.main.async {
                    appState.serverRunning = success
                    if success {
                      DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        (NSApp.delegate as? AppDelegate)?.checkAuthAndRefresh()
                      }
                    }
                  }
                }
              }
            }
          }
        }

        if hasChanges {
          HStack {
            Spacer()
            Button("Save Preferences") {
              savePreferences()
            }
            .keyboardShortcut(.defaultAction)
          }
        }
      }
      .formStyle(.grouped)
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      autoUpdate = UserDefaults.standard.bool(forKey: "AutoUpdateEnabled")
      startOnLaunch = UserDefaults.standard.bool(forKey: "LaunchAtStartup")
      showNotifications = UserDefaults.standard.bool(forKey: "ShowNotifications")
      customBinaryPath = UserDefaults.standard.string(forKey: "CustomBinaryPath") ?? ""
      customConfigPath = UserDefaults.standard.string(forKey: "CustomConfigPath") ?? ""
      hasChanges = false
    }
  }

  private func savePreferences() {
    UserDefaults.standard.set(autoUpdate, forKey: "AutoUpdateEnabled")
    UserDefaults.standard.set(startOnLaunch, forKey: "LaunchAtStartup")
    UserDefaults.standard.set(showNotifications, forKey: "ShowNotifications")
    UserDefaults.standard.set(customBinaryPath.trimmed, forKey: "CustomBinaryPath")
    UserDefaults.standard.set(customConfigPath.trimmed, forKey: "CustomConfigPath")
    hasChanges = false
    // Re-detect mode after path changes
    appState.serverMode = MistServerManager.shared.detectServerMode()
  }

  private func browseForBinary() {
    let panel = NSOpenPanel()
    panel.title = "Select MistController Binary"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      customBinaryPath = url.path
      hasChanges = true
    }
  }

  private func browseForConfig() {
    let panel = NSOpenPanel()
    panel.title = "Select MistServer Config File"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.json, .data]
    if panel.runModal() == .OK, let url = panel.url {
      customConfigPath = url.path
      hasChanges = true
    }
  }
}
