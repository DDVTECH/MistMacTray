//
//  ConfigurationManager.swift
//  MistTray
//

import Foundation

class ConfigurationManager {
  static let shared = ConfigurationManager()

  private init() {}

  // MARK: - Configuration Operations

  func loadConfiguration(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    print("📥 Loading configuration from server...")

    APIClient.shared.fetchConfiguration { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let config):
          print("✅ Configuration loaded successfully")
          completion(.success(config))
        case .failure(let error):
          print("❌ Failed to load configuration: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func saveConfiguration(completion: @escaping (Result<Void, APIError>) -> Void) {
    print("💾 Saving configuration to server...")

    APIClient.shared.saveConfiguration { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Configuration saved successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Failed to save configuration: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  func backupConfiguration(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
    print("📦 Backing up configuration to: \(url.path)")

    APIClient.shared.backupConfiguration { result in
      switch result {
      case .success(let configData):
        do {
          let jsonData = try JSONSerialization.data(
            withJSONObject: configData, options: .prettyPrinted)
          try jsonData.write(to: url)
          print("✅ Configuration backup saved successfully")
          DispatchQueue.main.async {
            completion(.success(()))
          }
        } catch {
          print("❌ Failed to write backup file: \(error)")
          DispatchQueue.main.async {
            completion(.failure(error))
          }
        }
      case .failure(let error):
        print("❌ Failed to backup configuration: \(error)")
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func restoreConfiguration(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
    print("📥 Restoring configuration from: \(url.path)")

    do {
      let jsonData = try Data(contentsOf: url)
      let configData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

      guard let config = configData else {
        completion(.failure(ConfigurationError.invalidBackupFile))
        return
      }

      APIClient.shared.restoreConfiguration(config) { result in
        DispatchQueue.main.async {
          switch result {
          case .success:
            print("✅ Configuration restored successfully")
            completion(.success(()))
          case .failure(let error):
            print("❌ Failed to restore configuration: \(error)")
            completion(.failure(error))
          }
        }
      }
    } catch {
      print("❌ Failed to read backup file: \(error)")
      completion(.failure(error))
    }
  }

  func processConfigurationExport(
    _ configData: [String: Any], to url: URL, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("📤 Exporting configuration with metadata...")

    let exportData: [String: Any] = [
      "export_timestamp": ISO8601DateFormatter().string(from: Date()),
      "export_version": "1.0",
      "mistserver_config": configData,
    ]

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
      try jsonData.write(to: url)
      print("✅ Configuration exported successfully")
      completion(.success(()))
    } catch {
      print("❌ Failed to export configuration: \(error)")
      completion(.failure(error))
    }
  }

  func saveConfigurationExport(
    configData: [String: Any], completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DialogManager.shared.showExportConfigurationDialog { url in
      guard let exportURL = url else {
        completion(.failure(ConfigurationError.exportCancelled))
        return
      }

      self.processConfigurationExport(configData, to: exportURL, completion: completion)
    }
  }

  func performFactoryReset(completion: @escaping (Result<Void, APIError>) -> Void) {
    print("🏭 Performing factory reset...")

    // Confirm with user first
    let confirmed = DialogManager.shared.confirmFactoryReset()
    guard confirmed else {
      completion(.failure(.invalidRequest))
      return
    }

    // Perform factory reset by restoring empty configuration
    let emptyConfig: [String: Any] = [:]
    APIClient.shared.restoreConfiguration(emptyConfig) { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          print("✅ Factory reset completed successfully")
          completion(.success(()))
        case .failure(let error):
          print("❌ Factory reset failed: \(error)")
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Configuration Validation

  func validateConfiguration(_ config: [String: Any]) -> Bool {
    // Basic validation - check for required sections
    let requiredSections = ["streams", "protocols"]

    for section in requiredSections {
      if config[section] == nil {
        print("⚠️ Configuration missing required section: \(section)")
        return false
      }
    }

    print("✅ Configuration validation passed")
    return true
  }

  // MARK: - Protocol Configuration

  func fetchProtocolConfig(completion: @escaping (Result<[String: Any], APIError>) -> Void) {
    APIClient.shared.fetchProtocolConfig(completion: completion)
  }

  func performProtocolAction(
    apiCall: [String: Any], completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.performProtocolAction(apiCall: apiCall) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Push Settings

  func applyPushSettings(
    maxSpeed: Int, waitTime: Int, autoRestart: Bool,
    completion: @escaping (Result<Void, APIError>) -> Void
  ) {
    APIClient.shared.applyPushSettings(
      maxSpeed: maxSpeed, waitTime: waitTime, autoRestart: autoRestart
    ) { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Server Management

  func gracefulShutdown(completion: @escaping (Result<Void, APIError>) -> Void) {
    APIClient.shared.gracefulShutdown { result in
      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  // MARK: - Configuration Utilities

  func getConfigurationSummary(_ config: [String: Any]) -> ConfigurationSummary {
    let streamCount = (config["streams"] as? [String: Any])?.count ?? 0
    let pushCount = (config["push"] as? [String: Any])?.count ?? 0
    let protocolCount = (config["protocols"] as? [String: Any])?.count ?? 0

    return ConfigurationSummary(
      streamCount: streamCount,
      pushCount: pushCount,
      protocolCount: protocolCount,
      version: config["version"] as? String ?? "Unknown",
      lastModified: Date()
    )
  }

  // MARK: - Configuration Export with Metadata

  func exportConfigurationWithMetadata(completion: @escaping (Result<Void, Error>) -> Void) {
    // First backup the configuration
    APIClient.shared.backupConfiguration { result in
      switch result {
      case .success(let configData):
        // Save the configuration with metadata
        self.saveConfigurationExport(configData: configData) { saveResult in
          completion(saveResult)
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }
}

// MARK: - Supporting Types

struct ConfigValidationResult {
  let isValid: Bool
  let errors: [String]
  let warnings: [String]
}

struct ConfigurationSummary {
  let streamCount: Int
  let pushCount: Int
  let protocolCount: Int
  let version: String
  let lastModified: Date

  var description: String {
    return "Streams: \(streamCount), Pushes: \(pushCount), Protocols: \(protocolCount)"
  }
}

// MARK: - Configuration Errors

enum ConfigurationError: Error, LocalizedError {
  case invalidBackupFile
  case exportCancelled
  case validationFailed

  var errorDescription: String? {
    switch self {
    case .invalidBackupFile:
      return "Invalid backup file format"
    case .exportCancelled:
      return "Export was cancelled by user"
    case .validationFailed:
      return "Configuration validation failed"
    }
  }
}
