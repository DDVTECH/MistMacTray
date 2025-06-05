# MistTray

<div align="center">

![MistTray Icon](Assets.xcassets/AppIcon.appiconset/256-mac.png)

**A beautiful, native macOS system tray interface for MistServer**

[![Release](https://img.shields.io/github/v/release/DDVTECH/MistMacTray)](https://github.com/DDVTECH/MistMacTray/releases)
[![License](https://img.shields.io/github/license/DDVTECH/MistMacTray)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-10.15+-blue)](https://www.apple.com/macos/)

</div>

## Overview

MistTray provides a clean, intuitive system tray interface for managing your MistServer media streaming platform directly from your macOS menu bar. No more command-line complexity - control streams, pushes, clients, and server configuration with simple point-and-click operations.


## ⚠️ HERE BE DRAGONS ⚠️

**This is a vibe-coded work in progress.** Expect broken buttons, missing data, stale data or other nice issues.

If you don't need a Tray icon to manage your Mist instance, take a look at the [bare, Homebrew MistServer edition](https://github.com/DDVTECH/homebrew-mistserver) here.
---

## ✨ Features

### 🎛️ **Stream Management**
- Create, edit, and delete streams with visual dialogs
- Monitor stream status (online/offline) and viewer counts
- Real-time bandwidth and connection statistics
- Stream tagging and organization
- One-click stream "nuking" for emergency stops

### 📤 **Push Management**  
- Start and stop RTMP/SRT pushes to external platforms
- Auto-push rules for automated stream forwarding
- Push status monitoring and error handling
- Configurable push settings (bandwidth limits, retry logic)

### 👥 **Client Management**
- View all connected clients in real-time
- Disconnect individual clients or kick all viewers from a stream
- Force client re-authentication
- Session tagging for advanced client management

### ⚙️ **Server Configuration**
- Complete MistServer configuration through GUI
- Protocol management (enable/disable RTMP, HLS, WebRTC, etc.)
- Configuration backup and restore
- Factory reset functionality
- Real-time server statistics and monitoring

### 🔄 **Unified State Management**
- Single API call consolidates all server data
- Consistent menu state across all operations
- Real-time updates every 10 seconds
- Automatic server status detection

## 📦 Installation

### 🍺 Option 1: Homebrew (Recommended)

The easiest way to install and keep MistTray updated:

```bash
# One tap for the complete MistServer ecosystem
brew tap ddvtech/mistserver

# Install MistServer (streaming engine)
brew install mistserver

# Install MistTray (GUI management app)  
brew install --cask mistmactray

# Or install everything at once
brew bundle install --file=- <<EOF
tap "ddvtech/mistserver"
brew "mistserver"
cask "mistmactray"
EOF
```

**Benefits:**
- ✅ Automatic updates with `brew upgrade --cask mistmactray`
- ✅ Clean uninstall with `brew uninstall --cask mistmactray`
- ✅ Handles dependencies automatically
- ✅ Code-signed and notarized builds

### 📦 Option 2: Direct Download

For users who prefer manual installation:

1. **Download** the latest `MistTray-vX.X.X.dmg` from [Releases](https://github.com/DDVTECH/MistMacTray/releases)
2. **Open** the DMG and drag MistTray.app to your Applications folder
3. **Install MistServer** separately:
   ```bash
   brew tap ddvtech/mistserver
   brew install mistserver
   ```
4. **Launch** MistTray from Applications or Spotlight

## 🚀 Quick Start

1. **Start MistServer** (if not already running):
   ```bash
   brew services start mistserver
   ```

2. **Launch MistTray** - it will appear in your menu bar with the MistServer icon

3. **Access the Web UI** - Click "🌐 Open Web UI" for advanced configuration

4. **Create your first stream** - Use "➕ Create New Stream" in the Streams menu

5. **Monitor everything** - All server stats, streams, and clients update automatically

## 🎯 Usage

### Menu Structure

```
🟢 MistServer: Running • 2 streams • 15 viewers • Brew
├── 🌐 Open Web UI
├── ⏹ Stop MistServer
├── 🔄 Restart Server
├── 📺 Streams (2)
│   ├── ➕ Create New Stream
│   ├── 📺 live_stream
│   │   ├── 🟢 Online • 📡 rtmp://input
│   │   ├── ✏️ Edit Stream
│   │   ├── 🏷️ Manage Tags
│   │   ├── 💥 Nuke Stream
│   │   └── 🗑 Delete Stream
│   └── 📺 backup_stream
├── 📤 Pushes (1)
│   ├── ➕ Start New Push
│   ├── 🔧 Manage Auto-Push Rules
│   └── 📤 live_stream → YouTube
├── 👥 Clients (15)
│   ├── 📺 live_stream (12)
│   ├── 📺 backup_stream (3)
│   └── 🛠 Session Management
├── 🔌 Protocols
├── 📊 System Monitoring
├── ⚙️ Configuration
└── 🔧 Preferences
```

### Key Operations

- **Stream Control**: Create streams with custom sources, monitor status, manage tags
- **Push Management**: Forward streams to YouTube, Twitch, or custom RTMP endpoints
- **Client Monitoring**: See who's watching, disconnect problematic clients
- **Configuration**: Backup/restore settings, manage protocols, factory reset

## 🛠️ Development

### Prerequisites

- **Xcode 15+** with macOS SDK
- **macOS 10.15+** for development and testing
- **MistServer** installed locally for testing

### Building from Source

```bash
# Clone the repository
git clone https://github.com/DDVTECH/MistMacTray.git
cd MistMacTray

# Open in Xcode
open MistTray.xcodeproj

# Or build from command line
xcodebuild -project MistTray.xcodeproj -scheme MistTray -configuration Release build
```

## 🤝 Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/DDVTECH/MistMacTray/issues)
- **MistServer**: For MistServer-specific questions, visit [MistServer Documentation](https://docs.mistserver.org/)
