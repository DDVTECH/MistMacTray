//
//  DialogManager.swift
//  MistTray
//

import Cocoa
import UniformTypeIdentifiers

class DialogManager {
  static let shared = DialogManager()

  private init() {}

  // MARK: - Alert Dialogs

  func showSuccessAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func showErrorAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func showWarningAlert(
    title: String, message: String, confirmButtonTitle: String = "Continue",
    cancelButtonTitle: String = "Cancel"
  ) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: confirmButtonTitle)
    alert.addButton(withTitle: cancelButtonTitle)
    return alert.runModal() == .alertFirstButtonReturn
  }

  func showInfoAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Configuration Backup & Restore

  func showBackupConfigurationDialog(completion: @escaping (URL?) -> Void) {
    let savePanel = NSSavePanel()
    savePanel.title = "Backup MistServer Configuration"
    savePanel.nameFieldStringValue = "mistserver-config-backup.json"
    savePanel.allowedContentTypes = [.json]
    savePanel.canCreateDirectories = true

    savePanel.begin { response in
      completion(response == .OK ? savePanel.url : nil)
    }
  }

  func showRestoreConfigurationDialog(completion: @escaping (URL?) -> Void) {
    let openPanel = NSOpenPanel()
    openPanel.title = "Restore Configuration"
    openPanel.message = "Select a MistServer configuration backup file to restore"
    openPanel.allowedContentTypes = [.json]
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true

    openPanel.begin { response in
      completion(response == .OK ? openPanel.url : nil)
    }
  }

  func showExportConfigurationDialog(completion: @escaping (URL?) -> Void) {
    let savePanel = NSSavePanel()
    savePanel.title = "Export Configuration"
    savePanel.message = "Save configuration backup with metadata"
    savePanel.allowedContentTypes = [.json]

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    savePanel.nameFieldStringValue = "mistserver_config_\(formatter.string(from: Date())).json"

    savePanel.begin { response in
      completion(response == .OK ? savePanel.url : nil)
    }
  }

  func confirmRestoreConfiguration() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Restore Configuration"
    alert.informativeText =
      "This will replace the current server configuration. The server will be restarted. Continue?"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Restore")
    alert.addButton(withTitle: "Cancel")

    return alert.runModal() == .alertFirstButtonReturn
  }

  func confirmFactoryReset() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Reset to Factory Defaults"
    alert.informativeText =
      "This will permanently delete all current configuration and reset to factory defaults. This action cannot be undone. Continue?"
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")

    return alert.runModal() == .alertFirstButtonReturn
  }

  // MARK: - Stream Management Dialogs

  func showCreateStreamDialog(completion: @escaping (StreamConfiguration?) -> Void) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "Create New Stream"
    window.center()

    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.spacing = 16
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    // Stream Name Section
    let nameSection = createFormSection(title: "📺 Stream Name", required: true)
    let nameField = NSTextField()
    nameField.placeholderString = "Enter stream name (e.g., 'camera1', 'livestream')"
    nameSection.addArrangedSubview(nameField)
    mainStack.addArrangedSubview(nameSection)

    // Source Section
    let sourceSection = createFormSection(title: "📡 Source", required: true)
    let sourceField = NSTextField()
    sourceField.placeholderString = "rtmp://source.example.com/live/stream or /path/to/file.mp4"
    sourceSection.addArrangedSubview(sourceField)

    let sourceHelp = NSTextField(
      wrappingLabelWithString:
        "Enter the source URL or file path. Supported: RTMP, RTSP, HTTP, file paths, push:// for incoming streams"
    )
    sourceHelp.font = NSFont.systemFont(ofSize: 11)
    sourceHelp.textColor = .secondaryLabelColor
    sourceHelp.preferredMaxLayoutWidth = 450
    sourceSection.addArrangedSubview(sourceHelp)
    mainStack.addArrangedSubview(sourceSection)

    // Buttons
    let buttonSection = NSStackView()
    buttonSection.orientation = .horizontal
    buttonSection.spacing = 12
    buttonSection.alignment = .trailing

    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let createButton = NSButton(title: "Create Stream", target: nil, action: nil)
    createButton.keyEquivalent = "\r"

    buttonSection.addArrangedSubview(cancelButton)
    buttonSection.addArrangedSubview(createButton)
    mainStack.addArrangedSubview(buttonSection)

    contentView.addSubview(mainStack)
    NSLayoutConstraint.activate([
      mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
    ])

    window.contentView = contentView

    var result: StreamConfiguration?

    cancelButton.target = self
    cancelButton.action = #selector(dismissModalWindow(_:))

    createButton.target = self
    createButton.action = #selector(acceptModalWindow(_:))

    let response = NSApp.runModal(for: window)
    window.close()

    if response == .OK {
      let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let source = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

      if !name.isEmpty && !source.isEmpty {
        result = StreamConfiguration(name: name, source: source)
      }
    }

    completion(result)
  }

  func showEditStreamDialog(
    streamName: String, currentConfig: [String: Any],
    completion: @escaping (StreamConfiguration?) -> Void
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "Edit Stream: \(streamName)"
    window.center()

    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.spacing = 16
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    // Source Section
    let sourceSection = createFormSection(title: "📡 Source", required: true)
    let sourceField = NSTextField()
    sourceField.stringValue = currentConfig["source"] as? String ?? ""
    sourceField.placeholderString = "rtmp://source.example.com/live/stream or /path/to/file.mp4"
    sourceSection.addArrangedSubview(sourceField)
    mainStack.addArrangedSubview(sourceSection)

    // Buttons
    let buttonSection = NSStackView()
    buttonSection.orientation = .horizontal
    buttonSection.spacing = 12
    buttonSection.alignment = .trailing

    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let saveButton = NSButton(title: "Save Changes", target: nil, action: nil)
    saveButton.keyEquivalent = "\r"

    buttonSection.addArrangedSubview(cancelButton)
    buttonSection.addArrangedSubview(saveButton)
    mainStack.addArrangedSubview(buttonSection)

    contentView.addSubview(mainStack)
    NSLayoutConstraint.activate([
      mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
    ])

    window.contentView = contentView

    var result: StreamConfiguration?

    cancelButton.target = self
    cancelButton.action = #selector(dismissModalWindow(_:))

    saveButton.target = self
    saveButton.action = #selector(acceptModalWindow(_:))

    let response = NSApp.runModal(for: window)
    window.close()

    if response == .OK {
      let source = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if !source.isEmpty {
        result = StreamConfiguration(name: streamName, source: source)
      }
    }

    completion(result)
  }

  func confirmDeleteStream(streamName: String, viewerCount: Int, bandwidth: Int) -> Bool {
    let bandwidthStr = formatBandwidth(bandwidth)
    let message = """
      Stream: \(streamName)
      Viewers: \(viewerCount)
      Bandwidth: \(bandwidthStr)

      This will permanently delete the stream configuration. Active viewers will be disconnected.
      """

    return showWarningAlert(
      title: "Delete Stream", message: message, confirmButtonTitle: "Delete",
      cancelButtonTitle: "Cancel")
  }

  // MARK: - Push Management Dialogs

  func showCreatePushDialog(
    availableStreams: [String], completion: @escaping (PushConfiguration?) -> Void
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "Start New Push"
    window.center()

    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.spacing = 16
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    // Stream Selection
    let streamSection = createFormSection(title: "📺 Source Stream", required: true)
    let streamPopup = NSPopUpButton()
    streamPopup.addItems(
      withTitles: availableStreams.isEmpty ? ["No streams available"] : availableStreams)
    streamPopup.isEnabled = !availableStreams.isEmpty
    streamSection.addArrangedSubview(streamPopup)
    mainStack.addArrangedSubview(streamSection)

    // Target URL
    let targetSection = createFormSection(title: "🎯 Target URL", required: true)
    let targetField = NSTextField()
    targetField.placeholderString = "rtmp://live.example.com/live/streamkey"
    targetSection.addArrangedSubview(targetField)

    let targetHelp = NSTextField(
      wrappingLabelWithString:
        "Enter the destination URL where the stream should be pushed (RTMP, RTSP, etc.)")
    targetHelp.font = NSFont.systemFont(ofSize: 11)
    targetHelp.textColor = .secondaryLabelColor
    targetHelp.preferredMaxLayoutWidth = 450
    targetSection.addArrangedSubview(targetHelp)
    mainStack.addArrangedSubview(targetSection)

    // Buttons
    let buttonSection = NSStackView()
    buttonSection.orientation = .horizontal
    buttonSection.spacing = 12
    buttonSection.alignment = .trailing

    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let startButton = NSButton(title: "Start Push", target: nil, action: nil)
    startButton.keyEquivalent = "\r"
    startButton.isEnabled = !availableStreams.isEmpty

    buttonSection.addArrangedSubview(cancelButton)
    buttonSection.addArrangedSubview(startButton)
    mainStack.addArrangedSubview(buttonSection)

    contentView.addSubview(mainStack)
    NSLayoutConstraint.activate([
      mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
    ])

    window.contentView = contentView

    var result: PushConfiguration?

    cancelButton.target = self
    cancelButton.action = #selector(dismissModalWindow(_:))

    startButton.target = self
    startButton.action = #selector(acceptModalWindow(_:))

    let response = NSApp.runModal(for: window)
    window.close()

    if response == .OK && !availableStreams.isEmpty {
      let selectedStream = streamPopup.titleOfSelectedItem ?? ""
      let target = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

      if !selectedStream.isEmpty && !target.isEmpty {
        result = PushConfiguration(streamName: selectedStream, targetURL: target)
      }
    }

    completion(result)
  }

  // MARK: - Protocol Configuration Dialog

  func showProtocolConfigurationDialog(
    protocolName: String, completion: @escaping (ProtocolConfiguration?) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = "\(protocolName) Protocol Configuration"
    alert.informativeText =
      "Configure the port and interface settings for the \(protocolName) protocol."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Configure")
    alert.addButton(withTitle: "Cancel")

    // Create input fields
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 12
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Port section
    let portLabel = NSTextField(labelWithString: "Port:")
    let portField = NSTextField()
    portField.placeholderString =
      "Default: \(UtilityManager.shared.getDefaultPort(for: protocolName))"
    portField.stringValue = UtilityManager.shared.getDefaultPort(for: protocolName)

    // Interface section
    let interfaceLabel = NSTextField(labelWithString: "Interface:")
    let interfaceField = NSTextField()
    interfaceField.placeholderString = "0.0.0.0 (all interfaces)"
    interfaceField.stringValue = "0.0.0.0"

    stackView.addArrangedSubview(portLabel)
    stackView.addArrangedSubview(portField)
    stackView.addArrangedSubview(interfaceLabel)
    stackView.addArrangedSubview(interfaceField)

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 300),
      portField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
      interfaceField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
    ])

    alert.accessoryView = stackView
    alert.window.initialFirstResponder = portField

    // Show dialog
    let response = alert.runModal()

    guard response == .alertFirstButtonReturn else {
      print("🚫 Protocol configuration cancelled by user")
      completion(nil)
      return
    }

    let port = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let interface = interfaceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate port
    guard !port.isEmpty, let portInt = Int(port) else {
      showErrorAlert(title: "Invalid Port", message: "Please enter a valid port number.")
      completion(nil)
      return
    }

    // Use default interface if empty
    let finalInterface = interface.isEmpty ? "0.0.0.0" : interface

    completion(ProtocolConfiguration(port: portInt, interface: finalInterface))
  }

  // MARK: - Preferences Dialog

  func showPreferencesDialog(
    currentSettings: PreferencesSettings, completion: @escaping (PreferencesSettings?) -> Void
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "MistTray Preferences"
    window.center()

    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.spacing = 20
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    // Auto-update Section
    let autoUpdateSection = createFormSection(title: "🔄 Auto-Update Settings", required: false)
    let autoUpdateCheckbox = NSButton(
      checkboxWithTitle: "Enable automatic updates", target: nil, action: nil)
    autoUpdateCheckbox.state = currentSettings.autoUpdateEnabled ? .on : .off
    autoUpdateSection.addArrangedSubview(autoUpdateCheckbox)

    let updateHelp = NSTextField(
      wrappingLabelWithString:
        "When enabled, MistServer will automatically update to the latest version when available.")
    updateHelp.font = NSFont.systemFont(ofSize: 11)
    updateHelp.textColor = .secondaryLabelColor
    updateHelp.preferredMaxLayoutWidth = 550
    autoUpdateSection.addArrangedSubview(updateHelp)
    mainStack.addArrangedSubview(autoUpdateSection)

    // Startup Section
    let startupSection = createFormSection(title: "🚀 Startup Settings", required: false)
    let startupCheckbox = NSButton(
      checkboxWithTitle: "Start MistServer automatically on app launch", target: nil, action: nil)
    startupCheckbox.state = currentSettings.startServerOnLaunch ? .on : .off
    startupSection.addArrangedSubview(startupCheckbox)
    mainStack.addArrangedSubview(startupSection)

    // Notification Section
    let notificationSection = createFormSection(title: "🔔 Notifications", required: false)
    let notificationCheckbox = NSButton(
      checkboxWithTitle: "Show notifications for server events", target: nil, action: nil)
    notificationCheckbox.state = currentSettings.showNotifications ? .on : .off
    notificationSection.addArrangedSubview(notificationCheckbox)
    mainStack.addArrangedSubview(notificationSection)

    // Buttons
    let buttonSection = NSStackView()
    buttonSection.orientation = .horizontal
    buttonSection.spacing = 12
    buttonSection.alignment = .trailing

    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)
    saveButton.keyEquivalent = "\r"

    buttonSection.addArrangedSubview(cancelButton)
    buttonSection.addArrangedSubview(saveButton)
    mainStack.addArrangedSubview(buttonSection)

    contentView.addSubview(mainStack)
    NSLayoutConstraint.activate([
      mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
    ])

    window.contentView = contentView

    var result: PreferencesSettings?

    cancelButton.target = self
    cancelButton.action = #selector(dismissModalWindow(_:))

    saveButton.target = self
    saveButton.action = #selector(acceptModalWindow(_:))

    let response = NSApp.runModal(for: window)
    window.close()

    if response == .OK {
      result = PreferencesSettings(
        autoUpdateEnabled: autoUpdateCheckbox.state == .on,
        startServerOnLaunch: startupCheckbox.state == .on,
        showNotifications: notificationCheckbox.state == .on
      )
    }

    completion(result)
  }

  // MARK: - Stream Tags Dialog

  func showStreamTagsDialog(streamName: String, completion: @escaping ([String]?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Manage Tags for '\(streamName)'"
    alert.informativeText = "Add or remove tags to organize and categorize your streams."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Add Tag")
    alert.addButton(withTitle: "Close")

    // Create tags display
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Current tags section
    let tagsLabel = NSTextField(labelWithString: "Current Tags:")
    tagsLabel.font = NSFont.boldSystemFont(ofSize: 13)
    stackView.addArrangedSubview(tagsLabel)

    // Fetch existing tags first
    APIClient.shared.fetchStreamTags(for: streamName) { result in
      DispatchQueue.main.async {
        let existingTags: [String]
        switch result {
        case .success(let tags):
          existingTags = tags
        case .failure:
          existingTags = []
        }

        if existingTags.isEmpty {
          let noTagsLabel = NSTextField(labelWithString: "No tags assigned to this stream")
          noTagsLabel.font = NSFont.systemFont(ofSize: 11)
          noTagsLabel.textColor = .secondaryLabelColor
          stackView.addArrangedSubview(noTagsLabel)
        } else {
          for tag in existingTags {
            let tagView = NSStackView()
            tagView.orientation = .horizontal
            tagView.spacing = 8

            let tagLabel = NSTextField(labelWithString: "🏷️ \(tag)")
            tagLabel.font = NSFont.systemFont(ofSize: 11)

            tagView.addArrangedSubview(tagLabel)
            stackView.addArrangedSubview(tagView)
          }
        }

        // Instructions
        let instructionsLabel = NSTextField(
          labelWithString: """
            Tags help organize streams by category, purpose, or any custom criteria.
            Examples: "live", "recording", "backup", "camera1", "production"
            """)
        instructionsLabel.font = NSFont.systemFont(ofSize: 10)
        instructionsLabel.textColor = .tertiaryLabelColor
        instructionsLabel.isEditable = false
        instructionsLabel.isBordered = false
        instructionsLabel.backgroundColor = .clear
        instructionsLabel.lineBreakMode = .byWordWrapping
        instructionsLabel.maximumNumberOfLines = 0

        stackView.addArrangedSubview(NSView())  // Spacer
        stackView.addArrangedSubview(instructionsLabel)

        // Set constraints
        NSLayoutConstraint.activate([
          stackView.widthAnchor.constraint(equalToConstant: 400)
        ])

        alert.accessoryView = stackView

        // Show dialog
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
          // User clicked "Add Tag"
          completion(existingTags)
        } else {
          completion(nil)
        }
      }
    }
  }

  func showAddStreamTagDialog(streamName: String, completion: @escaping (String?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Add Tag to '\(streamName)'"
    alert.informativeText = "Enter a tag name to categorize this stream."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Add Tag")
    alert.addButton(withTitle: "Cancel")

    // Create input field
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    let tagLabel = NSTextField(labelWithString: "Tag Name:")
    let tagField = NSTextField()
    tagField.placeholderString = "Enter tag name (e.g., live, recording, camera1)"
    tagField.stringValue = ""

    // Example text
    let exampleText = NSTextField(
      labelWithString: """
        Examples:
        • Purpose: "live", "recording", "backup"
        • Location: "studio", "outdoor", "office" 
        • Equipment: "camera1", "camera2", "microphone"
        • Status: "production", "testing", "archive"
        """)
    exampleText.font = NSFont.systemFont(ofSize: 10)
    exampleText.textColor = .tertiaryLabelColor
    exampleText.isEditable = false
    exampleText.isBordered = false
    exampleText.backgroundColor = .clear
    exampleText.lineBreakMode = .byWordWrapping
    exampleText.maximumNumberOfLines = 0

    stackView.addArrangedSubview(tagLabel)
    stackView.addArrangedSubview(tagField)
    stackView.addArrangedSubview(exampleText)

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 350),
      tagField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
    ])

    alert.accessoryView = stackView
    alert.window.initialFirstResponder = tagField

    // Show dialog
    let response = alert.runModal()

    guard response == .alertFirstButtonReturn else {
      print("🚫 Stream tag addition cancelled by user")
      completion(nil)
      return
    }

    let tagName = tagField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate input
    guard !tagName.isEmpty else {
      showErrorAlert(title: "Invalid Tag Name", message: "Please enter a valid tag name.")
      completion(nil)
      return
    }

    completion(tagName)
  }

  // MARK: - Auto Push Rules Dialog

  func showAutoPushRulesDialog(
    existingRules: [String: Any], completion: @escaping (AutoPushRuleAction) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = "Manage Auto-Push Rules"
    alert.informativeText = "Configure automatic push rules that trigger when streams start."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Add New Rule")
    alert.addButton(withTitle: "Close")

    // Create rules display
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Existing rules section
    let rulesLabel = NSTextField(labelWithString: "Existing Auto-Push Rules:")
    rulesLabel.font = NSFont.boldSystemFont(ofSize: 13)
    stackView.addArrangedSubview(rulesLabel)

    if existingRules.isEmpty {
      let noRulesLabel = NSTextField(labelWithString: "No auto-push rules configured")
      noRulesLabel.font = NSFont.systemFont(ofSize: 11)
      noRulesLabel.textColor = .secondaryLabelColor
      stackView.addArrangedSubview(noRulesLabel)
    } else {
      for (_, ruleData) in existingRules {
        if let rule = ruleData as? [String: Any] {
          let stream = rule["stream"] as? String ?? "Unknown"
          let target = rule["target"] as? String ?? "Unknown"

          let ruleView = NSStackView()
          ruleView.orientation = .horizontal
          ruleView.spacing = 8

          let ruleLabel = NSTextField(labelWithString: "\(stream) → \(target)")
          ruleLabel.font = NSFont.systemFont(ofSize: 11)

          let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
          deleteButton.bezelStyle = .rounded
          deleteButton.controlSize = .small

          ruleView.addArrangedSubview(ruleLabel)
          ruleView.addArrangedSubview(deleteButton)

          stackView.addArrangedSubview(ruleView)
        }
      }
    }

    // Instructions
    let instructionsLabel = NSTextField(
      labelWithString: """
        Auto-push rules automatically start pushes when matching streams become active.
        This is useful for automatic recording or forwarding to external services.
        """)
    instructionsLabel.font = NSFont.systemFont(ofSize: 10)
    instructionsLabel.textColor = .tertiaryLabelColor
    instructionsLabel.isEditable = false
    instructionsLabel.isBordered = false
    instructionsLabel.backgroundColor = .clear
    instructionsLabel.lineBreakMode = .byWordWrapping
    instructionsLabel.maximumNumberOfLines = 0

    stackView.addArrangedSubview(NSView())  // Spacer
    stackView.addArrangedSubview(instructionsLabel)

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 450)
    ])

    alert.accessoryView = stackView

    // Show dialog
    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      completion(.addRule)
    } else {
      completion(.close)
    }
  }

  func showAddAutoPushRuleDialog(completion: @escaping (String?, String?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Add Auto-Push Rule"
    alert.informativeText =
      "Create a rule to automatically start pushes when matching streams become active."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Create Rule")
    alert.addButton(withTitle: "Cancel")

    // Create input fields
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Stream pattern field
    let streamLabel = NSTextField(labelWithString: "Stream Pattern:")
    let streamField = NSTextField()
    streamField.placeholderString = "Enter stream name or pattern (e.g., camera*, live_*)"
    streamField.stringValue = ""

    // Target URL field
    let targetLabel = NSTextField(labelWithString: "Target URL:")
    let targetField = NSTextField()
    targetField.placeholderString = "rtmp://example.com/live/stream_key"
    targetField.stringValue = ""

    // Instructions
    let instructionsText = NSTextField(
      labelWithString: """
        Stream Pattern Examples:
        • Exact match: "camera1" (matches only "camera1")
        • Wildcard: "camera*" (matches "camera1", "camera2", etc.)
        • Prefix: "live_*" (matches "live_stream1", "live_broadcast", etc.)

        Target URL Examples:
        • RTMP: rtmp://live.example.com/live/stream_key
        • SRT: srt://server.example.com:9999
        • File: file:///path/to/recording.mp4
        • HTTP: http://server.example.com:8080/publish/stream
        """)
    instructionsText.font = NSFont.systemFont(ofSize: 10)
    instructionsText.textColor = .tertiaryLabelColor
    instructionsText.isEditable = false
    instructionsText.isBordered = false
    instructionsText.backgroundColor = .clear
    instructionsText.lineBreakMode = .byWordWrapping
    instructionsText.maximumNumberOfLines = 0

    stackView.addArrangedSubview(streamLabel)
    stackView.addArrangedSubview(streamField)
    stackView.addArrangedSubview(targetLabel)
    stackView.addArrangedSubview(targetField)
    stackView.addArrangedSubview(instructionsText)

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 450),
      streamField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
      targetField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
    ])

    alert.accessoryView = stackView
    alert.window.initialFirstResponder = streamField

    // Show dialog
    let response = alert.runModal()

    guard response == .alertFirstButtonReturn else {
      print("🚫 Auto-push rule creation cancelled by user")
      completion(nil, nil)
      return
    }

    let streamPattern = streamField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetURL = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate inputs
    guard !streamPattern.isEmpty else {
      showErrorAlert(
        title: "Invalid Stream Pattern", message: "Please enter a valid stream pattern.")
      completion(nil, nil)
      return
    }

    guard !targetURL.isEmpty else {
      showErrorAlert(title: "Invalid Target URL", message: "Please enter a valid target URL.")
      completion(nil, nil)
      return
    }

    // Basic URL validation
    guard UtilityManager.shared.isValidStreamingURL(targetURL) else {
      showErrorAlert(
        title: "Invalid URL Format",
        message: "Please enter a valid streaming URL (rtmp://, srt://, http://, file://, etc.).")
      completion(nil, nil)
      return
    }

    completion(streamPattern, targetURL)
  }

  // MARK: - Enhanced Statistics Dialog

  func displayEnhancedStatistics(serverStats: [String: Any]) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "Enhanced Server Statistics"
    window.center()

    let contentView = NSView()
    let scrollView = NSScrollView()
    let textView = NSTextView()

    // Format statistics
    var statsText = "📊 MistServer Enhanced Statistics\n"
    statsText += String(repeating: "=", count: 50) + "\n\n"

    if let totals = serverStats["totals"] as? [String: Any] {
      statsText += "🖥️ Server Totals:\n"
      statsText += "  • Total Clients: \(totals["clients"] ?? 0)\n"
      statsText +=
        "  • Total Bandwidth: \(UtilityManager.shared.formatBandwidth(totals["bps_out"] as? Int ?? 0))\n"
      statsText +=
        "  • Uptime: \(UtilityManager.shared.formatConnectionTime(totals["uptime"] as? Int ?? 0))\n"
      statsText += "  • Active Streams: \(totals["streams"] ?? 0)\n\n"
    }

    if let memory = serverStats["memory"] as? [String: Any] {
      statsText += "💾 Memory Usage:\n"
      statsText += "  • Used: \(memory["used"] ?? 0) MB\n"
      statsText += "  • Total: \(memory["total"] ?? 0) MB\n\n"
    }

    if let cpu = serverStats["cpu"] as? [String: Any] {
      statsText += "⚡ CPU Usage:\n"
      statsText += "  • Usage: \(String(format: "%.1f", cpu["usage"] as? Double ?? 0.0))%\n\n"
    }

    textView.string = statsText
    textView.isEditable = false
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true

    contentView.addSubview(scrollView)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -60),
    ])

    // Close button
    let closeButton = NSButton(
      title: "Close", target: self, action: #selector(dismissModalWindow(_:)))
    contentView.addSubview(closeButton)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      closeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
    ])

    window.contentView = contentView
    NSApp.runModal(for: window)
    window.close()
  }

  // MARK: - Server Statistics Dialog

  func showServerStatistics(
    activeStreams: Int, totalViewers: Int, activePushes: Int, totals: [String: Any]
  ) {
    let alert = NSAlert()
    alert.messageText = "MistServer Statistics"
    alert.informativeText = "Real-time server performance and historical usage statistics."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Refresh")
    alert.addButton(withTitle: "Close")

    // Create statistics display
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Current statistics
    let currentLabel = NSTextField(labelWithString: "Current Statistics:")
    currentLabel.font = NSFont.boldSystemFont(ofSize: 13)
    stackView.addArrangedSubview(currentLabel)

    let streamsLabel = NSTextField(labelWithString: "Active Streams: \(activeStreams)")
    streamsLabel.font = NSFont.systemFont(ofSize: 11)
    stackView.addArrangedSubview(streamsLabel)

    let viewersLabel = NSTextField(labelWithString: "Connected Viewers: \(totalViewers)")
    viewersLabel.font = NSFont.systemFont(ofSize: 11)
    stackView.addArrangedSubview(viewersLabel)

    let pushesLabel = NSTextField(labelWithString: "Active Pushes: \(activePushes)")
    pushesLabel.font = NSFont.systemFont(ofSize: 11)
    stackView.addArrangedSubview(pushesLabel)

    // Historical totals (if available)
    if !totals.isEmpty {
      stackView.addArrangedSubview(NSView())  // Spacer

      let totalsLabel = NSTextField(labelWithString: "Historical Totals:")
      totalsLabel.font = NSFont.boldSystemFont(ofSize: 13)
      stackView.addArrangedSubview(totalsLabel)

      if let totalConnections = totals["connections"] as? Int {
        let connectionsLabel = NSTextField(
          labelWithString: "Total Connections: \(totalConnections)")
        connectionsLabel.font = NSFont.systemFont(ofSize: 11)
        stackView.addArrangedSubview(connectionsLabel)
      }

      if let totalBytes = totals["bytes"] as? Int {
        let bytesStr = UtilityManager.shared.formatBandwidth(totalBytes)
        let bytesLabel = NSTextField(labelWithString: "Total Data Transferred: \(bytesStr)")
        bytesLabel.font = NSFont.systemFont(ofSize: 11)
        stackView.addArrangedSubview(bytesLabel)
      }

      if let uptime = totals["uptime"] as? Int {
        let uptimeStr = UtilityManager.shared.formatConnectionTime(uptime)
        let uptimeLabel = NSTextField(labelWithString: "Server Uptime: \(uptimeStr)")
        uptimeLabel.font = NSFont.systemFont(ofSize: 11)
        stackView.addArrangedSubview(uptimeLabel)
      }
    }

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 350)
    ])

    alert.accessoryView = stackView

    // Show dialog
    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      // User clicked "Refresh" - handled by caller
    }
  }

  // MARK: - Protocol Management Dialogs

  struct ProtocolConfiguration {
    let port: Int
    let interface: String
  }

  func showActiveProtocols(protocols: [String: Any]) {
    let alert = NSAlert()
    alert.messageText = "Active Protocols"
    alert.informativeText = "Currently enabled protocols and their configurations."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Refresh")
    alert.addButton(withTitle: "Close")

    // Create protocol display
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 6
    stackView.translatesAutoresizingMaskIntoConstraints = false

    if protocols.isEmpty {
      let noProtocolsLabel = NSTextField(labelWithString: "No protocol configuration found")
      noProtocolsLabel.font = NSFont.systemFont(ofSize: 11)
      noProtocolsLabel.textColor = .secondaryLabelColor
      stackView.addArrangedSubview(noProtocolsLabel)
    } else {
      for (protocolName, protocolConfig) in protocols {
        let protocolView = NSStackView()
        protocolView.orientation = .vertical
        protocolView.spacing = 2

        let nameLabel = NSTextField(labelWithString: "🔌 \(protocolName.uppercased())")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 12)
        protocolView.addArrangedSubview(nameLabel)

        if let config = protocolConfig as? [String: Any] {
          // Show key configuration details
          if let port = config["port"] as? Int {
            let portLabel = NSTextField(labelWithString: "  Port: \(port)")
            portLabel.font = NSFont.systemFont(ofSize: 10)
            portLabel.textColor = .secondaryLabelColor
            protocolView.addArrangedSubview(portLabel)
          }

          if let interface = config["interface"] as? String {
            let interfaceLabel = NSTextField(labelWithString: "  Interface: \(interface)")
            interfaceLabel.font = NSFont.systemFont(ofSize: 10)
            interfaceLabel.textColor = .secondaryLabelColor
            protocolView.addArrangedSubview(interfaceLabel)
          }
        } else {
          let statusLabel = NSTextField(labelWithString: "  Status: Enabled")
          statusLabel.font = NSFont.systemFont(ofSize: 10)
          statusLabel.textColor = .systemGreen
          protocolView.addArrangedSubview(statusLabel)
        }

        stackView.addArrangedSubview(protocolView)

        // Add separator
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        stackView.addArrangedSubview(separator)
      }
    }

    scrollView.documentView = stackView

    // Set constraints
    NSLayoutConstraint.activate([
      scrollView.widthAnchor.constraint(equalToConstant: 350),
      scrollView.heightAnchor.constraint(equalToConstant: 250),
      stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
    ])

    alert.accessoryView = scrollView

    // Show dialog
    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      // User clicked "Refresh" - handled by caller
    }
  }

  // MARK: - Session Management Dialogs

  func showStopTaggedSessionsDialog(completion: @escaping (String?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Stop Tagged Sessions"
    alert.informativeText = "Enter the tag name to disconnect all sessions with that tag."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Stop Sessions")
    alert.addButton(withTitle: "Cancel")

    // Create form
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false

    let tagLabel = NSTextField(labelWithString: "Tag Name:")
    tagLabel.font = NSFont.boldSystemFont(ofSize: 12)
    stackView.addArrangedSubview(tagLabel)

    let tagField = NSTextField()
    tagField.placeholderString = "Enter tag name to stop all sessions with this tag"
    tagField.translatesAutoresizingMaskIntoConstraints = false
    stackView.addArrangedSubview(tagField)

    let warningLabel = NSTextField(
      labelWithString: "⚠️ This will disconnect ALL sessions with the specified tag!")
    warningLabel.font = NSFont.systemFont(ofSize: 11)
    warningLabel.textColor = .systemRed
    stackView.addArrangedSubview(warningLabel)

    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 350),
      tagField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
    ])

    alert.accessoryView = stackView

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      let tagName = tagField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

      if tagName.isEmpty {
        showErrorAlert(title: "Error", message: "Please enter a tag name.")
        completion(nil)
        return
      }

      completion(tagName)
    } else {
      completion(nil)
    }
  }

  func showTaggedSessionsViewer() {
    let alert = NSAlert()
    alert.messageText = "Tagged Sessions Viewer"
    alert.informativeText =
      "This feature shows all sessions grouped by their tags. Tagged sessions can be managed through the session management system using tag operations."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Push Settings Dialog

  struct PushSettings {
    let maxSpeed: Int
    let waitTime: Int
    let autoRestart: Bool
  }

  func showPushSettingsDialog(completion: @escaping (PushSettings?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Push Settings Configuration"
    alert.informativeText = "Configure global push settings for MistServer."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Apply Settings")
    alert.addButton(withTitle: "Cancel")

    // Create form
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 12
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Max speed section
    let speedLabel = NSTextField(labelWithString: "Maximum Push Speed (KB/s):")
    let maxSpeedField = NSTextField()
    maxSpeedField.placeholderString = "0 = unlimited"
    maxSpeedField.stringValue = "0"

    // Wait time section
    let waitLabel = NSTextField(labelWithString: "Wait Time Between Pushes (seconds):")
    let waitTimeField = NSTextField()
    waitTimeField.placeholderString = "Default: 5"
    waitTimeField.stringValue = "5"

    // Auto-restart section
    let autoRestartCheckbox = NSButton(
      checkboxWithTitle: "Auto-restart failed pushes", target: nil, action: nil)
    autoRestartCheckbox.state = .on

    stackView.addArrangedSubview(speedLabel)
    stackView.addArrangedSubview(maxSpeedField)
    stackView.addArrangedSubview(waitLabel)
    stackView.addArrangedSubview(waitTimeField)
    stackView.addArrangedSubview(autoRestartCheckbox)

    // Set constraints
    NSLayoutConstraint.activate([
      stackView.widthAnchor.constraint(equalToConstant: 350),
      maxSpeedField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
      waitTimeField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
    ])

    alert.accessoryView = stackView
    alert.window.initialFirstResponder = maxSpeedField

    // Show dialog
    let response = alert.runModal()

    guard response == .alertFirstButtonReturn else {
      print("🚫 Push settings configuration cancelled by user")
      completion(nil)
      return
    }

    let maxSpeed = Int(maxSpeedField.stringValue) ?? 0
    let waitTime = Int(waitTimeField.stringValue) ?? 5
    let autoRestart = autoRestartCheckbox.state == .on

    completion(PushSettings(maxSpeed: maxSpeed, waitTime: waitTime, autoRestart: autoRestart))
  }

  // MARK: - Helper Methods

  private func createFormSection(title: String, required: Bool = false) -> NSStackView {
    let section = NSStackView()
    section.orientation = .vertical
    section.spacing = 8

    let titleLabel = NSTextField(labelWithString: title + (required ? " *" : ""))
    titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
    section.addArrangedSubview(titleLabel)

    return section
  }

  private func getDefaultPort(for protocolName: String) -> String {
    switch protocolName.uppercased() {
    case "RTMP": return "1935"
    case "HLS": return "8080"
    case "DASH": return "8080"
    case "WEBRTC": return "8080"
    case "SRT": return "9999"
    case "RTSP": return "554"
    case "HTTP": return "8080"
    case "WEBSOCKET": return "8080"
    default: return "8080"
    }
  }

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

  // MARK: - Modal Window Actions

  @objc private func dismissModalWindow(_ sender: Any) {
    NSApp.stopModal(withCode: .cancel)
  }

  @objc private func acceptModalWindow(_ sender: Any) {
    NSApp.stopModal(withCode: .OK)
  }

  func showConfirmationAlert(
    title: String, message: String, confirmButtonTitle: String = "OK", isDestructive: Bool = false,
    completion: @escaping (Bool) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = isDestructive ? .warning : .informational
    alert.addButton(withTitle: confirmButtonTitle)
    alert.addButton(withTitle: "Cancel")

    // Make the destructive button red if needed
    if isDestructive, let confirmButton = alert.buttons.first {
      confirmButton.hasDestructiveAction = true
    }

    // Show confirmation dialog
    let response = alert.runModal()
    completion(response == .alertFirstButtonReturn)
  }
}

// MARK: - Configuration Data Structures

struct StreamConfiguration {
  let name: String
  let source: String
}

struct PushConfiguration {
  let streamName: String
  let targetURL: String
}

struct PreferencesSettings {
  let autoUpdateEnabled: Bool
  let startServerOnLaunch: Bool
  let showNotifications: Bool
}

enum AutoPushRuleAction {
  case addRule
  case deleteRule(String)
  case close
}
