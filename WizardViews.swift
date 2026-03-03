//
//  WizardViews.swift
//  MistTray
//

import SwiftUI

// MARK: - Push Scenario Definitions

enum PushScenarioGroup: String, CaseIterable {
  case record = "Record"
  case server = "Push to Server"
  case platform = "Push to Platform"
}

struct PushScenario: Identifiable {
  let id: String
  let group: PushScenarioGroup
  let title: String
  let icon: String
  let description: String
  let targetPrefix: String?
  let prefixOptions: [String]?  // Multiple prefix choices (e.g. rtmp:// and rtmps://)
  let isPlatform: Bool

  static let all: [PushScenario] = [
    // Record
    PushScenario(id: "record_file", group: .record, title: "Record to File",
                 icon: "doc.fill", description: "Save stream to local file (TS, MKV, MP4)",
                 targetPrefix: nil, prefixOptions: nil, isPlatform: false),
    PushScenario(id: "record_dvr", group: .record, title: "Live DVR (HLS)",
                 icon: "play.rectangle.on.rectangle", description: "HLS playlist with rolling segments",
                 targetPrefix: nil, prefixOptions: nil, isPlatform: false),
    PushScenario(id: "record_cloud", group: .record, title: "Record to Cloud",
                 icon: "cloud.fill", description: "Save to S3 or other cloud storage",
                 targetPrefix: nil, prefixOptions: nil, isPlatform: false),
    // Server
    PushScenario(id: "push_rtmp", group: .server, title: "RTMP / RTMPS",
                 icon: "arrow.up.right.circle", description: "Push via RTMP to another server",
                 targetPrefix: "rtmp://", prefixOptions: ["rtmp://", "rtmps://"], isPlatform: false),
    PushScenario(id: "push_srt", group: .server, title: "SRT",
                 icon: "arrow.up.right.circle", description: "Push via SRT protocol",
                 targetPrefix: "srt://", prefixOptions: nil, isPlatform: false),
    PushScenario(id: "push_ts", group: .server, title: "MPEG-TS",
                 icon: "arrow.up.right.circle", description: "Push via UDP/TCP/RTP transport stream",
                 targetPrefix: "tsudp://", prefixOptions: ["tsudp://", "tstcp://", "tsrtp://"], isPlatform: false),
    PushScenario(id: "push_other", group: .server, title: "Other Protocol",
                 icon: "arrow.up.right.circle", description: "RIST, RTSP, WHIP, DTSC, or any supported protocol",
                 targetPrefix: nil, prefixOptions: nil, isPlatform: false),
    // Platform
    PushScenario(id: "cdn_youtube", group: .platform, title: "YouTube Live",
                 icon: "play.rectangle.fill", description: "Stream to YouTube Live",
                 targetPrefix: "rtmp://a.rtmp.youtube.com/live2/", prefixOptions: nil, isPlatform: true),
    PushScenario(id: "cdn_twitch", group: .platform, title: "Twitch",
                 icon: "play.rectangle.fill", description: "Stream to Twitch",
                 targetPrefix: "rtmp://live.twitch.tv/app/", prefixOptions: nil, isPlatform: true),
    PushScenario(id: "cdn_facebook", group: .platform, title: "Facebook Live",
                 icon: "play.rectangle.fill", description: "Stream to Facebook",
                 targetPrefix: "rtmps://live-api-s.facebook.com:443/rtmp/", prefixOptions: nil, isPlatform: true),
    PushScenario(id: "cdn_kick", group: .platform, title: "Kick",
                 icon: "play.rectangle.fill", description: "Stream to Kick",
                 targetPrefix: "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/",
                 prefixOptions: nil, isPlatform: true),
    PushScenario(id: "cdn_custom", group: .platform, title: "Custom Platform",
                 icon: "globe", description: "X, Instagram, TikTok, Restream, or any RTMP/RTMPS ingest",
                 targetPrefix: nil, prefixOptions: nil, isPlatform: true),
  ]

  static func grouped() -> [(group: PushScenarioGroup, scenarios: [PushScenario])] {
    PushScenarioGroup.allCases.map { group in
      (group: group, scenarios: all.filter { $0.group == group })
    }
  }
}

// MARK: - Template Variables

private let templateVariables = [
  "$stream", "$basename", "$wildcard", "$pluswildcard",
  "$datetime", "$year", "$month", "$day", "$yday",
  "$hour", "$minute", "$seconds",
]

private let dvrTemplateVariables = [
  "$segmentCounter", "$currentMediaTime",
]

// MARK: - Schedule Mode

enum PushScheduleMode: String, CaseIterable {
  case now = "Start Now"
  case always = "Always Active"
  case scheduled = "Scheduled"
  case conditional = "Conditional"
}

// MARK: - Push Wizard View (4 Steps)

struct PushWizardView: View {
  @Bindable var appState: AppState
  var dismiss: () -> Void

