//
//  DetailViews.swift
//  MistTray
//

import Charts
import SwiftUI

// MARK: - Stream Detail View

struct StreamDetailView: View {
  @Bindable var appState: AppState
  let streamName: String
  @Binding var path: NavigationPath

  private enum ConfirmAction: Equatable {
    case delete, nuke, stopSessions, invalidateSessions
    var message: String {
      switch self {
      case .delete: "Permanently delete '\(String())' and disconnect all viewers?"
      case .nuke: "Immediately kill all connections and stop this stream?"
      case .stopSessions: "Disconnect all current viewers from this stream?"
      case .invalidateSessions: "Force all viewers to re-authenticate?"
      }
    }
    var buttonLabel: String {
      switch self {
      case .delete: "Delete"
      case .nuke: "Nuke"
      case .stopSessions: "Stop Sessions"
      case .invalidateSessions: "Invalidate"
      }
    }
  }

  @State private var tags: [String] = []
  @State private var isLoadingTags = false
  @State private var confirmAction: ConfirmAction?
  @State private var streamInfo: [String: Any] = [:]
  @State private var infoTimer: Timer?
  @State private var processes: [[String: Any]] = []

  private var isOnline: Bool { appState.isStreamOnline(streamName) }
  private var source: String { appState.streamSource(streamName) }
  private var viewers: Int { appState.streamViewerCount(streamName) }

