//
//  ManagementViews.swift
//  MistTray
//

import SwiftUI

// MARK: - Protocols View

struct ProtocolsView: View {
  @Bindable var appState: AppState
  @Binding var path: NavigationPath
  @State private var showAddSheet = false
  @State private var selectedConnector = ""

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Protocols")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("\(appState.configuredProtocols.count) configured")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              showAddSheet = true
            } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if appState.configuredProtocols.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "network")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No protocols configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(appState.sortedProtocols, id: \.index) { proto in
              protocolCard(proto)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: $showAddSheet) {
      addProtocolSheet
    }
  }

  private func protocolCard(_ proto: (index: Int, connector: String, port: Int, online: Int))
    -> some View
  {
    Button {
      path.append(Route.protocolConfig(proto.connector, proto.index))
    } label: {
      HStack(spacing: 10) {
        Circle()
          .fill(proto.online == 1 ? Color.tnGreen : proto.online == 2 ? Color.tnYellow : Color.tnRed)
          .frame(width: 8, height: 8)

        VStack(alignment: .leading, spacing: 2) {
          Text(proto.connector)
            .font(.system(.body, weight: .medium))
          HStack(spacing: 6) {
            if proto.port > 0 {
              Text("Port \(proto.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(proto.online == 1 ? "Online" : proto.online == 2 ? "Starting" : "Offline")
              .font(.system(size: 10, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(
                proto.online == 1 ? Color.tnGreen.opacity(0.1) : proto.online == 2
                  ? Color.tnYellow.opacity(0.1) : Color.tnRed.opacity(0.1)
              )
              .clipShape(Capsule())
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption2).foregroundStyle(.tertiary)

        Button(role: .destructive) {
          deleteProtocol(at: proto.index)
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
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointerOnHover()
  }

  private func deleteProtocol(at index: Int) {
    guard index < appState.configuredProtocols.count else { return }
    let proto = appState.configuredProtocols[index]
    APIClient.shared.deleteProtocol(proto) { (result: Result<[String: Any], APIError>) in
      DispatchQueue.main.async {
        if case .success = result {
          refreshData()
        }
      }
    }
  }

  /// Filter out PUSHONLY connectors and already-configured ones
  private var availableProtocols: [String] {
    appState.availableConnectors.keys.sorted().filter { name in
      guard let info = appState.availableConnectors[name] as? [String: Any] else { return true }
      // Filter out PUSHONLY connectors
      if let flags = info["flags"] as? [String: Any], flags["PUSHONLY"] != nil { return false }
      if info["PUSHONLY"] != nil { return false }
      return true
    }
  }

  private var addProtocolSheet: some View {
    VStack(spacing: 12) {
      Text("Add Protocol")
        .font(.headline)
      Text("Select a connector to enable")
        .font(.caption)
        .foregroundStyle(.secondary)

      ScrollView {
        VStack(spacing: 4) {
          ForEach(availableProtocols, id: \.self) { name in
            Button {
              addProtocol(name)
              showAddSheet = false
            } label: {
              HStack {
                Text(name)
                  .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "plus.circle")
                  .foregroundStyle(Color.tnAccent)
              }
              .padding(.vertical, 6)
              .padding(.horizontal, 12)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
          }
        }
      }
      .frame(maxHeight: 300)

      Button("Cancel") { showAddSheet = false }
        .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(width: 300)
  }

  private func addProtocol(_ connector: String) {
    APIClient.shared.addProtocol(["connector": connector]) {
      (result: Result<[String: Any], APIError>) in
      DispatchQueue.main.async {
        if case .success = result { refreshData() }
      }
    }
  }

  private func refreshData() {
    appState.onDataChanged?()
  }
}

// MARK: - Triggers View

struct TriggersView: View {
  @Bindable var appState: AppState
  @Binding var path: NavigationPath

  private let triggerCategories: [(name: String, icon: String, events: [String])] = [
    (
      "Access Control", "shield.fill",
      ["USER_NEW", "CONN_OPEN", "CONN_PLAY", "STREAM_PUSH", "LIVE_BANDWIDTH"]
    ),
    (
      "Stream Lifecycle", "play.circle.fill",
      [
        "STREAM_ADD", "STREAM_CONFIG", "STREAM_REMOVE", "STREAM_SOURCE", "STREAM_LOAD",
        "STREAM_READY", "STREAM_UNLOAD",
      ]
    ),
    (
      "Routing", "arrow.triangle.branch",
      [
        "PUSH_REWRITE", "RTMP_PUSH_REWRITE", "PUSH_OUT_START", "PLAY_REWRITE", "DEFAULT_STREAM",
      ]
    ),
    (
      "Monitoring", "chart.bar.fill",
      [
        "STREAM_BUFFER", "STREAM_END", "CONN_CLOSE", "USER_END", "RECORDING_END", "OUTPUT_END",
        "PUSH_END", "LIVE_TRACK_LIST", "INPUT_ABORT",
      ]
    ),
    (
      "System", "server.rack",
      ["SYSTEM_START", "SYSTEM_STOP", "OUTPUT_START", "OUTPUT_STOP"]
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Triggers")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("\(appState.triggerCount) trigger(s)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              path.append(Route.triggerWizard)
            } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if appState.triggers.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No triggers configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(appState.sortedTriggerNames, id: \.self) { eventName in
              if let handlers = appState.triggers[eventName] as? [[String: Any]] {
                triggerGroup(eventName: eventName, handlers: handlers)
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

  private func triggerGroup(eventName: String, handlers: [[String: Any]]) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Image(systemName: iconForEvent(eventName))
            .font(.caption)
            .foregroundStyle(Color.tnAccent)
          Text(eventName)
            .font(.subheadline.weight(.semibold))
          Spacer()
        }

        ForEach(Array(handlers.enumerated()), id: \.offset) { index, handler in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(handler["handler"] as? String ?? "Unknown")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
              HStack(spacing: 6) {
                if handler["sync"] as? Bool == true {
                  Text("Blocking")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.tnOrange.opacity(0.15))
                    .clipShape(Capsule())
                }
                let streams = handler["streams"] as? [String] ?? []
                Text(streams.isEmpty ? "All streams" : streams.joined(separator: ", "))
                  .font(.system(size: 9))
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button {
              path.append(Route.editTrigger(eventName, index))
            } label: {
              Image(systemName: "pencil")
                .font(.system(size: 10))
                .foregroundStyle(Color.tnAccent)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
            Button(role: .destructive) {
              deleteTrigger(eventName: eventName, index: index)
            } label: {
              Image(systemName: "trash")
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  private func iconForEvent(_ event: String) -> String {
    for cat in triggerCategories {
      if cat.events.contains(event) {
        return cat.icon
      }
    }
    return "bolt.fill"
  }

  private func deleteTrigger(eventName: String, index: Int) {
    var triggers = appState.triggers
    guard var handlers = triggers[eventName] as? [[String: Any]] else { return }
    handlers.remove(at: index)
    if handlers.isEmpty {
      triggers.removeValue(forKey: eventName)
    } else {
      triggers[eventName] = handlers
    }

    APIClient.shared.saveTriggers(triggers) { result in
      DispatchQueue.main.async {
        if case .success = result {
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }

}

// MARK: - Variables View

struct VariablesView: View {
  @Bindable var appState: AppState
  @State private var showAddForm = false
  @State private var newVarName = ""
  @State private var newVarValue = ""
  @State private var newVarType = "static"
  @State private var newVarCommand = ""
  @State private var newVarInterval = "0"
  @State private var isSubmitting = false

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Variables")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("\(appState.variables.count) variable(s)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              showAddForm.toggle()
            } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if showAddForm {
            addVariableForm
          }

          if appState.variables.isEmpty && !showAddForm {
            VStack(spacing: 8) {
              Image(systemName: "textformat.abc")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No custom variables")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(appState.sortedVariableNames, id: \.self) { name in
              variableRow(name: name)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var addVariableForm: some View {
    GroupBox("New Variable") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 4) {
          Text("$")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color.tnAccent)
          TextField("name", text: $newVarName)
            .textFieldStyle(.roundedBorder)
        }

        Picker("Type", selection: $newVarType) {
          Text("Static value").tag("static")
          Text("Dynamic (command/URL)").tag("dynamic")
        }
        .labelsHidden()
        .pickerStyle(.segmented)

        if newVarType == "static" {
          TextField("Value", text: $newVarValue)
            .textFieldStyle(.roundedBorder)
        } else {
          TextField("Command or URL", text: $newVarCommand)
            .textFieldStyle(.roundedBorder)
          HStack {
            Text("Check interval (s):")
              .font(.caption)
            TextField("0", text: $newVarInterval)
              .textFieldStyle(.roundedBorder)
              .frame(width: 60)
            Text("0 = once at startup")
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
          }
        }

        HStack {
          Spacer()
          Button("Cancel") {
            showAddForm = false
            resetVarForm()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button("Add") { addVariable() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newVarName.trimmed.isEmpty || isSubmitting)
        }
      }
    }
  }

  private func variableRow(name: String) -> some View {
    let value = appState.variables[name]
    return HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("$\(name)")
          .font(.system(.body, design: .monospaced, weight: .medium))
        if let dict = value as? [String: Any] {
          if let v = dict["value"] as? String, !v.isEmpty {
            Text(v)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          } else if let target = dict["target"] as? String {
            Text(target)
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        } else if let str = value as? String {
          Text(str)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      Button(role: .destructive) {
        removeVariable(name: name)
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

  private func addVariable() {
    isSubmitting = true
    var variable: [String: Any] = ["name": "$\(newVarName.trimmed)"]
    if newVarType == "static" {
      variable["value"] = newVarValue.trimmed
    } else {
      variable["target"] = newVarCommand.trimmed
      variable["interval"] = Int(newVarInterval.trimmed) ?? 0
    }
    APIClient.shared.addVariable(variable) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        if case .success = result {
          showAddForm = false
          resetVarForm()
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }

  private func removeVariable(name: String) {
    APIClient.shared.removeVariable(name: name) { result in
      DispatchQueue.main.async {
        if case .success = result {
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }

  private func resetVarForm() {
    newVarName = ""
    newVarValue = ""
    newVarType = "static"
    newVarCommand = ""
    newVarInterval = "0"
  }
}

// MARK: - External Writers View

struct ExternalWritersView: View {
  @Bindable var appState: AppState
  @State private var showAddForm = false
  @State private var newName = ""
  @State private var newCmdline = ""
  @State private var newProtocols = ""
  @State private var isSubmitting = false

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "External Writers")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Custom push target protocols (S3, etc.)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              showAddForm.toggle()
            } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if showAddForm {
            addWriterForm
          }

          if appState.externalWriters.isEmpty && !showAddForm {
            VStack(spacing: 8) {
              Image(systemName: "cloud")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No external writers configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(Array(appState.externalWriters.keys.sorted()), id: \.self) { name in
              writerRow(name: name)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var addWriterForm: some View {
    GroupBox("New External Writer") {
      VStack(alignment: .leading, spacing: 8) {
        TextField("Name", text: $newName)
          .textFieldStyle(.roundedBorder)
        TextField("Command line", text: $newCmdline)
          .textFieldStyle(.roundedBorder)
        TextField("URI protocols (comma-separated, e.g. s3,gs)", text: $newProtocols)
          .textFieldStyle(.roundedBorder)

        HStack {
          Spacer()
          Button("Cancel") {
            showAddForm = false
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button("Add") { addWriter() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
              newName.trimmed.isEmpty || newCmdline.trimmed.isEmpty
                || newProtocols.trimmed.isEmpty || isSubmitting)
        }
      }
    }
  }

  private func writerRow(name: String) -> some View {
    let writer = appState.externalWriters[name]
    return HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(.body, weight: .medium))
        if let dict = writer as? [String: Any] {
          if let cmdline = dict["cmdline"] as? String {
            Text(cmdline)
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          if let protos = dict["protocols"] as? [String] {
            Text(protos.map { $0 + "://" }.joined(separator: ", "))
              .font(.system(size: 10))
              .foregroundStyle(Color.tnAccent)
          }
        }
      }
      Spacer()
      Button(role: .destructive) {
        removeWriter(name: name)
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

  private func addWriter() {
    isSubmitting = true
    let protocols = newProtocols.trimmed.components(separatedBy: ",").map { $0.trimmed }
    let config: [String: Any] = [
      "name": newName.trimmed,
      "cmdline": newCmdline.trimmed,
      "protocols": protocols,
    ]
    APIClient.shared.addExternalWriter(config) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        if case .success = result {
          showAddForm = false
          newName = ""
          newCmdline = ""
          newProtocols = ""
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }

  private func removeWriter(name: String) {
    APIClient.shared.removeExternalWriter(name: name) { result in
      DispatchQueue.main.async {
        if case .success = result {
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }
}

// MARK: - JWK Management View

struct JWKManagementView: View {
  @Bindable var appState: AppState

  private enum AddMode: String, CaseIterable { case url, inlineKey }

  @State private var showAddForm = false
  @State private var addMode: AddMode = .url
  @State private var jwkURL = ""
  @State private var jwkJSON = ""
  @State private var streamScope = "*"
  @State private var permitViewing = true
  @State private var permitInput = true
  @State private var permitAdmin = false
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var editingIndex: Int?
  @State private var editPermitViewing = true
  @State private var editPermitInput = true
  @State private var editPermitAdmin = false
  @State private var editStreamScope = "*"
  @State private var deletingIndex: Int?

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "JSON Web Keys")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Token-based authentication for streams")
              .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { showAddForm.toggle() } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption).contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerOnHover()
          }

          if showAddForm { addJWKForm }

          if appState.jwkEntries.isEmpty {
            Text("No JWK entries configured.")
              .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
          } else {
            ForEach(Array(appState.jwkEntries.enumerated()), id: \.offset) { index, entry in
              jwkEntryRow(entry, index: index)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Entry Row

  private func jwkEntryRow(_ entry: [Any], index: Int) -> some View {
    let source = entry.first
    let permissions = entry.count > 1 ? entry[1] as? [String: Any] : nil
    let (label, typeLabel, identifier, copyText) = parseEntry(source)
    let isEditing = editingIndex == index
    let isDeleting = deletingIndex == index

    return GroupBox {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.medium)).lineLimit(1)
            Text(typeLabel).font(.system(size: 9)).foregroundStyle(.secondary)
          }
          Spacer()
          // Copy button
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
          }
          .buttonStyle(.plain).pointerOnHover()
          // Edit button
          Button {
            if isEditing {
              editingIndex = nil
            } else {
              editingIndex = index
              editPermitViewing = permissions?["output"] as? Bool ?? true
              editPermitInput = permissions?["input"] as? Bool ?? true
              editPermitAdmin = permissions?["admin"] as? Bool ?? false
              editStreamScope = permissions?["stream"] as? String ?? "*"
            }
          } label: {
            Image(systemName: isEditing ? "xmark" : "pencil")
              .font(.caption).foregroundStyle(Color.tnAccent).contentShape(Rectangle())
          }
          .buttonStyle(.plain).pointerOnHover()
          // Delete button
          Button { deletingIndex = isDeleting ? nil : index } label: {
            Image(systemName: "trash")
              .font(.caption).foregroundStyle(Color.tnRed).contentShape(Rectangle())
          }
          .buttonStyle(.plain).pointerOnHover()
        }

        // Permission badges (when not editing)
        if !isEditing, let perms = permissions {
          HStack(spacing: 6) {
            if perms["output"] as? Bool == true { permBadge("View", color: Color.tnGreen) }
            if perms["input"] as? Bool == true { permBadge("Input", color: Color.tnAccent) }
            if perms["admin"] as? Bool == true { permBadge("Admin", color: Color.tnOrange) }
            if let scope = perms["stream"] as? String, scope != "*" {
              permBadge(scope, color: Color.tnPurple)
            }
          }
        }

        // Inline delete confirmation
        if isDeleting {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.caption).foregroundStyle(Color.tnOrange)
            Text("Delete this key?").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { deletingIndex = nil }
              .buttonStyle(.bordered).controlSize(.mini)
            Button("Delete", role: .destructive) {
              deletingIndex = nil
              deleteJWK(identifier)
            }
            .buttonStyle(.borderedProminent).controlSize(.mini)
          }
        }

        // Inline edit form
        if isEditing {
          Divider()
          VStack(alignment: .leading, spacing: 4) {
            Toggle("Permit viewing", isOn: $editPermitViewing).font(.caption)
            Toggle("Permit stream input", isOn: $editPermitInput).font(.caption)
            Toggle("Permit API access", isOn: $editPermitAdmin).font(.caption)
            HStack {
              Text("Streams:").font(.caption).foregroundStyle(.secondary)
              TextField("*", text: $editStreamScope)
                .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 150)
            }
            HStack {
              Spacer()
              Button("Cancel") { editingIndex = nil }
                .buttonStyle(.bordered).controlSize(.mini)
              Button("Save") { saveEditedPermissions(entry, index: index, identifier: identifier) }
                .buttonStyle(.borderedProminent).controlSize(.mini)
            }
          }
        }
      }
    }
  }

  private func parseEntry(_ source: Any?) -> (label: String, typeLabel: String, identifier: String, copyText: String) {
    if let urlString = source as? String {
      return (urlString, "URL", urlString, urlString)
    } else if let keyObj = source as? [String: Any] {
      let kid = keyObj["kid"] as? String ?? "Inline Key"
      let kty = keyObj["kty"] as? String ?? "Key"
      let json = (try? JSONSerialization.data(withJSONObject: keyObj, options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? kid
      return (kid, kty, kid, json)
    }
    return ("Unknown", "?", "", "")
  }

  private func permBadge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9, weight: .medium))
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(color.opacity(0.2)).foregroundStyle(color)
      .clipShape(Capsule())
  }

  // MARK: - Add Form

  private var addJWKForm: some View {
    GroupBox("Add JWK") {
      VStack(alignment: .leading, spacing: 8) {
        Picker("", selection: $addMode) {
          Text("JWKS URL").tag(AddMode.url)
          Text("Inline Key").tag(AddMode.inlineKey)
        }
        .pickerStyle(.segmented).labelsHidden()

        if addMode == .url {
          TextField("https://example.com/.well-known/jwks.json", text: $jwkURL)
            .textFieldStyle(.roundedBorder)
        } else {
          Text("Paste JWK JSON (must contain 'kty' field)")
            .font(.system(size: 9)).foregroundStyle(.secondary)
          TextEditor(text: $jwkJSON)
            .font(.system(.caption, design: .monospaced))
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
        }

        VStack(alignment: .leading, spacing: 4) {
          Toggle("Permit viewing", isOn: $permitViewing).font(.caption)
          Toggle("Permit stream input", isOn: $permitInput).font(.caption)
          Toggle("Permit API access", isOn: $permitAdmin).font(.caption)
        }

        HStack {
          Text("Streams:").font(.caption).foregroundStyle(.secondary)
          TextField("* (all streams)", text: $streamScope)
            .textFieldStyle(.roundedBorder).font(.caption)
        }

        if let error = errorMessage {
          Text(error).font(.caption).foregroundColor(Color.tnRed)
        }

        HStack {
          Spacer()
          Button("Cancel") { showAddForm = false; errorMessage = nil }
            .buttonStyle(.bordered).controlSize(.small)
          Button("Add") { addJWK() }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .disabled(addFormDisabled)
        }
      }
    }
  }

  private var addFormDisabled: Bool {
    if isSubmitting { return true }
    if addMode == .url { return jwkURL.trimmed.isEmpty }
    return jwkJSON.trimmed.isEmpty
  }

  // MARK: - Actions

  private func addJWK() {
    isSubmitting = true
    errorMessage = nil
    let permissions: [String: Any] = [
      "output": permitViewing, "input": permitInput, "admin": permitAdmin,
      "stream": streamScope.trimmed.isEmpty ? "*" : streamScope.trimmed,
    ]

    let entries: [[Any]]
    if addMode == .url {
      entries = [[jwkURL.trimmed, permissions]]
    } else {
      // Parse inline JSON
      guard let data = jwkJSON.trimmed.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data)
      else {
        isSubmitting = false
        errorMessage = "Invalid JSON. Please enter a valid JWK object."
        return
      }

      // Support single key object or JWKS with "keys" array
      var keys: [[String: Any]] = []
      if let obj = parsed as? [String: Any] {
        if let keysArray = obj["keys"] as? [[String: Any]] {
          keys = keysArray
        } else {
          keys = [obj]
        }
      } else if let arr = parsed as? [[String: Any]] {
        keys = arr
      } else {
        isSubmitting = false
        errorMessage = "Expected a JSON object or array of key objects."
        return
      }

      // Validate kty field
      for key in keys {
        if key["kty"] == nil {
          isSubmitting = false
          errorMessage = "All keys must contain a 'kty' field."
          return
        }
      }

      entries = keys.map { [$0, permissions] }
    }

    APIClient.shared.addJWK(entries) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          showAddForm = false
          jwkURL = ""; jwkJSON = ""; streamScope = "*"
          addMode = .url
          appState.onDataChanged?()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func saveEditedPermissions(_ entry: [Any], index: Int, identifier: String) {
    let permissions: [String: Any] = [
      "output": editPermitViewing, "input": editPermitInput, "admin": editPermitAdmin,
      "stream": editStreamScope.trimmed.isEmpty ? "*" : editStreamScope.trimmed,
    ]

    // Re-add with updated permissions, then delete old
    let source = entry.first
    let newEntries: [[Any]] = [[source as Any, permissions]]

    APIClient.shared.deleteJWK(identifier) { deleteResult in
      if case .success = deleteResult {
        APIClient.shared.addJWK(newEntries) { addResult in
          DispatchQueue.main.async {
            editingIndex = nil
            if case .success = addResult {
              appState.onDataChanged?()
            }
          }
        }
      }
    }
  }

  private func deleteJWK(_ identifier: String) {
    APIClient.shared.deleteJWK(identifier) { result in
      DispatchQueue.main.async {
        if case .success = result { appState.onDataChanged?() }
      }
    }
  }
}

// MARK: - Stream Keys View

struct StreamKeysView: View {
  @Bindable var appState: AppState

  @State private var showAddForm = false
  @State private var newKey = ""
  @State private var selectedStream = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var deletingKey: String?

  private var streamNames: [String] {
    appState.allStreams.keys.sorted()
  }

  /// Keys grouped by stream name, sorted
  private var keysByStream: [(stream: String, keys: [String])] {
    var grouped: [String: [String]] = [:]
    for (key, stream) in appState.streamKeys {
      grouped[stream, default: []].append(key)
    }
    return grouped.sorted { $0.key < $1.key }.map { (stream: $0.key, keys: $0.value.sorted()) }
  }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Stream Keys")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Push authentication keys")
              .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { showAddForm.toggle() } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption).contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerOnHover()
          }

          if showAddForm { addKeyForm }

          if appState.streamKeys.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No stream keys configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
              Text("Stream keys authenticate push inputs without full API access.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          } else {
            ForEach(keysByStream, id: \.stream) { group in
              streamKeyGroup(group.stream, keys: group.keys)
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      if selectedStream.isEmpty, let first = streamNames.first {
        selectedStream = first
      }
    }
  }

  // MARK: - Key Group

  private func streamKeyGroup(_ stream: String, keys: [String]) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Image(systemName: "tv")
            .font(.caption).foregroundStyle(Color.tnAccent)
          Text(stream)
            .font(.caption.weight(.semibold))
          Spacer()
          Text("\(keys.count) key\(keys.count == 1 ? "" : "s")")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }

        ForEach(keys, id: \.self) { key in
          keyRow(key, stream: stream)
        }
      }
    }
  }

  private func keyRow(_ key: String, stream: String) -> some View {
    let isDeleting = deletingKey == key

    return VStack(spacing: 4) {
      HStack {
        Text(key)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(key, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerOnHover()

        Button { deletingKey = isDeleting ? nil : key } label: {
          Image(systemName: "trash")
            .font(.caption).foregroundStyle(Color.tnRed).contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerOnHover()
      }

      if isDeleting {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(Color.tnOrange)
          Text("Delete this key?").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Cancel") { deletingKey = nil }
            .buttonStyle(.bordered).controlSize(.mini)
          Button("Delete", role: .destructive) {
            deletingKey = nil
            deleteKey(key)
          }
          .buttonStyle(.borderedProminent).controlSize(.mini)
        }
      }
    }
  }

  // MARK: - Add Form

  private var addKeyForm: some View {
    GroupBox("Add Stream Key") {
      VStack(alignment: .leading, spacing: 8) {
        if streamNames.isEmpty {
          Text("No streams configured. Create a stream first.")
            .font(.caption).foregroundStyle(Color.tnOrange)
        } else {
          HStack {
            Text("Stream:").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $selectedStream) {
              ForEach(streamNames, id: \.self) { name in
                Text(name).tag(name)
              }
            }
            .labelsHidden().frame(maxWidth: 180)
          }

          HStack {
            TextField("Key (or generate random)", text: $newKey)
              .textFieldStyle(.roundedBorder).font(.caption)
            Button("Generate") { newKey = randomKey() }
              .buttonStyle(.bordered).controlSize(.small)
          }

          if let error = errorMessage {
            Text(error).font(.caption).foregroundColor(Color.tnRed)
          }

          HStack {
            Spacer()
            Button("Cancel") { showAddForm = false; errorMessage = nil; newKey = "" }
              .buttonStyle(.bordered).controlSize(.small)
            Button("Add") { addKey() }
              .buttonStyle(.borderedProminent).controlSize(.small)
              .disabled(newKey.trimmed.isEmpty || selectedStream.isEmpty || isSubmitting)
          }
        }
      }
    }
  }

  // MARK: - Actions

  private func randomKey() -> String {
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<32).map { _ in chars.randomElement()! })
  }

  private func addKey() {
    let key = newKey.trimmed
    guard !key.isEmpty, !selectedStream.isEmpty else { return }
    isSubmitting = true
    errorMessage = nil

    APIClient.shared.addStreamKeys([key: selectedStream]) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success:
          showAddForm = false
          newKey = ""
          appState.onDataChanged?()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func deleteKey(_ key: String) {
    APIClient.shared.deleteStreamKeys([key]) { result in
      DispatchQueue.main.async {
        if case .success = result { appState.onDataChanged?() }
      }
    }
  }
}

// MARK: - Cameras View

struct CamerasView: View {
  @Bindable var appState: AppState
  @State private var cameras: [String: Any] = [:]
  @State private var isLoading = true
  @State private var showAddForm = false
  @State private var newHost = ""
  @State private var newPort = "80"
  @State private var newProtocol = "ONVIF"
  @State private var newUsername = ""
  @State private var newPassword = ""

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Cameras & Devices")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Network device discovery")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button {
              showAddForm.toggle()
            } label: {
              Label("Add", systemImage: "plus.circle.fill")
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()

            Button {
              loadCameras()
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.caption)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()
          }

          if showAddForm {
            addCameraForm
          }

          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity)
              .padding(.vertical, 20)
          } else if cameras.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
              Text("No cameras discovered")
                .font(.subheadline)
                .foregroundStyle(.secondary)
              Text("Cameras are auto-discovered via ONVIF, VISCA, and NDI protocols.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
          } else {
            ForEach(Array(cameras.keys.sorted()), id: \.self) { id in
              if let cam = cameras[id] as? [String: Any] {
                cameraRow(id: id, cam: cam)
              }
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { loadCameras() }
  }

  private var addCameraForm: some View {
    GroupBox("Add Camera") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Host").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("192.168.1.100", text: $newHost)
              .textFieldStyle(.roundedBorder)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("Port").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("80", text: $newPort)
              .textFieldStyle(.roundedBorder)
              .frame(width: 60)
          }
        }

        Picker("Protocol", selection: $newProtocol) {
          Text("ONVIF").tag("ONVIF")
          Text("VISCA").tag("VISCA")
        }
        .pickerStyle(.segmented)

        HStack(spacing: 8) {
          TextField("Username", text: $newUsername)
            .textFieldStyle(.roundedBorder)
          SecureField("Password", text: $newPassword)
            .textFieldStyle(.roundedBorder)
        }

        HStack {
          Spacer()
          Button("Cancel") { showAddForm = false }
            .buttonStyle(.bordered)
            .controlSize(.small)

          Button("Add") { addCamera() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newHost.trimmed.isEmpty)
        }
      }
    }
  }

  private func cameraRow(id: String, cam: [String: Any]) -> some View {
    let name = cam["name"] as? String ?? id
    let host = cam["host"] as? String ?? "Unknown"
    let online = cam["online"] as? Bool ?? false

    return HStack(spacing: 10) {
      Circle()
        .fill(online ? Color.tnGreen : Color.gray.opacity(0.4))
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(.body, weight: .medium))
        HStack(spacing: 6) {
          Text(host)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
          if let manufacturer = cam["manufacturer"] as? String {
            Text(manufacturer)
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
          }
        }
      }

      Spacer()

      Button {
        createStreamFromCamera(id: id, cam: cam)
      } label: {
        Image(systemName: "plus.circle")
          .font(.caption)
          .foregroundStyle(Color.tnAccent)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()
      .help("Add as stream")

      Button(role: .destructive) {
        removeCamera(id: id)
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

  private func loadCameras() {
    isLoading = true
    APIClient.shared.listCameras { result in
      DispatchQueue.main.async {
        isLoading = false
        if case .success(let data) = result {
          cameras = data["camera_list"] as? [String: Any] ?? [:]
        }
      }
    }
  }

  private func addCamera() {
    var params: [String: Any] = [
      "host": newHost.trimmed,
      "port": Int(newPort.trimmed) ?? 80,
      "protocol": newProtocol,
    ]
    if !newUsername.isEmpty { params["username"] = newUsername }
    if !newPassword.isEmpty { params["password"] = newPassword }

    APIClient.shared.updateCamera(params) { result in
      DispatchQueue.main.async {
        if case .success = result {
          showAddForm = false
          newHost = ""
          newPort = "80"
          newUsername = ""
          newPassword = ""
          loadCameras()
        }
      }
    }
  }

  private func removeCamera(id: String) {
    APIClient.shared.removeCamera(id: id) { result in
      DispatchQueue.main.async {
        if case .success = result { loadCameras() }
      }
    }
  }

  private func createStreamFromCamera(id: String, cam: [String: Any]) {
    APIClient.shared.createStreamFromCamera(["id": id]) { result in
      DispatchQueue.main.async {
        if case .success = result {
          (NSApp.delegate as? AppDelegate)?.refreshAllData()
        }
      }
    }
  }
}

// MARK: - Embed URLs View

struct EmbedURLsView: View {
  @Bindable var appState: AppState
  let streamName: String

  @State private var copied: String?

  /// Get the port for a connector, checking config first, then capabilities default.
  private func portForConnector(_ connectorName: String) -> Int? {
    // Check if explicitly set in protocol config
    for proto in appState.configuredProtocols {
      if let c = proto["connector"] as? String, c == connectorName,
         let port = proto["port"] as? Int {
        return port
      }
    }
    // Fall back to default from capabilities
    if let connInfo = appState.availableConnectors[connectorName] as? [String: Any],
       let optional = connInfo["optional"] as? [String: Any],
       let portInfo = optional["port"] as? [String: Any],
       let defaultPort = portInfo["default"] as? Int {
      return defaultPort
    }
    return nil
  }

  private var httpPort: Int {
    portForConnector("HTTP") ?? portForConnector("HTTPS") ?? 8080
  }

  var body: some View {
    VStack(spacing: 0) {
      NavHeader(title: "Embed & URLs")
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Quick URLs
          GroupBox("Playback URLs") {
            VStack(alignment: .leading, spacing: 8) {
              urlRow("HTML Page", url: "http://localhost:\(httpPort)/\(streamName).html")
              urlRow("JSON Info", url: "http://localhost:\(httpPort)/json_\(streamName).js")
              urlRow("JS Info", url: "http://localhost:\(httpPort)/info_\(streamName).js")
            }
          }

          // Protocol-specific URLs
          GroupBox("Protocol URLs") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(protocolURLs, id: \.protocol) { item in
                urlRow(item.protocol, url: item.url)
              }
              if protocolURLs.isEmpty {
                Text("Enable protocols to see playback URLs")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          // Embed code
          GroupBox("Embed Code") {
            VStack(alignment: .leading, spacing: 8) {
              let embedCode = """
                <script src="http://localhost:\(httpPort)/player.js"></script>
                <script>
                  mistPlay("\(streamName)", {target: document.getElementById("player")});
                </script>
                <div id="player"></div>
                """

              Text(embedCode)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

              Button {
                copyToClipboard(embedCode, label: "embed")
              } label: {
                Label(
                  copied == "embed" ? "Copied!" : "Copy Embed Code",
                  systemImage: copied == "embed" ? "checkmark" : "doc.on.doc"
                )
                .font(.caption)
                .contentShape(Rectangle())
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .pointerOnHover()
            }
          }
        }
        .padding(16)
      }
    }
    .navigationBarBackButtonHidden(true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func urlRow(_ label: String, url: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
        Text(url)
          .font(.system(size: 10, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Spacer()
      Button {
        copyToClipboard(url, label: label)
      } label: {
        Image(systemName: copied == label ? "checkmark" : "doc.on.doc")
          .font(.caption)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointerOnHover()
    }
  }

  private func copyToClipboard(_ text: String, label: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copied = label
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      if copied == label { copied = nil }
    }
  }

  private struct ProtocolURL {
    let `protocol`: String
    let url: String
  }

  private var protocolURLs: [ProtocolURL] {
    var urls: [ProtocolURL] = []
    let hp = httpPort

    for proto in appState.configuredProtocols {
      guard let connector = proto["connector"] as? String,
            appState.normalizeOnlineState(proto["online"]) == 1
      else { continue }

      let port = proto["port"] as? Int ?? portForConnector(connector) ?? 0
      guard port > 0 else { continue }

      let upper = connector.uppercased()

      // Standalone protocols with their own port
      if upper == "RTMP" {
        urls.append(ProtocolURL(protocol: "RTMP", url: "rtmp://localhost:\(port)/play/\(streamName)"))
      }
      if upper == "RTSP" {
        urls.append(ProtocolURL(protocol: "RTSP", url: "rtsp://localhost:\(port)/\(streamName)"))
      }
      if upper == "TSSRT" {
        urls.append(ProtocolURL(protocol: "SRT", url: "srt://localhost:\(port)?streamid=\(streamName)"))
      }
      if upper == "DTSC" {
        urls.append(ProtocolURL(protocol: "DTSC", url: "dtsc://localhost:\(port)/\(streamName)"))
      }
    }

    // HTTP-based protocols all share the HTTP port
    let enabledConnectors = Set(appState.configuredProtocols.compactMap { proto -> String? in
      guard let c = proto["connector"] as? String,
            appState.normalizeOnlineState(proto["online"]) == 1
      else { return nil }
      return c.uppercased()
    })

    if enabledConnectors.contains("HLS") || enabledConnectors.contains("HTTP") {
      urls.append(ProtocolURL(protocol: "HLS", url: "http://localhost:\(hp)/hls/\(streamName)/index.m3u8"))
    }
    if enabledConnectors.contains("CMAF") {
      urls.append(ProtocolURL(protocol: "DASH", url: "http://localhost:\(hp)/cmaf/\(streamName)/index.mpd"))
      urls.append(ProtocolURL(protocol: "CMAF/HLS", url: "http://localhost:\(hp)/cmaf/\(streamName)/index.m3u8"))
    }
    if enabledConnectors.contains("EBML") {
      urls.append(ProtocolURL(protocol: "MKV", url: "http://localhost:\(hp)/\(streamName).webm"))
    }
    if enabledConnectors.contains("MP4") {
      urls.append(ProtocolURL(protocol: "MP4", url: "http://localhost:\(hp)/\(streamName).mp4"))
    }
    if enabledConnectors.contains("FLV") {
      urls.append(ProtocolURL(protocol: "FLV", url: "http://localhost:\(hp)/\(streamName).flv"))
    }
    if enabledConnectors.contains("WEBRTC") {
      urls.append(ProtocolURL(protocol: "WebRTC", url: "http://localhost:\(hp)/webrtc/\(streamName)"))
    }

    // Deduplicate by protocol name
    var seen = Set<String>()
    return urls.filter { seen.insert($0.protocol).inserted }
  }
}
