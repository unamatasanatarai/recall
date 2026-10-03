# Recall

![Swift](https://img.shields.io/badge/Swift-5.7-orange.svg)
![macOS](https://img.shields.io/badge/macOS-12.3%2B-blue.svg)
![ScreenCaptureKit](https://img.shields.io/badge/framework-ScreenCaptureKit-purple.svg)
![SwiftUI](https://img.shields.io/badge/framework-SwiftUI-blue.svg)
![License](https://img.shields.io/badge/license-GPL--2.0-green.svg)
![Build](https://img.shields.io/badge/build-Makefile-brightgreen.svg)

Recall is a lightweight macOS menu bar utility that provides continuous, background screen recording using native macOS capture frameworks (`CGDisplayStream` and `ScreenCaptureKit`). It maintains a rolling ring-buffer of high-efficiency H.264 video chunks with automated retention management based on user-defined storage and time limits.

By dragging downward from the menu bar icon, users can interactively select a retrospective timeframe and instantly export high-quality video clips. The app utilizes single-pass `ffmpeg` concatenation and trimming with an automatic `AVFoundation` fallback, delivering fast clip exports without manual video editing.

## Features

- **Continuous Background Capture**: Records the main display at 30 FPS using `CGDisplayStream` and hardware-accelerated H.264 encoding via `AVAssetWriter` into 30-second rolling `.mp4` chunks.
- **Zero-Copy Frame Pipeline**: Employs direct `IOSurface` pixel buffer binding (`CVPixelBufferCreateWithIOSurface`) for GPU-to-buffer frame pass-through, backed by a `CIContext` rendering fallback.
- **Interactive Drag-to-Export HUD**: Visualizes retrospective recording selection via a custom translucent glassmorphism HUD beam overlay (`OverlayHUDWindow`) with real-time time offset calculations (`HUDTimeBadge`).
- **Ring-Buffer Retention & Storage Limits**: `ChunkManager` automatically enforces maximum storage size and retention duration thresholds, purging the oldest video chunks when limits are reached.
- **Single-Pass Lossless Clip Export**: Merges and trims selected chunks using `ffmpeg` (`concatAndTrim`), falling back to `AVMutableComposition` and `AVAssetExportSession` when `ffmpeg` is unavailable.
- **TCC Permission Preservation**: Incremental compilation in `build.sh` checks source timestamps against compiled binaries to skip re-signing when code is unchanged, preventing macOS Screen Recording permission invalidation.
- **Automated DMG Packaging**: Custom DMG generator (`create_dmg.sh` and `create_dmg_background.swift`) produces a styled installer volume with custom background graphics and pixel-aligned Finder icon placement.
- **Automated Release Workflow**: `release.sh` automates version bumping, changelog extraction from git history, unit test verification, DMG packaging, git tagging, and GitHub release publishing (`gh release create`).
- **Preferences & Analytics Panel**: SwiftUI interface for modifying export destinations, storage limits, and inspecting active clip metrics and disk usage in real time.

## Tech Stack

- **Language**: Swift 5.7
- **Platform**: macOS 12.3+ (x86_64 architecture)
- **Frameworks**: ScreenCaptureKit, AVFoundation, CoreMedia, CoreVideo, CoreImage, CoreGraphics, SwiftUI, AppKit
- **External Tools**: `ffmpeg` (optional system binary for fast video concatenation and trimming), `gh` (optional GitHub CLI for release publishing)
- **Build & Packaging**: Makefile, Bash (`build.sh`, `create_dmg.sh`, `release.sh`, `test.sh`), `swiftc`, `codesign`, `hdiutil` (DMG generation)
- **Testing**: Custom Swift unit test runner with protocol-based dependency injection (`FileSystemProvider`, `StorageConfig`, `FFmpegRunner`, `VideoMetadataProvider`)

## Project Structure

```text
Sources/Recall/
├── RecallApp.swift                   Application delegate and lifecycle management
├── RecorderEngine.swift              CGDisplayStream capture and AVAssetWriter H.264 encoding pipeline
├── ChunkManager.swift                Chunk storage persistence, retention enforcement, and video export
├── MenuBarManager.swift              NSStatusItem setup, custom menu bar icon, and drag gesture tracking
├── OverlayHUDWindow.swift            Full-screen translucent glassmorphism HUD beam overlay
├── SettingsManager.swift             UserDefaults persistence for export paths and storage thresholds
├── SettingsView.swift                SwiftUI preferences panel for storage and location configuration
├── SettingsWindowController.swift   NSWindowController manager for preferences window
└── Protocols.swift                   Abstraction protocols for file system, video metadata, and ffmpeg execution

Tests/RecallTests/
├── TestRunner.swift                  Standalone unit test runner entry point
├── ChunkManagerTests.swift           Unit tests for retention limit enforcement and purging
├── SettingsManagerTests.swift        Unit tests for settings calculations and defaults
└── Mocks.swift                       In-memory mocks for unit test isolation

Resources/
├── AppIcon.icns / AppIcon.png        Application icon assets
├── create_dmg_background.swift       Swift script generating custom DMG background graphics
└── dmg_background.png                Generated background image for installer volume

build.sh                              Compilation, ad-hoc signing, and Info.plist generation script
create_dmg.sh                         Styled DMG installer packaging script
release.sh                            Automated release, changelog, tagging, and GitHub publishing script
test.sh                               Unit test compilation and execution script
Makefile                              Build automation targets (help, build, test, dmg, release, run, launch, revoke, clean)
Package.swift                         Swift Package Manager manifest
VERSION                               Project version string
```

## Installation

### Prerequisites

- macOS 12.3 or later
- Xcode Command Line Tools (`swiftc`, `xcrun`, `codesign`)
- Optional: `ffmpeg` (installed via Homebrew or available in PATH)

### Building from Source

Clone the repository and compile the application bundle using `make`:

```bash
git clone https://github.com/unamatasanatarai/recall.git
cd recall
make build
```

The compiled application bundle will be created at `build/Recall.app`.

## Usage

### Running the Application

Launch the compiled app bundle:

```bash
make run
```

To launch an existing build without recompiling (preserving TCC Screen Capture permissions):

```bash
make launch
```

### Exporting Video Clips

1. Click and hold the Recall menu bar icon.
2. Drag downward to select the desired retrospective clip duration (in 30-second steps up to total recorded duration).
3. Release the mouse button. The clip will be exported to your designated export directory (`Recall_yyyy-MM-dd_HH-mm-ss.mp4`), and the file will be selected in Finder.

### Packaging a DMG

To create a styled `.dmg` disk image:

```bash
make dmg
```

The output file will be written to `build/Recall-v1.0.0.dmg`.

### Automated Release Workflow

To bump version, extract changelog from git commits, run tests, package DMG, tag git, and publish a release to GitHub:

```bash
# Auto-bump patch version
make release

# Specify a target version
make release VERSION=1.1.0
```

### Resetting TCC Permissions

If screen recording permissions need to be reset in macOS System Settings:

```bash
make revoke
```

## Configuration

Configuration values are persisted via `UserDefaults` and editable through the Preferences window (`Cmd + ,` or right-clicking the menu bar icon):

- **Export Location**: Directory where exported `.mp4` clips are saved. (Default: `~/Movies/Recall-exports`)
- **Max Size (MB)**: Maximum disk space for stored video chunks. (Default: `1000 MB`)
- **Max Time (Minutes)**: Maximum historical duration retained in memory/disk. (Default: `60 Minutes`)

### Cache Directory & Logs

- Video chunks are stored in `~/.cache/recall/chunks/` (or `$XDG_CACHE_HOME/recall/chunks/`).
- Runtime debug logs are written to `~/.cache/recall/recall_debug.log` (automatically rotated when exceeding 10 MB).

## Media Assets

![Recall App Icon](Resources/AppIcon.png)

## Tests

The project includes unit tests covering `ChunkManager` purging logic and `SettingsManager` calculations.

Run the test suite using `Makefile`:

```bash
make test
```

Or execute the test script directly:

```bash
./test.sh
```

## License

This project is licensed under the terms of the GNU General Public License v2.0. See the [LICENSE](LICENSE) file for details.