  private var httpPort: Int {
    for proto in appState.configuredProtocols {
      if let c = proto["connector"] as? String,
         c.uppercased().contains("HTTP"),
         !c.uppercased().contains("HTTPS"),
         let port = proto["port"] as? Int
      {
        return port
      }
    }
    return 8080
  }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: streamName)
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            let status = appState.streamStatusLabel(streamName)
            Circle()
              .fill(statusColor(status.color))
              .frame(width: 10, height: 10)
            Text(status.text)
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
                    .foregroundStyle(Color.tnAccent)
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
            GroupBox("Metrics") {
              VStack(alignment: .leading, spacing: 8) {
                let history = appState.streamHistory[streamName] ?? []
                if history.count >= 2 {
                  SparklineChart(
                    data: history.map { ($0.timestamp, Double($0.viewers)) },
                    color: .tnAccent,
                    label: "Viewers",
                    currentValue: "\(viewers)"
                  )
                  SparklineChart(
                    data: history.map { ($0.timestamp, Double($0.bpsOut)) },
                    color: .tnGreen,
                    label: "BW Out",
                    currentValue: DataProcessor.shared.formatBandwidth(appState.streamBandwidth(streamName))
                  )
                  let bwIn = appState.streamBandwidthIn(streamName)
                  if bwIn > 0 {
                    SparklineChart(
                      data: history.map { ($0.timestamp, Double($0.bpsIn)) },
                      color: .tnOrange,
                      label: "BW In",
                      currentValue: DataProcessor.shared.formatBandwidth(bwIn)
                    )
                  }
                } else {
                  let bwOut = appState.streamBandwidth(streamName)
                  let bwIn = appState.streamBandwidthIn(streamName)
                  HStack {
                    Text("BW Out")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text(DataProcessor.shared.formatBandwidth(bwOut))
                      .font(.system(.body, design: .rounded, weight: .semibold))
                  }
                  if bwIn > 0 {
                    HStack {
                      Text("BW In")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                      Spacer()
                      Text(DataProcessor.shared.formatBandwidth(bwIn))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    }
                  }
                }
              }
            }
          }

          if isOnline && !parsedTracks.isEmpty {
            GroupBox("Tracks") {
              VStack(alignment: .leading, spacing: 6) {
                ForEach(parsedTracks) { track in
                  VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                      Image(systemName: track.type.lowercased() == "video" ? "film" : track.type.lowercased() == "audio" ? "speaker.wave.2" : "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                      Text(track.summary)
                        .font(.system(size: 11, design: .monospaced))
                    }
                    let meta = trackMetaLine(track)
                    if !meta.isEmpty {
                      Text(meta)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                    }
                  }
                }
                if let bw = bufferWindow {
                  Divider()
                  HStack {
                    Text("Buffer")
                      .font(.system(size: 10))
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", Double(bw) / 1000.0))
                      .font(.system(size: 10, weight: .medium, design: .rounded))
                  }
                }
              }
            }
          }

          if isOnline {
            let streamClients = (appState.clientsByStream[streamName] ?? [])
              .filter { !($0.info["protocol"] as? String ?? "").hasPrefix("INPUT:") }
            if !streamClients.isEmpty {
              GroupBox("Connected Viewers (\(streamClients.count))") {
                VStack(alignment: .leading, spacing: 6) {
                  ForEach(streamClients, id: \.id) { client in
                    streamViewerRow(client.info)
                  }
                }
              }
            }
          }

          if isOnline && !processes.isEmpty {
            GroupBox("Processes") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(processes.enumerated()), id: \.offset) { _, proc in
                  processRow(proc)
                }
              }
            }
          }

          if isOnline {
            GroupBox("Playback") {
              Button {
                path.append(Route.embedURLs(streamName))
              } label: {
                HStack {
                  Label("Embed & URLs", systemImage: "link")
                    .font(.subheadline)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .pointerOnHover()
            }
          }

          Divider()

          // Inline confirmation banner
          if let action = confirmAction {
            GroupBox {
              VStack(spacing: 8) {
                HStack(spacing: 6) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.tnOrange)
                    .font(.caption)
                  Text(confirmMessage(action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                  Button("Cancel") { confirmAction = nil }
                    .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
                  Spacer()
                  Button(action.buttonLabel, role: .destructive) { executeConfirmAction(action) }
                    .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
                }
              }
            }
          }

          HStack(spacing: 8) {
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
              Menu {
                Button { confirmAction = .stopSessions } label: {
                  Label("Stop Sessions", systemImage: "stop.circle")
                }
                Button { confirmAction = .invalidateSessions } label: {
                  Label("Invalidate Sessions", systemImage: "arrow.counterclockwise")
                }
                Divider()
                Button(role: .destructive) { confirmAction = .nuke } label: {
                  Label("Nuke Stream", systemImage: "flame")
                }
              } label: {
                Label("Actions", systemImage: "ellipsis.circle")
                  .contentShape(Rectangle())
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
            }

            Spacer()

            Button(role: .destructive) {
              confirmAction = .delete
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
    .onAppear {
      loadTags()
      if isOnline { startInfoPolling() }
    }
    .onDisappear { stopInfoPolling() }
    .onChange(of: isOnline) { _, online in
      if online { startInfoPolling() } else { stopInfoPolling() }
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
          appState.onDataChanged?()
          path.removeLast()
        }
      }
    }
  }

  private func nukeStream() {
    StreamManager.shared.nukeStream(name: streamName) { result in
      DispatchQueue.main.async {
        if case .success = result {
          appState.onDataChanged?()
          path.removeLast()
        }
      }
    }
  }

  private func confirmMessage(_ action: ConfirmAction) -> String {
    switch action {
    case .delete: "Permanently delete '\(streamName)' and disconnect all viewers?"
    case .nuke: "Immediately kill all connections and stop this stream?"
    case .stopSessions: "Disconnect all current viewers from this stream?"
    case .invalidateSessions: "Force all viewers to re-authenticate?"
    }
  }

  private func executeConfirmAction(_ action: ConfirmAction) {
    confirmAction = nil
    switch action {
    case .delete:
      deleteStream()
    case .nuke:
      nukeStream()
    case .stopSessions:
      APIClient.shared.kickAllViewers(streamName: streamName) { result in
        DispatchQueue.main.async {
          if case .success = result { appState.onDataChanged?() }
        }
      }
    case .invalidateSessions:
      APIClient.shared.forceReauthentication(streamName: streamName) { result in
        DispatchQueue.main.async {
          if case .success = result { appState.onDataChanged?() }
        }
      }
    }
  }

  private func statusColor(_ name: String) -> Color {
    switch name {
    case "green": return .tnGreen
    case "yellow": return .tnYellow
    case "orange": return .tnOrange
    case "red": return .tnRed
    default: return .gray.opacity(0.4)
    }
  }

  // MARK: - Info JSON Polling

  private func startInfoPolling() {
    let encoded = streamName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? streamName
    let urlString = "http://localhost:\(httpPort)/json_\(encoded).js"
    fetchInfoJSON(urlString)
    infoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
      fetchInfoJSON(urlString)
    }
  }

  private func stopInfoPolling() {
    infoTimer?.invalidate()
    infoTimer = nil
  }

  private func fetchInfoJSON(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data = data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return }
      DispatchQueue.main.async { self.streamInfo = json }
    }.resume()

    // Also fetch process list
    fetchProcesses()
  }

  private func fetchProcesses() {
    APIClient.shared.fetchProcessList(streamName: streamName) { result in
      DispatchQueue.main.async {
        if case .success(let data) = result,
           let procList = data["proc_list"] {
          if let dict = procList as? [String: Any] {
            self.processes = dict.values.compactMap { $0 as? [String: Any] }
          } else if let arr = procList as? [[String: Any]] {
            self.processes = arr
          } else {
            self.processes = []
          }
        } else {
          self.processes = []
        }
      }
    }
  }

  private func processRow(_ proc: [String: Any]) -> some View {
    let name = proc["process"] as? String ?? "Unknown"
    let source = proc["source"] as? String
    let sink = proc["sink"] as? String
    let pid = proc["pid"]
    let activeSeconds = proc["active_seconds"] as? Int

    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(name)
          .font(.system(.body, weight: .medium))
        Spacer()
        if let pid = pid {
          Text("PID \(pid)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
      }

      if let source = source, !source.isEmpty {
        HStack(spacing: 4) {
          Text("Source:")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
          Text(source)
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      if let sink = sink, !sink.isEmpty {
        HStack(spacing: 4) {
          Text("Sink:")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
          Text(sink)
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      if let seconds = activeSeconds, seconds > 0 {
        Text("Active: \(DataProcessor.shared.formatDuration(seconds))")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      // Show logs if any
      if let logs = proc["logs"] as? [[Any]], !logs.isEmpty {
        VStack(alignment: .leading, spacing: 1) {
          ForEach(logs.suffix(3).indices, id: \.self) { i in
            let entry = logs[i]
            let msg = entry.count > 2 ? String(describing: entry[2]) : ""
            if !msg.isEmpty {
              Text(msg)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  private struct TrackDetail: Identifiable {
    let id: String
    let type: String
    let codec: String
    let summary: String
    var avgBitrate: Int?
    var peakBitrate: Int?
    var language: String?
    var jitter: Int?
    var bFrames: Int?
    var durationMs: Int?
  }

  private var parsedTracks: [TrackDetail] {
    guard let meta = streamInfo["meta"] as? [String: Any],
          let tracks = meta["tracks"] as? [String: Any]
    else { return [] }

    var result: [TrackDetail] = []
    for (key, value) in tracks.sorted(by: { $0.key < $1.key }) {
      guard let track = value as? [String: Any],
            let type = track["type"] as? String,
            let codec = track["codec"] as? String
      else { continue }

      let summary: String
      switch type.lowercased() {
      case "video":
        let w = track["width"] as? Int ?? 0
        let h = track["height"] as? Int ?? 0
        let fps = track["fpks"] as? Int ?? (track["fps"] as? Int ?? 0)
        let fpsStr = fps > 0 ? " \(fps > 100 ? fps / 1000 : fps)fps" : ""
        let res = w > 0 && h > 0 ? " \(w)x\(h)" : ""
        summary = "Video: \(codec)\(res)\(fpsStr)"
      case "audio":
        let rate = track["rate"] as? Int ?? 0
        let channels = track["channels"] as? Int ?? 0
        let rateStr = rate > 0 ? " \(rate / 1000)kHz" : ""
        let chStr = channels == 1 ? " mono" : channels == 2 ? " stereo" : channels > 0 ? " \(channels)ch" : ""
        summary = "Audio: \(codec)\(rateStr)\(chStr)"
      default:
        summary = "\(type.capitalized): \(codec)"
      }

      let firstMs = track["firstms"] as? Int ?? 0
      let lastMs = track["lastms"] as? Int ?? 0
      let duration = lastMs > firstMs ? lastMs - firstMs : nil

      var detail = TrackDetail(
        id: key, type: type, codec: codec, summary: summary,
        avgBitrate: track["bps"] as? Int,
        peakBitrate: track["maxbps"] as? Int,
        language: track["lang"] as? String,
        jitter: track["jitter"] as? Int,
        bFrames: track["bframes"] as? Int,
        durationMs: duration
      )
      if let lang = detail.language, lang.isEmpty { detail.language = nil }
      result.append(detail)
    }
    return result
  }

  private var bufferWindow: Int? {
    guard let meta = streamInfo["meta"] as? [String: Any],
          let source = meta["source"] as? [String: Any],
          let bw = source["buffer_window"] as? Int, bw > 0
    else { return nil }
    return bw
  }

  private func streamViewerRow(_ info: [String: Any]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(info["host"] as? String ?? "Unknown")
          .font(.system(size: 11, design: .monospaced))
          .lineLimit(1)
        Spacer()
        Text(info["protocol"] as? String ?? "?")
          .font(.system(size: 9, weight: .medium))
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Color.tnAccent.opacity(0.1))
          .clipShape(Capsule())
      }
      HStack(spacing: 8) {
        if let conntime = info["conntime"] as? Int {
          let elapsed = Int(Date().timeIntervalSince1970) - conntime
          Text(DataProcessor.shared.formatDuration(elapsed))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        if let downbps = info["downbps"] as? Int, downbps > 0 {
          Text(DataProcessor.shared.formatBandwidth(downbps))
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(Color.tnAccent)
        }
        if let down = info["down"] as? Int, down > 0 {
          Text(DataProcessor.shared.formatBytes(down))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        if let lost = info["pktlost"] as? Int, lost > 0 {
          Text("\(lost) lost")
            .font(.system(size: 10))
            .foregroundStyle(Color.tnRed)
        }
        if let retrans = info["pktretransmit"] as? Int, retrans > 0 {
          Text("\(retrans) retrans")
            .font(.system(size: 10))
            .foregroundStyle(Color.tnOrange)
        }
        Spacer()
      }
    }
    .padding(.vertical, 2)
  }

  private func trackMetaLine(_ track: TrackDetail) -> String {
    var parts: [String] = []
    if let bps = track.avgBitrate, bps > 0 {
      parts.append("Avg: \(DataProcessor.shared.formatBandwidth(bps))")
    }
    if let peak = track.peakBitrate, peak > 0 {
      parts.append("Peak: \(DataProcessor.shared.formatBandwidth(peak))")
    }
    if let lang = track.language {
      parts.append(lang)
    }
    if let jitter = track.jitter, jitter > 0 {
      parts.append("Jitter: \(jitter)ms")
    }
    if let bf = track.bFrames, bf > 0 {
      parts.append("B-frames")
    }
    if let dur = track.durationMs, dur > 0 {
      parts.append(DataProcessor.shared.formatDuration(dur / 1000))
    }
    return parts.joined(separator: " | ")
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
    .background(Color.tnAccent.opacity(0.1))
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

// MARK: - Sparkline Chart Component

struct SparklineChart: View {
  let data: [(Date, Double)]
  let color: Color
  let label: String
  let currentValue: String

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .leading)

      if data.count >= 2 {
        Chart {
          ForEach(Array(data.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("T", point.0), y: .value("V", point.1))
              .interpolationMethod(.catmullRom)
            AreaMark(x: .value("T", point.0), y: .value("V", point.1))
              .interpolationMethod(.catmullRom)
              .foregroundStyle(
                .linearGradient(
                  colors: [color.opacity(0.3), color.opacity(0.05)],
                  startPoint: .top, endPoint: .bottom))
          }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .foregroundStyle(color)
        .frame(height: 36)
      } else {
        Text("Collecting...")
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity)
          .frame(height: 36)
      }

      Text(currentValue)
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .frame(width: 70, alignment: .trailing)
    }
  }
}

// MARK: - Stat Card Component

struct StatCard: View {
  let value: String
  let label: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption)
        .foregroundStyle(color)
      Text(value)
        .font(.system(.title3, design: .rounded, weight: .bold))
      Text(label)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(color.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        VStack(alignment: .leading, spacing: 12) {
          // Server Health (CPU + Memory bars)
          if appState.serverRunning && !appState.serverCapabilities.isEmpty {
            serverHealthSection
          }

          // Traffic sparklines
          if appState.serverRunning {
            trafficSection
          }

          // Stat cards
          countsSection

          // Protocol distribution
          if !appState.clientProtocolCounts.isEmpty {
            protocolDistributionSection
          }

          // Connections breakdown
          if appState.serverRunning {
            connectionsSection
          }

          // Active streams sorted by viewers
          if !appState.activeStreams.isEmpty {
            activeStreamsSection
          }

          // Top viewers
          if !appState.connectedClients.isEmpty {
            topViewersSection
          }

          // System info
          if appState.serverRunning {
            systemSection
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Server Health

  private var serverHealthSection: some View {
    GroupBox("Server Health") {
      VStack(spacing: 8) {
        HStack {
          Text("CPU")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .leading)
          ProgressView(value: min(appState.cpuUsagePercent, 100), total: 100)
            .tint(colorForPercent(appState.cpuUsagePercent))
          Text(DataProcessor.shared.formatPercentage(appState.cpuUsagePercent))
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .frame(width: 48, alignment: .trailing)
        }
        HStack {
          Text("RAM")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .leading)
          ProgressView(value: min(appState.memoryPercent, 100), total: 100)
            .tint(colorForPercent(appState.memoryPercent))
          Text(DataProcessor.shared.formatPercentage(appState.memoryPercent))
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .frame(width: 48, alignment: .trailing)
        }
        if appState.memoryTotalMB > 0 {
          Text(
            "\(DataProcessor.shared.formatBytes(appState.memoryUsedMB * 1_048_576)) / \(DataProcessor.shared.formatBytes(appState.memoryTotalMB * 1_048_576))"
          )
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
  }

  // MARK: - Traffic Sparklines

  private var trafficSection: some View {
    GroupBox("Traffic") {
      VStack(spacing: 6) {
        SparklineChart(
          data: appState.totalsHistory.map { ($0.timestamp, Double($0.clients)) },
          color: .tnAccent,
          label: "Viewers",
          currentValue: "\(appState.viewerCount)"
        )
        SparklineChart(
          data: appState.totalsHistory.map { ($0.timestamp, Double($0.bpsOut)) },
          color: .tnGreen,
          label: "BW Out",
          currentValue: appState.formattedTotalBandwidth
        )
        SparklineChart(
          data: appState.totalsHistory.map { ($0.timestamp, Double($0.bpsIn)) },
          color: .tnOrange,
          label: "BW In",
          currentValue: DataProcessor.shared.formatBandwidth(appState.totalBandwidthIn)
        )
      }
    }
  }

  // MARK: - Stat Cards

  private var countsSection: some View {
    HStack(spacing: 8) {
      StatCard(
        value: "\(appState.activeStreamCount)", label: "Streams", icon: "tv", color: .tnAccent)
      StatCard(
        value: "\(appState.viewerCount)", label: "Viewers", icon: "person.2.fill", color: .tnGreen)
      StatCard(
        value: "\(appState.pushCount)", label: "Pushes", icon: "arrow.up.circle", color: .tnPurple)
    }
  }

  // MARK: - Protocol Distribution

  private var protocolDistributionSection: some View {
    let viewerProtocols = appState.clientProtocolCounts
      .filter { !$0.key.hasPrefix("INPUT:") }
      .sorted { $0.value > $1.value }
    let protoBW = appState.clientProtocolBandwidth

    return GroupBox("Viewers by Protocol") {
      VStack(spacing: 6) {
        ForEach(viewerProtocols, id: \.key) { proto, count in
          HStack {
            Text(proto)
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(width: 60, alignment: .leading)
            ProgressView(
              value: Double(count),
              total: Double(max(appState.viewerCount, 1))
            )
            .tint(.tnAccent)
            VStack(alignment: .trailing, spacing: 1) {
              Text("\(count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
              if let bw = protoBW[proto], bw > 0 {
                Text(DataProcessor.shared.formatBandwidth(bw))
                  .font(.system(size: 9))
                  .foregroundStyle(.tertiary)
              }
            }
            .frame(width: 60, alignment: .trailing)
          }
        }

        // Show INPUT protocols separately
        let inputProtocols = appState.clientProtocolCounts
          .filter { $0.key.hasPrefix("INPUT:") }
          .sorted { $0.value > $1.value }
        if !inputProtocols.isEmpty {
          Divider()
          ForEach(inputProtocols, id: \.key) { proto, count in
            HStack {
              Text(proto.replacingOccurrences(of: "INPUT:", with: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
              Text("input")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
              Spacer()
              Text("\(count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .frame(width: 30, alignment: .trailing)
            }
          }
        }
      }
    }
  }

  // MARK: - Connections Breakdown

  private var connectionsSection: some View {
    GroupBox("Connections") {
      VStack(spacing: 4) {
        HStack {
          Text("Total (from server)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(appState.totalConnectionCount)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        HStack {
          Text("Viewers (output)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(appState.viewerCount)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.tnGreen)
        }
        HStack {
          Text("Inputs")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(appState.inputConnectionCount)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.tnOrange)
        }
      }
    }
  }

  // MARK: - Active Streams

  private var activeStreamsSection: some View {
    GroupBox("Active Streams") {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(
          appState.activeStreams.sorted {
            appState.streamViewerCount($0) > appState.streamViewerCount($1)
          }, id: \.self
        ) { name in
          HStack {
            Circle().fill(Color.tnGreen).frame(width: 6, height: 6)
            Text(name)
              .font(.system(.body, weight: .medium))
              .lineLimit(1)
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

  // MARK: - Top Viewers

  private var topViewersSection: some View {
    let allViewers = appState.connectedClients.values
      .compactMap { $0 as? [String: Any] }
      .filter { !($0["protocol"] as? String ?? "").hasPrefix("INPUT:") }
      .sorted { ($0["downbps"] as? Int ?? 0) > ($1["downbps"] as? Int ?? 0) }
    let topN = Array(allViewers.prefix(10))

    return GroupBox("Top Viewers") {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(topN.enumerated()), id: \.offset) { _, viewer in
          HStack(spacing: 6) {
            Text(viewer["host"] as? String ?? "?")
              .font(.system(size: 11, design: .monospaced))
              .lineLimit(1)
            Spacer()
            if let stream = viewer["stream"] as? String {
              Text(stream)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Text(viewer["protocol"] as? String ?? "?")
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(Color.tnAccent.opacity(0.1))
              .clipShape(Capsule())
            Text(DataProcessor.shared.formatBandwidth(viewer["downbps"] as? Int ?? 0))
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(.secondary)
              .frame(width: 65, alignment: .trailing)
          }
        }
        if allViewers.count > 10 {
          Text("and \(allViewers.count - 10) more...")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
    }
  }

  // MARK: - System Info

  private var systemSection: some View {
    GroupBox("System") {
      VStack(alignment: .leading, spacing: 8) {
        statRow(label: "Uptime", value: appState.formattedUptime)
        statRow(
          label: "Bandwidth",
          value:
            "\(appState.formattedTotalBandwidth) out / \(DataProcessor.shared.formatBandwidth(appState.totalBandwidthIn)) in"
        )
        if let load = appState.loadAverages {
          statRow(
            label: "Load Avg",
            value: String(format: "%.2f  %.2f  %.2f", load.one, load.five, load.fifteen))
        }
      }
    }
  }

  // MARK: - Helpers

  private func statRow(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.system(.body, design: .rounded, weight: .semibold))
    }
  }

  private func colorForPercent(_ pct: Double) -> Color {
    if pct > 90 { return .tnRed }
    if pct > 70 { return .tnOrange }
    return .tnGreen
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

          if !appState.clientProtocolCounts.isEmpty {
            HStack(spacing: 6) {
              ForEach(
                appState.clientProtocolCounts.sorted(by: { $0.value > $1.value }), id: \.key
              ) { proto, count in
                Text("\(proto): \(count)")
                  .font(.system(size: 10, weight: .medium))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(Color.tnAccent.opacity(0.1))
                  .clipShape(Capsule())
              }
            }
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
              ClientManager.shared.kickAllViewers(streamName: streamName) { _ in
                DispatchQueue.main.async { appState.onDataChanged?() }
              }
            }
            Button("Force Re-auth") {
              ClientManager.shared.forceReauthentication(streamName: streamName) { _ in
                DispatchQueue.main.async { appState.onDataChanged?() }
              }
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
            .background(Color.tnAccent.opacity(0.1))
            .clipShape(Capsule())
          if let conntime = info["conntime"] as? Int {
            let elapsed = Int(Date().timeIntervalSince1970) - conntime
            Text(DataProcessor.shared.formatDuration(elapsed))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let downbps = info["downbps"] as? Int, downbps > 0 {
            Text(DataProcessor.shared.formatBandwidth(downbps))
              .font(.system(size: 10, design: .rounded))
              .foregroundStyle(Color.tnAccent)
          }
        }
      }
      Spacer()
      if let sessId = info["sessId"] as? String {
        Button {
          ClientManager.shared.disconnectClient(sessionId: sessId) { _ in
                  DispatchQueue.main.async { appState.onDataChanged?() }
                }
        } label: {
          Image(systemName: "xmark.circle")
            .font(.caption)
            .foregroundStyle(Color.tnRed.opacity(0.7))
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
    if lower.contains("error") || lower.contains("fail") { return .tnRed }
    if lower.contains("warn") { return .tnOrange }
    if lower.contains("info") { return .tnAccent }
    return .secondary
  }
}

// MARK: - Auto Push Rules View

struct AutoPushRulesView: View {
  @Bindable var appState: AppState
  @Binding var path: NavigationPath

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
              path.append(Route.pushWizard)
            } label: {
              Label("Add Rule", systemImage: "plus.circle.fill")
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if appState.autoPushRules.isEmpty {
            Text("No auto-push rules configured")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 20)
          } else {
            ForEach(Array(appState.autoPushRules.keys.sorted()), id: \.self) { ruleId in
              if let rule = appState.autoPushRules[ruleId] as? [String: Any] {
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

  private func deleteRule(ruleId: String) {
    APIClient.shared.deleteAutoPushRule(ruleId: ruleId) { result in
      DispatchQueue.main.async {
        if case .success = result {
          appState.onDataChanged?()
        }
      }
    }
  }
}

// MARK: - Settings View

struct SettingsView: View {
  @Bindable var appState: AppState

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
        Section("Updates") {
          HStack {
            Text("MistServer:")
              .foregroundStyle(.secondary)
            Text(appState.mistServerBaseVersion ?? "Unknown")
            if appState.mistServerUpdateAvailable,
              let latest = appState.mistServerLatestVersion
            {
              Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Color.tnAccent)
              Text(latest)
                .foregroundStyle(Color.tnAccent)
            }
          }
          .font(.caption)

          HStack {
            Text("MistTray:")
              .foregroundStyle(.secondary)
            Text(appState.mistTrayCurrentVersion)
            if appState.mistTrayUpdateAvailable,
              let latest = appState.mistTrayLatestVersion
            {
              Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Color.tnGreen)
              Text(latest)
                .foregroundStyle(Color.tnGreen)
            }
          }
          .font(.caption)

          HStack {
            Button {
              if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.checkForAllUpdates()
              }
            } label: {
              HStack(spacing: 4) {
                if appState.isCheckingForUpdates {
                  ProgressView()
                    .controlSize(.mini)
                } else {
                  Image(systemName: "arrow.clockwise")
                }
                Text("Check Now")
              }
            }
            .disabled(appState.isCheckingForUpdates)

            Spacer()

            if let lastCheck = appState.lastUpdateCheck {
              Text(lastCheck, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
          }
        }

        Section("Connection") {
          VStack(alignment: .leading, spacing: 4) {
            Text("Server URL")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            TextField("http://localhost:4242", text: Binding(
              get: { appState.serverURL },
              set: { appState.serverURL = $0; hasChanges = true }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
          }
        }

        Section("Server") {
          Toggle("Start server on app launch", isOn: $startOnLaunch)
            .onChange(of: startOnLaunch) { hasChanges = true }
          Toggle("Show notifications", isOn: $showNotifications)
            .onChange(of: showNotifications) { hasChanges = true }
        }

        if appState.discoveredInstallations.count > 1 {
          Section("Server Installation") {
            Picker("Active Installation", selection: Binding(
              get: {
                MistServerManager.shared.loadPreferredInstallation()
                  ?? appState.discoveredInstallations.first?.key ?? ""
              },
              set: { newKey in
                MistServerManager.shared.savePreferredInstallation(newKey)
                let installations = MistServerManager.shared.detectAllInstallations()
                appState.discoveredInstallations = installations
                appState.serverMode = MistServerManager.shared.resolveActiveMode(
                  installations: installations, preference: newKey)
              }
            )) {
              ForEach(appState.discoveredInstallations) { install in
                Text(install.label).tag(install.key)
              }
            }
            .pickerStyle(.inline)
            .font(.caption)
          }
        } else {
          Section("Server Installation") {
            HStack {
              Text("Mode:")
                .foregroundStyle(.secondary)
              Text(appState.serverMode.description)
            }
            .font(.caption)
          }
        }

        Section {
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
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                          appDelegate.enableDefaultProtocols {
                            appDelegate.checkAuthAndRefresh()
                          }
                        }
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
      startOnLaunch = UserDefaults.standard.bool(forKey: "LaunchAtStartup")
      showNotifications = UserDefaults.standard.bool(forKey: "ShowNotifications")
      customBinaryPath = UserDefaults.standard.string(forKey: "CustomBinaryPath") ?? ""
      customConfigPath = UserDefaults.standard.string(forKey: "CustomConfigPath") ?? ""
      hasChanges = false
    }
  }

  private func savePreferences() {
    UserDefaults.standard.set(startOnLaunch, forKey: "LaunchAtStartup")
    UserDefaults.standard.set(showNotifications, forKey: "ShowNotifications")
    UserDefaults.standard.set(customBinaryPath.trimmed, forKey: "CustomBinaryPath")
    UserDefaults.standard.set(customConfigPath.trimmed, forKey: "CustomConfigPath")
    hasChanges = false
    // Re-detect installations after path changes
    let installations = MistServerManager.shared.detectAllInstallations()
    let preference = MistServerManager.shared.loadPreferredInstallation()
    appState.discoveredInstallations = installations
    appState.serverMode = MistServerManager.shared.resolveActiveMode(
      installations: installations, preference: preference)
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