  @State private var step = 0
  @State private var selectedScenario: PushScenario?
  // Step 2: Configure
  @State private var streamText = ""
  @State private var useStreamPicker = true
  @State private var selectedStream = ""
  @State private var targetURL = ""
  @State private var selectedPrefix = ""
  @State private var streamKey = ""
  @State private var notes = ""
  // DVR params
  @State private var dvrPlaylist = "playlist.m3u8"
  @State private var dvrSplit = "24"
  @State private var dvrMaxEntries = "3600"
  @State private var dvrTargetAge = "0"
  // Step 3: Schedule
  @State private var scheduleMode: PushScheduleMode = .now
  @State private var scheduleStart = Date()
  @State private var scheduleEnd = Date().addingTimeInterval(3600)
  @State private var startRuleVar = ""
  @State private var startRuleOp = "=="
  @State private var startRuleVal = ""
  @State private var endRuleVar = ""
  @State private var endRuleOp = "=="
  @State private var endRuleVal = ""
  @State private var isEnabled = true
  // State
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private let stepNames = ["Scenario", "Configure", "Schedule", "Review"]
  private let conditionOps = ["==", "!=", ">", ">=", "<", "<="]

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "New Push")
      Divider()

      // Step indicator — sliding window of 3 visible out of 4
      HStack(spacing: 0) {
        let windowStart = max(0, min(step - 1, stepNames.count - 3))
        let visible = Array(windowStart..<min(windowStart + 3, stepNames.count))
        ForEach(Array(visible.enumerated()), id: \.offset) { idx, i in
          HStack(spacing: 4) {
            Circle()
              .fill(i <= step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(width: 8, height: 8)
            Text(stepNames[i])
              .font(.system(size: 10, weight: i == step ? .semibold : .regular))
              .foregroundStyle(i == step ? .primary : .secondary)
          }
          if idx < visible.count - 1 {
            Rectangle()
              .fill(i < step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(height: 1)
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 2)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .animation(.easeInOut(duration: 0.2), value: step)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch step {
          case 0: scenarioStep
          case 1: configureStep
          case 2: scheduleStep
          case 3: reviewStep
          default: EmptyView()
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      selectedStream = appState.sortedStreamNames.first ?? ""
    }
  }

  // MARK: - Step 1: Scenario Selection

  private var scenarioStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(PushScenario.grouped(), id: \.group) { group in
        Text(group.group.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(group.scenarios) { scenario in
          let available = isScenarioAvailable(scenario)
          Button {
            guard available else { return }
            selectedScenario = scenario
            selectedPrefix = scenario.targetPrefix ?? ""
            step = 1
          } label: {
            HStack(spacing: 10) {
              Image(systemName: scenario.icon)
                .font(.body)
                .foregroundStyle(available ? Color.tnAccent : Color.gray)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(available ? .primary : .secondary)
                Text(scenario.description)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .opacity(available ? 1 : 0.5)
          .hoverHighlight()
        }
      }
    }
  }

  private func isScenarioAvailable(_ scenario: PushScenario) -> Bool {
    if scenario.id == "record_cloud" {
      return !appState.writerProtocols.isEmpty
    }
    return true
  }

  // MARK: - Step 2: Configure

  private var configureStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let scenario = selectedScenario {
        scenarioChip(scenario)

        // Stream selector with free-text option
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Stream")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            Spacer()
            Button(useStreamPicker ? "Free text" : "Pick stream") {
              useStreamPicker.toggle()
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundStyle(Color.tnAccent)
            .pointerOnHover()
          }
          if useStreamPicker {
            Picker("Stream", selection: $selectedStream) {
              if appState.sortedStreamNames.isEmpty {
                Text("No streams available").tag("")
              }
              ForEach(appState.sortedStreamNames, id: \.self) { name in
                Text(name).tag(name)
              }
            }
            .labelsHidden()
          } else {
            TextField("Stream name, pattern (live+), or #tag", text: $streamText)
              .textFieldStyle(.roundedBorder)
          }
        }

        // Target configuration (varies by scenario)
        if scenario.isPlatform {
          platformTargetConfig(scenario)
        } else {
          switch scenario.id {
          case "record_file": fileTargetConfig
          case "record_dvr": dvrTargetConfig
          case "record_cloud": cloudTargetConfig
          default: genericTargetConfig(scenario)
          }
        }

        // Notes field
        VStack(alignment: .leading, spacing: 4) {
          Text("Notes (optional)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          TextField("Description or reference", text: $notes)
            .textFieldStyle(.roundedBorder)
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 0 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button("Schedule") { step = 2 }
            .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
            .disabled(currentStream.isEmpty || computedTarget.isEmpty)
        }
      }
    }
  }

  private func scenarioChip(_ scenario: PushScenario) -> some View {
    HStack(spacing: 6) {
      Image(systemName: scenario.icon).font(.caption).foregroundStyle(Color.tnAccent)
      Text(scenario.title).font(.caption.weight(.medium))
    }
    .padding(.horizontal, 10).padding(.vertical, 4)
    .background(Color.tnAccent.opacity(0.1)).clipShape(Capsule())
  }

  private func platformTargetConfig(_ scenario: PushScenario) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if scenario.targetPrefix != nil {
        Text("Stream Key")
          .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        if let prefix = scenario.targetPrefix {
          Text(prefix)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1).truncationMode(.middle)
        }
        TextField("Paste your stream key here", text: $streamKey)
          .textFieldStyle(.roundedBorder)
      } else {
        Text("Ingest URL")
          .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        TextField("rtmp://ingest.example.com/live/stream_key", text: $targetURL)
          .textFieldStyle(.roundedBorder)
        Text("Full RTMP/RTMPS ingest URL including stream key")
          .font(.system(size: 9)).foregroundStyle(.tertiary)
      }
    }
  }

  private var fileTargetConfig: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("File Path")
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
      TextField("/recordings/$stream_$datetime.ts", text: $targetURL)
        .textFieldStyle(.roundedBorder)
      templateVariableHints(templateVariables)
    }
  }

  private var dvrTargetConfig: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Segment File Path")
          .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        TextField("/recordings/$basename/$yday/$hour/$minute_$segmentCounter.ts", text: $targetURL)
          .textFieldStyle(.roundedBorder)
        templateVariableHints(templateVariables + dvrTemplateVariables)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Playlist Filename")
          .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        TextField("playlist.m3u8", text: $dvrPlaylist)
          .textFieldStyle(.roundedBorder)
      }

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Split (s)").font(.system(size: 10)).foregroundStyle(.secondary)
          TextField("24", text: $dvrSplit).textFieldStyle(.roundedBorder).frame(width: 50)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("Max Entries").font(.system(size: 10)).foregroundStyle(.secondary)
          TextField("3600", text: $dvrMaxEntries).textFieldStyle(.roundedBorder).frame(width: 50)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("Max Age (s)").font(.system(size: 10)).foregroundStyle(.secondary)
          TextField("0", text: $dvrTargetAge).textFieldStyle(.roundedBorder).frame(width: 50)
        }
      }
    }
  }

  private var cloudTargetConfig: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Cloud Target")
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
      HStack(spacing: 4) {
        Picker("Protocol", selection: $targetURL) {
          ForEach(appState.writerProtocols, id: \.self) { proto in
            Text(proto).tag(proto)
          }
        }.labelsHidden().frame(width: 80)
        TextField("bucket/path/$stream_$datetime", text: $streamKey)
          .textFieldStyle(.roundedBorder)
      }
    }
  }

  private func genericTargetConfig(_ scenario: PushScenario) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Target URL")
        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
      // Protocol selector if multiple options
      if let options = scenario.prefixOptions, options.count > 1 {
        HStack(spacing: 4) {
          Picker("Protocol", selection: $selectedPrefix) {
            ForEach(options, id: \.self) { opt in
              Text(opt).tag(opt)
            }
          }.labelsHidden().frame(width: 90)
          TextField("host:port/path", text: $targetURL)
            .textFieldStyle(.roundedBorder)
        }
      } else {
        TextField(scenario.targetPrefix ?? "protocol://host:port/path", text: $targetURL)
          .textFieldStyle(.roundedBorder)
      }
    }
  }

  private func templateVariableHints(_ vars: [String]) -> some View {
    let rows = stride(from: 0, to: vars.count, by: 4).map { Array(vars[$0..<min($0+4, vars.count)]) }
    return VStack(alignment: .leading, spacing: 2) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: 4) {
          ForEach(row, id: \.self) { v in
            Button {
              targetURL += v
            } label: {
              Text(v)
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.tnAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain).pointerOnHover()
          }
        }
      }
    }
  }

  // MARK: - Step 3: Schedule

  private var scheduleStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("When should this push run?")
        .font(.subheadline.weight(.medium))

      Picker("Mode", selection: $scheduleMode) {
        ForEach(PushScheduleMode.allCases, id: \.self) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.menu)

      switch scheduleMode {
      case .now:
        Text("Push starts immediately and runs once.")
          .font(.caption).foregroundStyle(.secondary)

      case .always:
        Text("Push runs whenever the stream is active. Retries on failure.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Enabled", isOn: $isEnabled)
          .font(.subheadline)

      case .scheduled:
        VStack(alignment: .leading, spacing: 8) {
          Text("Push starts and stops at specific times.")
            .font(.caption).foregroundStyle(.secondary)
          Toggle("Enabled", isOn: $isEnabled)
            .font(.subheadline)
          DatePicker("Start", selection: $scheduleStart)
            .font(.caption)
          DatePicker("End", selection: $scheduleEnd)
            .font(.caption)
        }

      case .conditional:
        VStack(alignment: .leading, spacing: 8) {
          Text("Push starts/stops based on server variable conditions.")
            .font(.caption).foregroundStyle(.secondary)
          Toggle("Enabled", isOn: $isEnabled)
            .font(.subheadline)

          GroupBox("Start when") {
            HStack(spacing: 4) {
              TextField("$variable", text: $startRuleVar)
                .textFieldStyle(.roundedBorder).frame(width: 80)
              Picker("", selection: $startRuleOp) {
                ForEach(conditionOps, id: \.self) { Text($0).tag($0) }
              }.labelsHidden().frame(width: 55)
              TextField("value", text: $startRuleVal)
                .textFieldStyle(.roundedBorder)
            }
          }
          GroupBox("Stop when") {
            HStack(spacing: 4) {
              TextField("$variable", text: $endRuleVar)
                .textFieldStyle(.roundedBorder).frame(width: 80)
              Picker("", selection: $endRuleOp) {
                ForEach(conditionOps, id: \.self) { Text($0).tag($0) }
              }.labelsHidden().frame(width: 55)
              TextField("value", text: $endRuleVal)
                .textFieldStyle(.roundedBorder)
            }
          }
        }
      }

      if let error = errorMessage {
        Text(error).font(.caption).foregroundStyle(Color.tnRed)
      }

      HStack {
        Button("Back") { step = 1 }
          .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        Spacer()
        Button("Review") { step = 3 }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
      }
    }
  }

  // MARK: - Step 4: Review

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let scenario = selectedScenario {
        GroupBox {
          VStack(alignment: .leading, spacing: 8) {
            reviewRow("Type", value: scenario.title)
            reviewRow("Stream", value: currentStream)
            reviewRow("Target", value: computedTarget)
            reviewRow("Schedule", value: scheduleMode.rawValue)
            if scheduleMode == .scheduled {
              reviewRow("Start", value: scheduleStart.formatted())
              reviewRow("End", value: scheduleEnd.formatted())
            }
            if scheduleMode == .conditional && !startRuleVar.isEmpty {
              reviewRow("Start rule", value: "\(startRuleVar) \(startRuleOp) \(startRuleVal)")
            }
            if !notes.isEmpty {
              reviewRow("Notes", value: notes)
            }
          }
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 2 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button {
            submitPush()
          } label: {
            if isSubmitting {
              HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(scheduleMode == .now ? "Starting..." : "Creating...")
              }
            } else {
              Text(scheduleMode == .now ? "Start Push" : "Create Auto-Push")
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
          .disabled(isSubmitting)
        }
      }
    }
  }

  private func reviewRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled).lineLimit(3)
    }
  }

  // MARK: - Computed Values

  private var currentStream: String {
    useStreamPicker ? selectedStream : streamText.trimmingCharacters(in: .whitespaces)
  }

  private var computedTarget: String {
    guard let scenario = selectedScenario else { return "" }
    let trimmedURL = targetURL.trimmingCharacters(in: .whitespaces)
    let trimmedKey = streamKey.trimmingCharacters(in: .whitespaces)

    if scenario.isPlatform {
      if let prefix = scenario.targetPrefix {
        return prefix + trimmedKey
      }
      // Custom platform: full URL entered in targetURL field
      return trimmedURL.isEmpty ? trimmedKey : trimmedURL
    }
    if scenario.id == "record_dvr" {
      var target = trimmedURL
      if !target.isEmpty {
        let pl = dvrPlaylist.trimmingCharacters(in: .whitespaces)
        let sp = dvrSplit.trimmingCharacters(in: .whitespaces)
        let me = dvrMaxEntries.trimmingCharacters(in: .whitespaces)
        let ta = dvrTargetAge.trimmingCharacters(in: .whitespaces)
        target += "?m3u8=\(pl)&split=\(sp)&maxEntries=\(me)&targetAge=\(ta)&append=1&noendlist=1"
      }
      return target
    }
    if scenario.id == "record_cloud" {
      return trimmedURL + trimmedKey
    }
    // For scenarios with prefix selector
    if let options = scenario.prefixOptions, options.count > 1 {
      return selectedPrefix + trimmedURL
    }
    return trimmedURL
  }

  // MARK: - Submit

  private func submitPush() {
    isSubmitting = true
    errorMessage = nil
    let stream = currentStream
    let target = computedTarget
    let deactivationMarker = "\u{1F4A4}deactivated\u{1F4A4}_"

    switch scheduleMode {
    case .now:
      APIClient.shared.startPush(streamName: stream, targetURL: target) { result in
        DispatchQueue.main.async {
          isSubmitting = false
          switch result {
          case .success:
            appState.onDataChanged?()
            dismiss()
          case .failure(let error):
            errorMessage = error.localizedDescription
          }
        }
      }

    case .always, .scheduled, .conditional:
      var config: [String: Any] = [
        "stream": isEnabled ? stream : (deactivationMarker + stream),
        "target": target,
      ]
      if !notes.isEmpty { config["x-LSP-notes"] = notes }

      if scheduleMode == .scheduled {
        config["scheduletime"] = Int(scheduleStart.timeIntervalSince1970)
        config["completetime"] = Int(scheduleEnd.timeIntervalSince1970)
      }

      if scheduleMode == .conditional {
        if !startRuleVar.isEmpty {
          config["start_rule"] = [startRuleVar, startRuleOp, startRuleVal]
        }
        if !endRuleVar.isEmpty {
          config["end_rule"] = [endRuleVar, endRuleOp, endRuleVal]
        }
      }

      APIClient.shared.addAutoPush(config) { result in
        DispatchQueue.main.async {
          isSubmitting = false
          switch result {
          case .success:
            appState.onDataChanged?()
            dismiss()
          case .failure(let error):
            errorMessage = error.localizedDescription
          }
        }
      }
    }
  }
}

