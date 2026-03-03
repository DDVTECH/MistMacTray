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
        } else {
          ScrollView {
            VStack(spacing: 0) {
              serverStatusHeader
              Divider()
              if appState.serverMode == .external && appState.serverRunning {
                externalModeBanner
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
          EditStreamForm(appState: appState, streamName: name) { path.removeLast() }
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
        case .protocolConfig(let name):
          ProtocolConfigForm(protocolName: name) { path.removeLast() }
        case .pushSettings:
          PushSettingsForm { path.removeLast() }
        case .clients:
          ClientsView(appState: appState)
        case .logs:
          LogsView(appState: appState)
        }
      }
    }
    .frame(width: 380, height: 520)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Server Status Header

  private var serverStatusHeader: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(appState.serverRunning ? Color.green : Color.red)
        .frame(width: 10, height: 10)

      VStack(alignment: .leading, spacing: 2) {
        Text("MistServer")
          .font(.headline)
        Text(serverStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
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
    .foregroundStyle(.orange)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.1))
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
          if let url = URL(string: "http://localhost:4242") {
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
            appState.serverMode = manager.detectServerMode()
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
            appState.serverMode = manager.detectServerMode()
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
            path.append(Route.createStream)
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(.blue)
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
        Circle()
          .fill(appState.isStreamOnline(name) ? Color.green : Color.gray.opacity(0.4))
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(.system(.body, weight: .medium))
            .foregroundStyle(.primary)
          Text(appState.streamSource(name))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
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
            path.append(Route.createPush)
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(.blue)
              .frame(width: 24, height: 24)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .pointerOnHover()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)

      if appState.activePushes.isEmpty {
        Text("No active pushes")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      } else {
        ForEach(appState.sortedPushes, id: \.id) { push in
          pushRow(push: push)
        }
      }
    }
  }

  private func pushRow(push: (id: Int, stream: String, target: String)) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(push.stream)
          .font(.system(.body, weight: .medium))
        Text(push.target)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      if appState.isStoppingPush.contains(push.id) {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          appState.isStoppingPush.insert(push.id)
          PushManager.shared.stopPush(pushId: push.id) { result in
            DispatchQueue.main.async {
              appState.isStoppingPush.remove(push.id)
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
      HStack(spacing: 12) {
        footerButton("Auto-Push", icon: "arrow.triangle.2.circlepath") {
          path.append(Route.autoPushRules)
        }
        .disabled(!appState.serverRunning)

        footerButton("Clients", icon: "person.2") {
          path.append(Route.clients)
        }
        .disabled(!appState.serverRunning)

        footerButton("Logs", icon: "doc.text") {
          path.append(Route.logs)
        }
        .disabled(!appState.serverRunning)

        Spacer()
      }

      HStack(spacing: 12) {
        footerButton("Stats", icon: "chart.bar") {
          path.append(Route.statistics)
        }

        footerButton("Settings", icon: "gear") {
          path.append(Route.settings)
        }

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
  case settings
  case statistics
  case addStreamTag(String)
  case addAutoPushRule
  case autoPushRules
  case protocolConfig(String)
  case pushSettings
  case clients
  case logs
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
      .foregroundStyle(.blue)

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

/// NSViewRepresentable that uses addCursorRect to reliably set
/// the pointing hand cursor. This is the proper AppKit mechanism
/// and won't fight with SwiftUI's internal cursor management.
struct PointingHandCursor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = CursorView()
    view.wantsLayer = true
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    nsView.window?.invalidateCursorRects(for: nsView)
  }

  private class CursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
      return nil  // Let clicks pass through to the SwiftUI button underneath
    }

    override func resetCursorRects() {
      addCursorRect(bounds, cursor: .pointingHand)
    }
  }
}

extension View {
  /// Shows pointing hand cursor via AppKit cursor rects (reliable).
  func pointerOnHover() -> some View {
    self.overlay(PointingHandCursor())
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
      .overlay(PointingHandCursor())
      .onHover { hovering in
        isHovered = hovering
      }
  }
}
