//
//  FormViews.swift
//  MistTray
//

import SwiftUI

// MARK: - Create Stream Form

struct CreateStreamForm: View {
  @Bindable var appState: AppState
  var dismiss: () -> Void

  @State private var name = ""
  @State private var source = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        TextField("Stream name (e.g. camera1)", text: $name)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Stream Name")
      }

      Section {
        TextField("rtmp://source.example.com/live/stream", text: $source)
          .textFieldStyle(.roundedBorder)
        Text("Supported: RTMP, RTSP, HTTP, file paths, push://")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Source")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Create Stream") { createStream() }
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmed.isEmpty || source.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Create Stream")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func createStream() {
    isSubmitting = true
    errorMessage = nil
    StreamManager.shared.createStream(name: name.trimmed, source: source.trimmed) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Edit Stream Form

struct EditStreamForm: View {
  @Bindable var appState: AppState
  let streamName: String
  var dismiss: () -> Void

  @State private var source: String = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        Text(streamName)
          .font(.headline)
      } header: {
        Text("Stream")
      }

      Section {
        TextField("rtmp://source.example.com/live/stream", text: $source)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Source")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save") { saveChanges() }
          .keyboardShortcut(.defaultAction)
          .disabled(source.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Edit Stream")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      source = appState.streamSource(streamName)
      if source == "Unknown" { source = "" }
    }
  }

  private func saveChanges() {
    isSubmitting = true
    errorMessage = nil
    StreamManager.shared.updateStream(name: streamName, config: ["source": source.trimmed]) {
      result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Create Push Form

struct CreatePushForm: View {
  @Bindable var appState: AppState
  var dismiss: () -> Void

  @State private var selectedStream: String = ""
  @State private var targetURL = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        Picker("Stream", selection: $selectedStream) {
          if appState.sortedStreamNames.isEmpty {
            Text("No streams available").tag("")
          }
          ForEach(appState.sortedStreamNames, id: \.self) { name in
            Text(name).tag(name)
          }
        }
      } header: {
        Text("Source Stream")
      }

      Section {
        TextField("rtmp://live.example.com/live/streamkey", text: $targetURL)
          .textFieldStyle(.roundedBorder)
        Text("Destination URL (RTMP, RTSP, SRT, etc.)")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Target URL")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Start Push") { startPush() }
          .keyboardShortcut(.defaultAction)
          .disabled(selectedStream.isEmpty || targetURL.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Start Push")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      selectedStream = appState.sortedStreamNames.first ?? ""
    }
  }

  private func startPush() {
    isSubmitting = true
    errorMessage = nil
    PushManager.shared.startPush(streamName: selectedStream, targetURL: targetURL.trimmed) {
      result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Protocol Config Form

struct ProtocolConfigForm: View {
  let protocolName: String
  var dismiss: () -> Void

  @State private var port: String = ""
  @State private var interfaceAddr: String = "0.0.0.0"
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        TextField("Port number", text: $port)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Port")
      }

      Section {
        TextField("0.0.0.0 (all interfaces)", text: $interfaceAddr)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Interface")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Configure") { configure() }
          .keyboardShortcut(.defaultAction)
          .disabled(port.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("\(protocolName) Config")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      port = UtilityManager.shared.getDefaultPort(for: protocolName)
    }
  }

  private func configure() {
    guard Int(port.trimmed) != nil else {
      errorMessage = "Please enter a valid port number."
      return
    }
    // Protocol configuration requires MistServer web UI for now
    if let url = URL(string: "http://localhost:4242") {
      NSWorkspace.shared.open(url)
    }
    dismiss()
  }
}

// MARK: - Add Stream Tag Form

struct AddStreamTagForm: View {
  let streamName: String
  var dismiss: () -> Void

  @State private var tagName = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        TextField("e.g. live, recording, camera1", text: $tagName)
          .textFieldStyle(.roundedBorder)
        Text("Tags help organize streams by category, purpose, or equipment.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Tag Name")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Add Tag") { addTag() }
          .keyboardShortcut(.defaultAction)
          .disabled(tagName.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Add Tag to '\(streamName)'")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func addTag() {
    isSubmitting = true
    errorMessage = nil
    StreamManager.shared.addStreamTag(streamName, tag: tagName.trimmed) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Add Auto-Push Rule Form

struct AddAutoPushRuleForm: View {
  var dismiss: () -> Void

  @State private var streamPattern = ""
  @State private var targetURL = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        TextField("e.g. camera*, live_*", text: $streamPattern)
          .textFieldStyle(.roundedBorder)
        Text("Use * as wildcard. Exact match: \"camera1\", Pattern: \"camera*\"")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Stream Pattern")
      }

      Section {
        TextField("rtmp://example.com/live/stream_key", text: $targetURL)
          .textFieldStyle(.roundedBorder)
        Text("Supported: rtmp://, srt://, http://, file://")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Target URL")
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Create Rule") { createRule() }
          .keyboardShortcut(.defaultAction)
          .disabled(
            streamPattern.trimmed.isEmpty || targetURL.trimmed.isEmpty || isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Add Auto-Push Rule")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func createRule() {
    guard UtilityManager.shared.isValidStreamingURL(targetURL.trimmed) else {
      errorMessage = "Please enter a valid streaming URL."
      return
    }
    isSubmitting = true
    errorMessage = nil
    APIClient.shared.createAutoPushRule(
      streamPattern: streamPattern.trimmed, targetURL: targetURL.trimmed
    ) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Push Settings Form

struct PushSettingsForm: View {
  var dismiss: () -> Void

  @State private var maxSpeed = "0"
  @State private var waitTime = "5"
  @State private var autoRestart = true
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        TextField("0 = unlimited", text: $maxSpeed)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Maximum Push Speed (KB/s)")
      }

      Section {
        TextField("Default: 5", text: $waitTime)
          .textFieldStyle(.roundedBorder)
      } header: {
        Text("Wait Time Between Pushes (seconds)")
      }

      Section {
        Toggle("Auto-restart failed pushes", isOn: $autoRestart)
      }

      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Apply") { applySettings() }
          .keyboardShortcut(.defaultAction)
          .disabled(isSubmitting)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Push Settings")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func applySettings() {
    guard let speed = Int(maxSpeed.trimmed), let wait = Int(waitTime.trimmed) else {
      errorMessage = "Please enter valid numbers."
      return
    }
    isSubmitting = true
    errorMessage = nil
    APIClient.shared.applyPushSettings(maxSpeed: speed, waitTime: wait, autoRestart: autoRestart) {
      result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - First-Time Setup Form (Inline)

struct SetupFormInline: View {
  @Bindable var appState: AppState

  @State private var username = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private var isValid: Bool {
    !username.trimmed.isEmpty
      && !password.isEmpty
      && password == confirmPassword
      && password.count >= 4
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Welcome to MistServer")
            .font(.title3.weight(.semibold))
          Text("Create an admin account to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Username")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            TextField("admin", text: $username)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Password")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            SecureField("Password", text: $password)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Confirm Password")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
            SecureField("Confirm password", text: $confirmPassword)
              .textFieldStyle(.roundedBorder)
          }

          if !confirmPassword.isEmpty && password != confirmPassword {
            Text("Passwords do not match")
              .font(.caption)
              .foregroundStyle(.red)
          }
          if !password.isEmpty && password.count < 4 {
            Text("Password must be at least 4 characters")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }

        if let error = errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Button {
          createAccount()
        } label: {
          if isSubmitting {
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
              Text("Creating account...")
            }
            .frame(maxWidth: .infinity)
          } else {
            Text("Create Account")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isValid || isSubmitting)
      }
      .padding(16)
    }
  }

  private func createAccount() {
    isSubmitting = true
    errorMessage = nil

    APIClient.shared.createAccount(username: username.trimmed, password: password) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success(let data):
          if let authorize = data["authorize"] as? [String: Any],
            let status = authorize["status"] as? String
          {
            if status == "ACC_MADE" || status == "OK" {
              appState.needsSetup = false
              // Reset responder chain: the setup form's text fields held first
              // responder and are now gone, which breaks click handling in the
              // borderless panel. Give it back to the content view.
              DispatchQueue.main.async {
                if let w = NSApp.keyWindow {
                  w.makeFirstResponder(w.contentView)
                }
              }
              if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.refreshAllData()
              }
            } else {
              errorMessage = "Unexpected response: \(status)"
            }
          } else {
            appState.needsSetup = false
            DispatchQueue.main.async {
              if let w = NSApp.keyWindow {
                w.makeFirstResponder(w.contentView)
              }
            }
            if let appDelegate = NSApp.delegate as? AppDelegate {
              appDelegate.refreshAllData()
            }
          }
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - String Extension

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