// MARK: - Stream Scenario Definitions

enum StreamScenarioGroup: String, CaseIterable {
  case receive = "Receive"
  case connect = "Connect"
  case serve = "Serve"
}

struct StreamScenario: Identifiable {
  let id: String
  let group: StreamScenarioGroup
  let title: String
  let icon: String
  let description: String
  let sourcePrefix: String

  static let all: [StreamScenario] = [
    // Receive
    StreamScenario(id: "push", group: .receive, title: "Push Ingest",
                   icon: "arrow.down.circle", description: "Receive a pushed stream (RTMP, SRT, WebRTC, etc.)",
                   sourcePrefix: "push://"),
    // Connect
    StreamScenario(id: "rtsp", group: .connect, title: "RTSP Camera",
                   icon: "video", description: "Pull from an RTSP source",
                   sourcePrefix: "rtsp://"),
    StreamScenario(id: "srt", group: .connect, title: "SRT",
                   icon: "antenna.radiowaves.left.and.right", description: "Connect via SRT protocol",
                   sourcePrefix: "srt://"),
    StreamScenario(id: "pull", group: .connect, title: "Pull from URL",
                   icon: "arrow.down.doc", description: "Pull from any HTTP/RTMP/HLS URL",
                   sourcePrefix: ""),
    // Serve
    StreamScenario(id: "file", group: .serve, title: "Single File",
                   icon: "doc.fill", description: "Serve a local media file",
                   sourcePrefix: "/"),
    StreamScenario(id: "folder", group: .serve, title: "Folder (Playlist)",
                   icon: "folder.fill", description: "Serve all files in a folder as a playlist",
                   sourcePrefix: "/"),
  ]

  static func grouped() -> [(group: StreamScenarioGroup, scenarios: [StreamScenario])] {
    StreamScenarioGroup.allCases.map { group in
      (group: group, scenarios: all.filter { $0.group == group })
    }
  }
}

// MARK: - Stream Wizard View

struct StreamWizardView: View {
  @Bindable var appState: AppState
  var dismiss: () -> Void

  @State private var step = 0
  @State private var selectedScenario: StreamScenario?
  @State private var streamName = ""
  @State private var sourceURL = ""
  @State private var alwaysOn = false
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var processes: [[String: Any]] = []
  @State private var showProcessPicker = false

