//
//  DialogManager.swift
//  MistTray
//

import Cocoa
import UniformTypeIdentifiers

class DialogManager: NSObject, NSWindowDelegate {
  static let shared = DialogManager()

  private override init() { super.init() }

  func windowWillClose(_ notification: Notification) {
    NSApp.stopModal(withCode: .cancel)
  }

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
    savePanel.allowedContentTypes = [UTType.json]
    savePanel.nameFieldStringValue = "mistserver-backup.json"
    let response = savePanel.runModal()
    completion(response == .OK ? savePanel.url : nil)
  }

  func showRestoreConfigurationDialog(completion: @escaping (URL?) -> Void) {
    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [UTType.json]
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = false
    openPanel.allowsMultipleSelection = false
    let response = openPanel.runModal()
    completion(response == .OK ? openPanel.url : nil)
  }

  func showExportConfigurationDialog(completion: @escaping (URL?) -> Void) {
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [UTType.json]
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
    savePanel.nameFieldStringValue =
      "mistserver-export-\(dateFormatter.string(from: Date())).json"
    let response = savePanel.runModal()
    completion(response == .OK ? savePanel.url : nil)
  }

  func confirmRestoreConfiguration() -> Bool {
    return showWarningAlert(
      title: "Restore Configuration",
      message:
        "This will replace the current configuration. The server will restart. Are you sure?",
      confirmButtonTitle: "Restore")
  }

  func confirmFactoryReset() -> Bool {
    return showWarningAlert(
      title: "Factory Reset",
      message:
        "This will reset ALL configuration to factory defaults. This action cannot be undone.",
      confirmButtonTitle: "Reset")
  }

  // MARK: - Confirmation Dialogs

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

    if isDestructive, let confirmButton = alert.buttons.first {
      confirmButton.hasDestructiveAction = true
    }

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
