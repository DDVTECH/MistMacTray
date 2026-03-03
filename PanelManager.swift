//
//  PanelManager.swift
//  MistTray
//

import Cocoa
import SwiftUI

// Borderless NSPanel that can become key (required for SwiftUI interaction)
private class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }

  override func sendEvent(_ event: NSEvent) {
    // If the panel lost key status (e.g. after a view hierarchy change that
    // invalidated the responder chain), re-establish it before dispatching
    // the click so SwiftUI's gesture system can process it.
    if event.type == .leftMouseDown && !isKeyWindow {
      makeKeyAndOrderFront(nil)
    }
    super.sendEvent(event)
  }
}

class PanelManager: NSObject, NSWindowDelegate {
  private var panel: NSPanel?
  private let appState: AppState
  private let panelWidth: CGFloat = 380
  private let panelHeight: CGFloat = 520

  init(appState: AppState) {
    self.appState = appState
    super.init()
  }

  // MARK: - Panel Lifecycle

  func togglePanel(relativeTo button: NSStatusBarButton) {
    if let panel = panel, panel.isVisible {
      closePanel()
    } else {
      showPanel(relativeTo: button)
    }
  }

  private func showPanel(relativeTo button: NSStatusBarButton) {
    let panel = makePanel()

    let hostingView = NSHostingController(
      rootView: DashboardView(appState: appState, closePanel: { [weak self] in
        self?.closePanel()
      })
    )
    panel.contentViewController = hostingView
    panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

    // Position below the status bar button
    if let buttonWindow = button.window {
      let buttonFrame = buttonWindow.frame
      let x = buttonFrame.midX - (panelWidth / 2)
      let y = buttonFrame.minY - panelHeight - 4
      panel.setFrameOrigin(NSPoint(x: x, y: y))
    } else {
      panel.center()
    }

    self.panel = panel

    // Activate the app so the panel can properly become key
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func closePanel() {
    panel?.orderOut(nil)
    panel = nil
  }

  // MARK: - Panel Construction

  private func makePanel() -> NSPanel {
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hasShadow = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.delegate = self
    panel.isMovableByWindowBackground = false
    panel.hidesOnDeactivate = false
    return panel
  }

  // MARK: - NSWindowDelegate

  func windowDidResignKey(_ notification: Notification) {
    closePanel()
  }
}
