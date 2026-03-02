# MistTray

A native macOS menu bar app for managing [MistServer](https://mistserver.org). Start/stop the server, manage streams, monitor clients, control pushes, and handle configuration — all from the menu bar.

**MistServer is required.** MistTray talks to MistServer's JSON API on `localhost:4242`. It is a companion GUI, not a standalone app.

## Install

### Homebrew (recommended)

```bash
brew tap ddvtech/mistserver
brew install --cask misttray
```

This also installs MistServer as a dependency.

### Direct download

Grab the latest `.dmg` from [Releases](https://github.com/DDVTECH/MistMacTray/releases), drag MistTray.app to Applications, and install MistServer separately:

```bash
brew tap ddvtech/mistserver
brew install mistserver
brew services start mistserver
```

### Build from source

```bash
git clone https://github.com/DDVTECH/MistMacTray.git
cd MistMacTray
xcodebuild -project MistTray.xcodeproj -scheme MistTray -configuration Debug \
  -derivedDataPath build/ CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/MistTray.app
```

Requires Xcode 16+ and macOS 12.0+.

## Features

- **Server control** — start, stop, restart MistServer via `brew services`
- **Streams** — list, create, edit, delete streams
- **Pushes** — start/stop pushes to external platforms (RTMP, SRT, etc.)
- **Clients** — see connected viewers per stream, disconnect or kick
- **Configuration** — backup, restore, save, factory reset
- Auto-refreshes every 10 seconds while MistServer is running

## Releasing

Releases are automated via GitHub Actions. The workflow archives, signs, notarizes, and publishes a `.zip` (for Homebrew) and `.dmg` (for direct download) to GitHub Releases.

To release a new version:

```bash
git tag v1.0.1
git push origin v1.0.1
```

The git tag version is automatically injected into the app bundle — no need to manually edit version numbers in the Xcode project.

### Required GitHub secrets

Set these in **Settings > Secrets and variables > Actions**:

| Secret | What it is |
|---|---|
| `CERTIFICATES_P12` | Base64-encoded Developer ID Application `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `CERTIFICATES_P12_PASSWORD` | Password used when exporting the `.p12` |
| `TEAM_ID` | 10-character Apple Developer Team ID |
| `DEVELOPER_ID` | Certificate common name, e.g. `DDVTech (AB12C3D4E5)` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APP_SPECIFIC_PASSWORD` | App-specific password from [appleid.apple.com](https://appleid.apple.com) |

Also enable **Settings > Actions > General > Workflow permissions > Read and write permissions** so the workflow can upload release assets.

### Creating the Developer ID certificate

If you haven't created the certificate yet:

1. Open **Keychain Access** > Certificate Assistant > Request a Certificate from a Certificate Authority (save to disk)
2. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) > click **+** > select **Developer ID Application** > upload the CSR
3. Download and double-click to install the certificate
4. In Keychain Access, right-click the installed certificate > Export > save as `.p12` with a password
5. Base64 encode it: `base64 -i DeveloperID.p12 | pbcopy`
6. Paste into the `CERTIFICATES_P12` GitHub secret

## License

[MIT](LICENSE)