  private let stepLabels = ["Type", "Configure", "Processes", "Review"]

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "New Stream")
      Divider()

      // Step indicator — sliding window of 3 visible out of 4
      HStack(spacing: 0) {
        let windowStart = max(0, min(step - 1, stepLabels.count - 3))
        let visible = Array(windowStart..<min(windowStart + 3, stepLabels.count))
        ForEach(Array(visible.enumerated()), id: \.offset) { idx, i in
          HStack(spacing: 4) {
            Circle()
              .fill(i <= step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(width: 8, height: 8)
            Text(stepLabels[i])
              .font(.system(size: 10, weight: i == step ? .semibold : .regular))
              .foregroundStyle(i == step ? .primary : .secondary)
          }
          if idx < visible.count - 1 {
            Rectangle()
              .fill(i < step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(height: 1).frame(maxWidth: .infinity).padding(.horizontal, 2)
          }
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)
      .animation(.easeInOut(duration: 0.2), value: step)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch step {
          case 0: scenarioStep
          case 1: configureStep
          case 2: processesStep
          case 3: reviewStep
          default: EmptyView()
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var scenarioStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(StreamScenario.grouped(), id: \.group) { group in
        Text(group.group.rawValue)
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(group.scenarios) { scenario in
          Button {
            selectedScenario = scenario
            sourceURL = scenario.id == "push" ? "push://" : scenario.sourcePrefix
            if scenario.id == "rtsp" || scenario.id == "srt" { alwaysOn = true }
            step = 1
          } label: {
            HStack(spacing: 10) {
              Image(systemName: scenario.icon)
                .font(.body).foregroundStyle(Color.tnAccent).frame(width: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title).font(.subheadline.weight(.medium))
                Text(scenario.description).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
          }
          .buttonStyle(.plain).hoverHighlight()
        }
      }
    }
  }

  private var configureStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let scenario = selectedScenario {
        HStack(spacing: 6) {
          Image(systemName: scenario.icon).font(.caption).foregroundStyle(Color.tnAccent)
          Text(scenario.title).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.tnAccent.opacity(0.1)).clipShape(Capsule())

        VStack(alignment: .leading, spacing: 4) {
          Text("Stream Name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
          TextField("e.g. camera1, livestream", text: $streamName)
            .textFieldStyle(.roundedBorder)
        }

        if scenario.id == "push" {
          pushIngestConfig
        } else {
          VStack(alignment: .leading, spacing: 4) {
            Text("Source").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(sourcePlaceholder(scenario), text: $sourceURL)
              .textFieldStyle(.roundedBorder)
          }
        }

        Toggle("Always On", isOn: $alwaysOn).font(.subheadline)

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 0 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button("Next") { step = 2 }
            .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
            .disabled(streamName.trimmingCharacters(in: .whitespaces).isEmpty
                      || sourceURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }

  private var pushIngestConfig: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Source").font(.caption.weight(.medium)).foregroundStyle(.secondary)
      Text("push://")
        .font(.system(.body, design: .monospaced)).foregroundStyle(Color.tnAccent)
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tnAccent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))

      if !appState.configuredProtocols.isEmpty {
        Text("Ingest URLs (after creation)")
          .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        let port = getHTTPPort()
        VStack(alignment: .leading, spacing: 4) {
          ForEach(ingestHints(port: port), id: \.protocol) { hint in
            HStack(spacing: 4) {
              Text(hint.protocol)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.tnAccent)
                .frame(width: 50, alignment: .leading)
              Text(hint.url)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            }
          }
        }
      }
    }
  }

  private func getHTTPPort() -> Int {
    for proto in appState.configuredProtocols {
      if let connector = proto["connector"] as? String,
         connector.uppercased().contains("HTTP"),
         let port = proto["port"] as? Int { return port }
    }
    return 8080
  }

  private struct IngestHint { let `protocol`: String; let url: String }

  private func ingestHints(port: Int) -> [IngestHint] {
    let name = streamName.trimmingCharacters(in: .whitespaces).isEmpty ? "STREAMNAME" : streamName.trimmingCharacters(in: .whitespaces)
    var hints: [IngestHint] = []
    let connectors = Set(appState.configuredProtocols.compactMap { ($0["connector"] as? String)?.uppercased() })
    if connectors.contains(where: { $0.contains("RTMP") }) {
      let rtmpPort = appState.configuredProtocols.first(where: {
        ($0["connector"] as? String)?.uppercased().contains("RTMP") == true
      })?["port"] as? Int ?? 1935
      hints.append(IngestHint(protocol: "RTMP", url: "rtmp://HOST:\(rtmpPort)/live/\(name)"))
    }
    if connectors.contains(where: { $0.contains("SRT") }) {
      let srtPort = appState.configuredProtocols.first(where: {
        ($0["connector"] as? String)?.uppercased().contains("SRT") == true
      })?["port"] as? Int ?? 9999
      hints.append(IngestHint(protocol: "SRT", url: "srt://HOST:\(srtPort)?streamid=\(name)"))
    }
    if connectors.contains(where: { $0.contains("WEBRTC") || $0.contains("HTTP") }) {
      hints.append(IngestHint(protocol: "WHIP", url: "http://HOST:\(port)/webrtc/\(name)"))
    }
    return hints
  }

  private func sourcePlaceholder(_ scenario: StreamScenario) -> String {
    switch scenario.id {
    case "rtsp": return "rtsp://192.168.1.100:554/stream"
    case "srt": return "srt://host:port"
    case "pull": return "https://example.com/live/stream.m3u8"
    case "file": return "/path/to/video.mp4"
    case "folder": return "/path/to/media/folder/"
    default: return scenario.sourcePrefix + "..."
    }
  }

  // MARK: - Process Templates

  private struct ProcessTemplate: Identifiable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let processes: [[String: Any]]
  }

  private var availableProcessTypes: [String] {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any] else { return [] }
    return procs.keys.sorted()
  }

  private func processHRN(_ procId: String) -> String {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any],
          let info = procs[procId] as? [String: Any]
    else { return procId }
    return info["hrn"] as? String ?? info["name"] as? String ?? procId
  }

  private func processDesc(_ procId: String) -> String {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any],
          let info = procs[procId] as? [String: Any]
    else { return "" }
    return info["desc"] as? String ?? ""
  }

  private var processTemplates: [ProcessTemplate] {
    let avail = Set(availableProcessTypes)
    var templates: [ProcessTemplate] = []

    let useAV = avail.contains("AV")
    let useFFMPEG = avail.contains("FFMPEG")
    let encoder = useAV ? "AV" : (useFFMPEG ? "FFMPEG" : nil)

    if let enc = encoder {
      templates.append(ProcessTemplate(
        id: "1080p", title: "1080p H264", icon: "film",
        description: "Transcode to 1920x1080",
        processes: [["process": enc, "x-LSP-name": "1080p H264", "codec": "H264",
                     "resolution": "1920x1080", "preset": "faster"]]))
      templates.append(ProcessTemplate(
        id: "720p", title: "720p H264", icon: "film",
        description: "Transcode to 1280x720",
        processes: [["process": enc, "x-LSP-name": "720p H264", "codec": "H264",
                     "resolution": "1280x720", "preset": "faster"]]))
      templates.append(ProcessTemplate(
        id: "480p", title: "480p H264", icon: "film",
        description: "Transcode to 854x480",
        processes: [["process": enc, "x-LSP-name": "480p H264", "codec": "H264",
                     "resolution": "854x480", "preset": "fast"]]))
      templates.append(ProcessTemplate(
        id: "abr", title: "ABR Ladder", icon: "rectangle.3.group",
        description: "1080 + 720 + 480p",
        processes: [
          ["process": enc, "x-LSP-name": "1080p H264", "codec": "H264",
           "resolution": "1920x1080", "preset": "faster"],
          ["process": enc, "x-LSP-name": "720p H264", "codec": "H264",
           "resolution": "1280x720", "preset": "faster"],
          ["process": enc, "x-LSP-name": "480p H264", "codec": "H264",
           "resolution": "854x480", "preset": "fast"],
        ]))
      templates.append(ProcessTemplate(
        id: "mjpeg", title: "MJPEG Snapshots", icon: "photo",
        description: "JPEG snapshots from video",
        processes: [["process": useAV ? "AV" : enc, "x-LSP-name": "MJPEG Snapshots",
                     "codec": "JPEG", "quality": 15, "gopsize": 30] as [String: Any]]))
      templates.append(ProcessTemplate(
        id: "opus", title: "Audio to Opus", icon: "speaker.wave.2",
        description: "Transcode audio to Opus",
        processes: [["process": enc, "x-LSP-name": "Audio Opus", "codec": "opus",
                     "bitrate": 128000] as [String: Any]]))
      templates.append(ProcessTemplate(
        id: "aac", title: "Audio to AAC", icon: "speaker.wave.2",
        description: "Transcode audio to AAC",
        processes: [["process": enc, "x-LSP-name": "Audio AAC", "codec": "AAC",
                     "bitrate": 128000] as [String: Any]]))
    }

    return templates
  }

  // MARK: - Processes Step

  private var processesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add processing steps (optional)")
        .font(.subheadline.weight(.medium))
      Text("Transcode video, generate thumbnails, or create ABR variants.")
        .font(.caption).foregroundStyle(.secondary)

      // Current process list
      if !processes.isEmpty {
        VStack(spacing: 6) {
          ForEach(Array(processes.enumerated()), id: \.offset) { index, proc in
            HStack(spacing: 8) {
              Image(systemName: "bolt.fill")
                .font(.system(size: 11)).foregroundStyle(Color.tnPurple)
              VStack(alignment: .leading, spacing: 1) {
                Text(proc["x-LSP-name"] as? String ?? proc["process"] as? String ?? "Process")
                  .font(.caption.weight(.medium))
                let detail = [proc["codec"] as? String, proc["resolution"] as? String]
                  .compactMap { $0 }.joined(separator: " ")
                if !detail.isEmpty {
                  Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Button {
                processes.remove(at: index)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.caption).foregroundStyle(.secondary)
                  .frame(width: 20, height: 20).contentShape(Rectangle())
              }
              .buttonStyle(.plain).pointerOnHover()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.tnPurple.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
      }

      // Templates
      if !processTemplates.isEmpty && !showProcessPicker {
        Text("Quick Add").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
          ForEach(processTemplates) { template in
            Button {
              processes.append(contentsOf: template.processes)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: template.icon)
                  .font(.system(size: 10)).foregroundStyle(Color.tnAccent).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                  Text(template.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                  Text(template.description)
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
              .padding(.horizontal, 8).padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.tnAccent.opacity(0.06))
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerOnHover()
          }
        }
      }

      // Available process types (advanced)
      if !availableProcessTypes.isEmpty {
        Button {
          showProcessPicker.toggle()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: showProcessPicker ? "chevron.down" : "chevron.right")
              .font(.system(size: 9))
            Text("Available Encoders")
              .font(.caption.weight(.medium))
          }
          .foregroundStyle(Color.tnAccent).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerOnHover()

        if showProcessPicker {
          VStack(spacing: 4) {
            ForEach(availableProcessTypes, id: \.self) { procId in
              Button {
                processes.append(["process": procId])
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: "bolt").font(.caption).foregroundStyle(Color.tnAccent).frame(width: 20)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(processHRN(procId)).font(.caption.weight(.medium))
                    Text(processDesc(procId)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                  }
                  Spacer()
                  Image(systemName: "plus.circle").font(.caption).foregroundStyle(Color.tnAccent)
                }
                .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
              }
              .buttonStyle(.plain).hoverHighlight()
            }
          }
        }
      }

      HStack {
        Button("Back") { step = 1 }
          .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        Spacer()
        if processes.isEmpty {
          Button("Skip") { step = 3 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        }
        Button("Review") { step = 3 }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
      }
    }
  }

  // MARK: - Review Step

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let scenario = selectedScenario {
        GroupBox {
          VStack(alignment: .leading, spacing: 8) {
            reviewRow("Type", value: scenario.title)
            reviewRow("Name", value: streamName.trimmingCharacters(in: .whitespaces))
            reviewRow("Source", value: sourceURL.trimmingCharacters(in: .whitespaces))
            if alwaysOn {
              HStack {
                Text("Always On").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tnGreen)
              }
            }
            if !processes.isEmpty {
              Divider()
              Text("Processes").font(.caption).foregroundStyle(.secondary)
              ForEach(Array(processes.enumerated()), id: \.offset) { _, proc in
                let procName = proc["x-LSP-name"] as? String
                  ?? proc["process"] as? String ?? "Process"
                let codec = proc["codec"] as? String
                let res = proc["resolution"] as? String
                let detail = [codec, res].compactMap { $0 }.joined(separator: " ")
                HStack(spacing: 4) {
                  Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Color.tnPurple)
                  Text(procName).font(.caption.weight(.medium))
                  if !detail.isEmpty {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 2 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button {
            createStream()
          } label: {
            if isSubmitting {
              HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Creating...") }
            } else {
              Text("Create Stream")
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
          .disabled(isSubmitting)
        }
      }
    }
  }

  private func reviewRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
    }
  }

  private func createStream() {
    isSubmitting = true
    errorMessage = nil
    var config: [String: Any] = ["source": sourceURL.trimmingCharacters(in: .whitespaces)]
    if alwaysOn { config["always_on"] = true }
    if !processes.isEmpty { config["processes"] = processes }
    let apiCall: [String: Any] = ["addstream": [streamName.trimmingCharacters(in: .whitespaces): config]]
    APIClient.shared.makeAPICall(apiCall) { (result: Result<[String: Any], APIError>) in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          appState.onDataChanged?()
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Stream Edit Wizard

struct StreamEditWizardView: View {
  @Bindable var appState: AppState
  let originalName: String
  var dismiss: () -> Void

  @State private var step = 0
  @State private var streamName = ""
  @State private var sourceURL = ""
  @State private var alwaysOn = false
  @State private var processes: [[String: Any]] = []
  @State private var stopSessions = false
  @State private var showProcessPicker = false
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  private let stepLabels = ["Configure", "Processes", "Review"]

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Edit Stream")
      Divider()

      // Step indicator — sliding window of 3
      HStack(spacing: 0) {
        ForEach(Array(stepLabels.enumerated()), id: \.offset) { i, label in
          HStack(spacing: 4) {
            Circle()
              .fill(i <= step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(width: 8, height: 8)
            Text(label)
              .font(.system(size: 10, weight: i == step ? .semibold : .regular))
              .foregroundStyle(i == step ? .primary : .secondary)
          }
          if i < stepLabels.count - 1 {
            Rectangle()
              .fill(i < step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(height: 1).frame(maxWidth: .infinity).padding(.horizontal, 2)
          }
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch step {
          case 0: configureStep
          case 1: processesStep
          case 2: reviewStep
          default: EmptyView()
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { prefillFromExisting() }
  }

  // MARK: - Pre-fill

  private func prefillFromExisting() {
    streamName = originalName
    if let config = appState.allStreams[originalName] as? [String: Any] {
      sourceURL = config["source"] as? String ?? ""
      alwaysOn = config["always_on"] as? Bool ?? false
      processes = config["processes"] as? [[String: Any]] ?? []
    }
  }

  // MARK: - Configure Step

  private var configureStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Stream Name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        TextField("stream-name", text: $streamName)
          .textFieldStyle(.roundedBorder)
        if streamName != originalName && !streamName.trimmingCharacters(in: .whitespaces).isEmpty {
          Text("Renaming from '\(originalName)' to '\(streamName.trimmingCharacters(in: .whitespaces))'")
            .font(.system(size: 10)).foregroundStyle(Color.tnOrange)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Source").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        TextField("push:// or rtmp://...", text: $sourceURL)
          .textFieldStyle(.roundedBorder)
      }

      Toggle("Always On", isOn: $alwaysOn).font(.subheadline)

      if let error = errorMessage {
        Text(error).font(.caption).foregroundStyle(Color.tnRed)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        Spacer()
        Button("Next") { step = 1 }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
          .disabled(streamName.trimmingCharacters(in: .whitespaces).isEmpty
                    || sourceURL.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }

  // MARK: - Processes Step

  private struct ProcessTemplate: Identifiable {
    let id: String; let title: String; let icon: String
    let description: String; let processes: [[String: Any]]
  }

  private var availableProcessTypes: [String] {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any] else { return [] }
    return procs.keys.sorted()
  }

  private func processHRN(_ procId: String) -> String {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any],
          let info = procs[procId] as? [String: Any]
    else { return procId }
    return info["hrn"] as? String ?? info["name"] as? String ?? procId
  }

  private func processDesc(_ procId: String) -> String {
    guard let procs = appState.serverCapabilities["processes"] as? [String: Any],
          let info = procs[procId] as? [String: Any]
    else { return "" }
    return info["desc"] as? String ?? ""
  }

  private var processTemplates: [ProcessTemplate] {
    let avail = Set(availableProcessTypes)
    let useAV = avail.contains("AV")
    let useFFMPEG = avail.contains("FFMPEG")
    guard let enc = useAV ? "AV" : (useFFMPEG ? "FFMPEG" : nil) else { return [] }
    return [
      ProcessTemplate(id: "1080p", title: "1080p H264", icon: "film",
        description: "Transcode to 1920x1080",
        processes: [["process": enc, "x-LSP-name": "1080p H264", "codec": "H264",
                     "resolution": "1920x1080", "preset": "faster"]]),
      ProcessTemplate(id: "720p", title: "720p H264", icon: "film",
        description: "Transcode to 1280x720",
        processes: [["process": enc, "x-LSP-name": "720p H264", "codec": "H264",
                     "resolution": "1280x720", "preset": "faster"]]),
      ProcessTemplate(id: "480p", title: "480p H264", icon: "film",
        description: "Transcode to 854x480",
        processes: [["process": enc, "x-LSP-name": "480p H264", "codec": "H264",
                     "resolution": "854x480", "preset": "fast"]]),
      ProcessTemplate(id: "abr", title: "ABR Ladder", icon: "rectangle.3.group",
        description: "1080 + 720 + 480p",
        processes: [
          ["process": enc, "x-LSP-name": "1080p H264", "codec": "H264",
           "resolution": "1920x1080", "preset": "faster"],
          ["process": enc, "x-LSP-name": "720p H264", "codec": "H264",
           "resolution": "1280x720", "preset": "faster"],
          ["process": enc, "x-LSP-name": "480p H264", "codec": "H264",
           "resolution": "854x480", "preset": "fast"],
        ]),
      ProcessTemplate(id: "mjpeg", title: "MJPEG Snapshots", icon: "photo",
        description: "JPEG snapshots from video",
        processes: [["process": useAV ? "AV" : enc, "x-LSP-name": "MJPEG Snapshots",
                     "codec": "JPEG", "quality": 15, "gopsize": 30] as [String: Any]]),
      ProcessTemplate(id: "opus", title: "Audio to Opus", icon: "speaker.wave.2",
        description: "Transcode audio to Opus",
        processes: [["process": enc, "x-LSP-name": "Audio Opus", "codec": "opus",
                     "bitrate": 128000] as [String: Any]]),
      ProcessTemplate(id: "aac", title: "Audio to AAC", icon: "speaker.wave.2",
        description: "Transcode audio to AAC",
        processes: [["process": enc, "x-LSP-name": "Audio AAC", "codec": "AAC",
                     "bitrate": 128000] as [String: Any]]),
    ]
  }

  private var processesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Stream Processes")
        .font(.subheadline.weight(.medium))
      Text("Add or modify transcoding, thumbnails, or ABR variants.")
        .font(.caption).foregroundStyle(.secondary)

      if !processes.isEmpty {
        VStack(spacing: 6) {
          ForEach(Array(processes.enumerated()), id: \.offset) { index, proc in
            HStack(spacing: 8) {
              Image(systemName: "bolt.fill")
                .font(.system(size: 11)).foregroundStyle(Color.tnPurple)
              VStack(alignment: .leading, spacing: 1) {
                Text(proc["x-LSP-name"] as? String ?? proc["process"] as? String ?? "Process")
                  .font(.caption.weight(.medium))
                let detail = [proc["codec"] as? String, proc["resolution"] as? String]
                  .compactMap { $0 }.joined(separator: " ")
                if !detail.isEmpty {
                  Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Button {
                processes.remove(at: index)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.caption).foregroundStyle(.secondary)
                  .frame(width: 20, height: 20).contentShape(Rectangle())
              }
              .buttonStyle(.plain).pointerOnHover()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.tnPurple.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
      }

      if !processTemplates.isEmpty && !showProcessPicker {
        Text("Quick Add").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
          ForEach(processTemplates) { template in
            Button {
              processes.append(contentsOf: template.processes)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: template.icon)
                  .font(.system(size: 10)).foregroundStyle(Color.tnAccent).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                  Text(template.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                  Text(template.description).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                }
              }
              .padding(.horizontal, 8).padding(.vertical, 6)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.tnAccent.opacity(0.06))
              .clipShape(RoundedRectangle(cornerRadius: 6))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerOnHover()
          }
        }
      }

      if !availableProcessTypes.isEmpty {
        Button {
          showProcessPicker.toggle()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: showProcessPicker ? "chevron.down" : "chevron.right")
              .font(.system(size: 9))
            Text("Available Encoders").font(.caption.weight(.medium))
          }
          .foregroundStyle(Color.tnAccent).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerOnHover()

        if showProcessPicker {
          VStack(spacing: 4) {
            ForEach(availableProcessTypes, id: \.self) { procId in
              Button {
                processes.append(["process": procId])
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: "bolt").font(.caption).foregroundStyle(Color.tnAccent).frame(width: 20)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(processHRN(procId)).font(.caption.weight(.medium))
                    Text(processDesc(procId)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                  }
                  Spacer()
                  Image(systemName: "plus.circle").font(.caption).foregroundStyle(Color.tnAccent)
                }
                .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
              }
              .buttonStyle(.plain).hoverHighlight()
            }
          }
        }
      }

      HStack {
        Button("Back") { step = 0 }
          .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        Spacer()
        if processes.isEmpty {
          Button("Skip") { step = 2 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        }
        Button("Review") { step = 2 }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
      }
    }
  }

  // MARK: - Review Step

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          reviewRow("Name", value: streamName.trimmingCharacters(in: .whitespaces))
          if streamName.trimmingCharacters(in: .whitespaces) != originalName {
            HStack(spacing: 4) {
              Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10)).foregroundStyle(Color.tnOrange)
              Text("Will rename from '\(originalName)'")
                .font(.system(size: 10)).foregroundStyle(Color.tnOrange)
            }
          }
          reviewRow("Source", value: sourceURL.trimmingCharacters(in: .whitespaces))
          if alwaysOn {
            HStack {
              Text("Always On").font(.caption).foregroundStyle(.secondary)
              Spacer()
              Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tnGreen)
            }
          }
          if !processes.isEmpty {
            Divider()
            Text("Processes").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(processes.enumerated()), id: \.offset) { _, proc in
              let procName = proc["x-LSP-name"] as? String
                ?? proc["process"] as? String ?? "Process"
              let codec = proc["codec"] as? String
              let res = proc["resolution"] as? String
              let detail = [codec, res].compactMap { $0 }.joined(separator: " ")
              HStack(spacing: 4) {
                Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Color.tnPurple)
                Text(procName).font(.caption.weight(.medium))
                if !detail.isEmpty {
                  Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }

      Toggle("Stop active sessions on save", isOn: $stopSessions)
        .font(.caption)

      if let error = errorMessage {
        Text(error).font(.caption).foregroundStyle(Color.tnRed)
      }

      HStack {
        Button("Back") { step = 1 }
          .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
        Spacer()
        Button { saveStream() } label: {
          if isSubmitting {
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Saving...") }
          } else {
            Text("Save Changes")
          }
        }
        .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
        .disabled(isSubmitting)
      }
    }
  }

  private func reviewRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
    }
  }

  // MARK: - Save

  private func saveStream() {
    isSubmitting = true
    errorMessage = nil
    let name = streamName.trimmingCharacters(in: .whitespaces)
    var config: [String: Any] = ["source": sourceURL.trimmingCharacters(in: .whitespaces)]
    if alwaysOn { config["always_on"] = true }
    if !processes.isEmpty { config["processes"] = processes }

    StreamManager.shared.updateStream(
      name: name, config: config,
      originalName: name != originalName ? originalName : nil,
      stopSessions: stopSessions
    ) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          appState.onDataChanged?()
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Trigger Wizard Definitions

private struct TriggerEvent: Identifiable {
  let id: String  // Event name (e.g. "USER_NEW")
  let title: String
  let description: String
  let category: String
}

private let triggerEvents: [TriggerEvent] = [
  // Access Control
  TriggerEvent(id: "USER_NEW", title: "Authenticate Viewers", description: "Fired when a new viewer session starts", category: "Access Control"),
  TriggerEvent(id: "CONN_OPEN", title: "Gate Connections", description: "Fired when a new connection opens", category: "Access Control"),
  TriggerEvent(id: "CONN_PLAY", title: "Gate Playback", description: "Fired when playback is requested", category: "Access Control"),
  TriggerEvent(id: "STREAM_PUSH", title: "Gate Incoming Pushes", description: "Fired when a push is received", category: "Access Control"),
  TriggerEvent(id: "LIVE_BANDWIDTH", title: "Enforce Bandwidth", description: "Fired to check bandwidth limits", category: "Access Control"),
  // Stream Lifecycle
  TriggerEvent(id: "STREAM_ADD", title: "Approve New Streams", description: "Fired when a stream is created", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_CONFIG", title: "Approve Config Changes", description: "Fired when stream config changes", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_REMOVE", title: "Approve Stream Removal", description: "Fired when a stream is deleted", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_SOURCE", title: "Override Stream Source", description: "Fired to override a stream's source", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_LOAD", title: "Approve Stream Loading", description: "Fired when a stream is loaded", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_READY", title: "On Stream Ready", description: "Fired when a stream becomes ready", category: "Stream Lifecycle"),
  TriggerEvent(id: "STREAM_UNLOAD", title: "Prevent Stream Unloading", description: "Fired before a stream unloads", category: "Stream Lifecycle"),
  // Routing
  TriggerEvent(id: "PUSH_REWRITE", title: "Rewrite Push Names", description: "Rewrite stream names for incoming pushes", category: "Routing"),
  TriggerEvent(id: "RTMP_PUSH_REWRITE", title: "Rewrite RTMP URLs", description: "Rewrite RTMP push URLs", category: "Routing"),
  TriggerEvent(id: "PUSH_OUT_START", title: "Override Push Target", description: "Override outgoing push targets", category: "Routing"),
  TriggerEvent(id: "PLAY_REWRITE", title: "Redirect Playback", description: "Redirect playback requests", category: "Routing"),
  TriggerEvent(id: "DEFAULT_STREAM", title: "Fallback Stream", description: "Fallback for missing streams", category: "Routing"),
  // Monitoring
  TriggerEvent(id: "STREAM_BUFFER", title: "Buffer State Changes", description: "Fired on buffer state transitions", category: "Monitoring"),
  TriggerEvent(id: "STREAM_END", title: "Stream Ended", description: "Fired when a stream stops", category: "Monitoring"),
  TriggerEvent(id: "CONN_CLOSE", title: "Connection Closed", description: "Fired when a connection closes", category: "Monitoring"),
  TriggerEvent(id: "USER_END", title: "Session Ended", description: "Fired when a viewer session ends", category: "Monitoring"),
  TriggerEvent(id: "RECORDING_END", title: "Recording Finished", description: "Fired when a recording completes", category: "Monitoring"),
  TriggerEvent(id: "PUSH_END", title: "Push Stopped", description: "Fired when a push ends", category: "Monitoring"),
  TriggerEvent(id: "LIVE_TRACK_LIST", title: "Track List Updated", description: "Fired when track list changes", category: "Monitoring"),
  TriggerEvent(id: "INPUT_ABORT", title: "Input Error", description: "Fired on input errors", category: "Monitoring"),
  // System
  TriggerEvent(id: "SYSTEM_START", title: "Server Boot", description: "Fired when server starts", category: "System"),
  TriggerEvent(id: "SYSTEM_STOP", title: "Server Shutdown", description: "Fired when server stops", category: "System"),
  TriggerEvent(id: "OUTPUT_START", title: "Connector Started", description: "Fired when a protocol starts", category: "System"),
  TriggerEvent(id: "OUTPUT_STOP", title: "Connector Stopped", description: "Fired when a protocol stops", category: "System"),
]

private let triggerCategories = ["Access Control", "Stream Lifecycle", "Routing", "Monitoring", "System"]

// MARK: - Trigger Wizard View

struct TriggerWizardView: View {
  @Bindable var appState: AppState
  var dismiss: () -> Void

  @State private var step = 0
  @State private var selectedEvent: TriggerEvent?
  @State private var handlerURL = ""
  @State private var isBlocking = false
  @State private var streamsText = ""
  @State private var defaultResponse = "true"
  @State private var params = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "New Trigger")
      Divider()

      HStack(spacing: 0) {
        ForEach(0..<3) { i in
          HStack(spacing: 4) {
            Circle()
              .fill(i <= step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(width: 8, height: 8)
            Text(["Event", "Configure", "Review"][i])
              .font(.system(size: 10, weight: i == step ? .semibold : .regular))
              .foregroundStyle(i == step ? .primary : .secondary)
          }
          if i < 2 {
            Rectangle()
              .fill(i < step ? Color.tnAccent : Color.gray.opacity(0.3))
              .frame(height: 1).frame(maxWidth: .infinity).padding(.horizontal, 4)
          }
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch step {
          case 0: eventStep
          case 1: configStep
          case 2: reviewStep
          default: EmptyView()
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Step 1: Event

  private var eventStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(triggerCategories, id: \.self) { category in
        Text(category)
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(triggerEvents.filter { $0.category == category }) { event in
          Button {
            selectedEvent = event
            // Auto-set blocking based on capabilities
            if let caps = appState.serverCapabilities["triggers"] as? [String: Any],
               let eventCaps = caps[event.id] as? [String: Any],
               let response = eventCaps["response"] as? String {
              isBlocking = (response == "always")
            }
            step = 1
          } label: {
            HStack(spacing: 10) {
              Text(event.id)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tnAccent)
                .frame(width: 100, alignment: .leading)
              VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.subheadline.weight(.medium))
                Text(event.description).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
          }
          .buttonStyle(.plain).hoverHighlight()
        }
      }
    }
  }

  // MARK: - Step 2: Configure

  private var configStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let event = selectedEvent {
        HStack(spacing: 6) {
          Text(event.id).font(.system(size: 11, weight: .semibold, design: .monospaced))
          Text(event.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.tnAccent.opacity(0.1)).clipShape(Capsule())

        VStack(alignment: .leading, spacing: 4) {
          Text("Handler URL").font(.caption.weight(.medium)).foregroundStyle(.secondary)
          TextField("https://example.com/handler", text: $handlerURL)
            .textFieldStyle(.roundedBorder)
          Text("URL or local executable path")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
        }

        let responseType = triggerResponseType(event.id)
        Toggle("Blocking (sync)", isOn: $isBlocking)
          .font(.subheadline)
          .disabled(responseType == "always" || responseType == "ignored")
        if responseType == "always" {
          Text("This event requires blocking mode.")
            .font(.system(size: 10)).foregroundStyle(Color.tnOrange)
        } else if responseType == "ignored" {
          Text("Handler response is not used for this event.")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Apply to Streams").font(.caption.weight(.medium)).foregroundStyle(.secondary)
          TextField("Empty = all streams. name+, #tag supported", text: $streamsText)
            .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Default Response").font(.caption.weight(.medium)).foregroundStyle(.secondary)
          TextField("true", text: $defaultResponse)
            .textFieldStyle(.roundedBorder)
          Text("Fallback when handler fails or non-blocking")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Parameters (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
          TextField("Extra arguments", text: $params)
            .textFieldStyle(.roundedBorder)
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 0 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button("Review") { step = 2 }
            .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
            .disabled(handlerURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }

  private func triggerResponseType(_ eventName: String) -> String {
    if let caps = appState.serverCapabilities["triggers"] as? [String: Any],
       let eventCaps = caps[eventName] as? [String: Any],
       let response = eventCaps["response"] as? String {
      return response
    }
    return "when-blocking"
  }

  // MARK: - Step 3: Review

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let event = selectedEvent {
        GroupBox {
          VStack(alignment: .leading, spacing: 8) {
            reviewRow("Event", value: "\(event.id) (\(event.title))")
            reviewRow("Handler", value: handlerURL)
            reviewRow("Blocking", value: isBlocking ? "Yes" : "No")
            reviewRow("Streams", value: streamsText.isEmpty ? "All streams" : streamsText)
            reviewRow("Default", value: defaultResponse)
            if !params.isEmpty {
              reviewRow("Params", value: params)
            }
          }
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundStyle(Color.tnRed)
        }

        HStack {
          Button("Back") { step = 1 }
            .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
          Spacer()
          Button {
            saveTrigger()
          } label: {
            if isSubmitting {
              HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Saving...") }
            } else {
              Text("Create Trigger")
            }
          }
          .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
          .disabled(isSubmitting)
        }
      }
    }
  }

  private func reviewRow(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(3)
    }
  }

  // MARK: - Save

  private func saveTrigger() {
    guard let event = selectedEvent else { return }
    isSubmitting = true
    errorMessage = nil

    // Parse streams from comma-separated text
    let streamsList: [String] = streamsText.isEmpty
      ? []
      : streamsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

    let newHandler: [String: Any] = [
      "handler": handlerURL.trimmingCharacters(in: .whitespaces),
      "sync": isBlocking,
      "streams": streamsList,
      "default": defaultResponse.trimmingCharacters(in: .whitespaces),
      "params": params.trimmingCharacters(in: .whitespaces),
    ]

    // Read-modify-write triggers in config
    var updatedTriggers = appState.triggers
    var handlers = updatedTriggers[event.id] as? [[String: Any]] ?? []
    handlers.append(newHandler)
    updatedTriggers[event.id] = handlers

    APIClient.shared.saveTriggers(updatedTriggers) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          appState.onDataChanged?()
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Trigger Edit View

struct TriggerEditView: View {
  @Bindable var appState: AppState
  let eventName: String
  let handlerIndex: Int
  var dismiss: () -> Void

  @State private var handlerURL = ""
  @State private var isBlocking = false
  @State private var streamsText = ""
  @State private var defaultResponse = "true"
  @State private var params = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private var existingHandler: [String: Any]? {
    guard let handlers = appState.triggers[eventName] as? [[String: Any]],
          handlerIndex < handlers.count else { return nil }
    return handlers[handlerIndex]
  }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Edit Trigger")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 6) {
            Text(eventName).font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(eventTitle(eventName)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 10).padding(.vertical, 4)
          .background(Color.tnAccent.opacity(0.1)).clipShape(Capsule())

          VStack(alignment: .leading, spacing: 4) {
            Text("Handler URL").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("https://example.com/handler", text: $handlerURL)
              .textFieldStyle(.roundedBorder)
            Text("URL or local executable path")
              .font(.system(size: 10)).foregroundStyle(.tertiary)
          }

          let responseType = triggerResponseType(eventName)
          Toggle("Blocking (sync)", isOn: $isBlocking)
            .font(.subheadline)
            .disabled(responseType == "always" || responseType == "ignored")
          if responseType == "always" {
            Text("This event requires blocking mode.")
              .font(.system(size: 10)).foregroundStyle(Color.tnOrange)
          } else if responseType == "ignored" {
            Text("Handler response is not used for this event.")
              .font(.system(size: 10)).foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Apply to Streams").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("Empty = all streams. name+, #tag supported", text: $streamsText)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Default Response").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("true", text: $defaultResponse)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Parameters (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("Extra arguments", text: $params)
              .textFieldStyle(.roundedBorder)
          }

          if let error = errorMessage {
            Text(error).font(.caption).foregroundStyle(Color.tnRed)
          }

          HStack {
            Button("Cancel") { dismiss() }
              .buttonStyle(.bordered).controlSize(.small).pointerOnHover()
            Spacer()
            Button { saveChanges() } label: {
              if isSubmitting {
                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Saving...") }
              } else {
                Text("Save Changes")
              }
            }
            .buttonStyle(.borderedProminent).controlSize(.small).pointerOnHover()
            .disabled(handlerURL.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { prefill() }
  }

  private func prefill() {
    guard let handler = existingHandler else { return }
    handlerURL = handler["handler"] as? String ?? ""
    isBlocking = handler["sync"] as? Bool ?? false
    let streams = handler["streams"] as? [String] ?? []
    streamsText = streams.joined(separator: ", ")
    defaultResponse = handler["default"] as? String ?? "true"
    params = handler["params"] as? String ?? ""
  }

  private func eventTitle(_ name: String) -> String {
    for event in triggerEvents where event.id == name { return event.title }
    return name
  }

  private func triggerResponseType(_ name: String) -> String {
    if let caps = appState.serverCapabilities["triggers"] as? [String: Any],
       let eventCaps = caps[name] as? [String: Any],
       let response = eventCaps["response"] as? String {
      return response
    }
    return "when-blocking"
  }

  private func saveChanges() {
    isSubmitting = true
    errorMessage = nil

    let streamsList: [String] = streamsText.isEmpty
      ? []
      : streamsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

    let updatedHandler: [String: Any] = [
      "handler": handlerURL.trimmingCharacters(in: .whitespaces),
      "sync": isBlocking,
      "streams": streamsList,
      "default": defaultResponse.trimmingCharacters(in: .whitespaces),
      "params": params.trimmingCharacters(in: .whitespaces),
    ]

    var updatedTriggers = appState.triggers
    var handlers = updatedTriggers[eventName] as? [[String: Any]] ?? []
    if handlerIndex < handlers.count {
      handlers[handlerIndex] = updatedHandler
    }
    updatedTriggers[eventName] = handlers

    APIClient.shared.saveTriggers(updatedTriggers) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          appState.onDataChanged?()
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}
