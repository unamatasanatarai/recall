import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager = SettingsManager.shared
    @ObservedObject var windowController: SettingsWindowController = SettingsWindowController.shared
    var chunkStore: ChunkStore = ChunkManager.shared
    var openPanelPresenter: OpenPanelPresenter = DefaultOpenPanelPresenter()
    var onPurgeRecordings: () -> Void = { MenuBarManager.shared.purgeRecordings() }
    @State private var currentDurationText: String = ""
    @State private var currentSizeBytesText: String = ""
    @State private var totalChunksCount: Int = 0

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()


    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                // Invisible Escape Key Shortcut to close Preferences
                Button("") {
                    SettingsWindowController.shared.closeWindow()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
                .frame(width: 0, height: 0)

                // Invisible Cmd+Q Key Shortcut for double Cmd+Q handling
                Button("") {
                    windowController.handleCmdQ()
                }
                .keyboardShortcut("q", modifiers: [.command])
                .hidden()
                .frame(width: 0, height: 0)

            // Card 1: Export Location Settings + Logo (Right)
            HStack(spacing: 8) {
                Text("Export Location:")
                    .font(.system(size: 13, weight: .semibold))

                Button(action: {
                    chooseDirectory()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text(settings.exportsDirectoryPath)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Click to change export folder")

                // Reset export location 🔄
                Button(action: {
                    settings.exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Reset export location to default")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // Card 2: Storage & Retention Limits
            VStack(alignment: .leading, spacing: 12) {
                // Row 1: Max Size
                HStack {
                    HStack(spacing: 6) {
                        Text("Max Size:")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 68, alignment: .leading)

                        TextField("", value: $settings.maxStorageMB, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)

                        Text("MB")
                            .font(.system(size: 13))
                            .frame(width: 54, alignment: .leading)

                        Stepper("", value: $settings.maxStorageMB, in: ConfigManager.shared.minStorageMB...ConfigManager.shared.maxAllowedStorageMB, step: ConfigManager.shared.stepStorageMB)
                            .labelsHidden()

                        // Reset size 🔄
                        Button(action: {
                            resetStorageMB()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Reset Max Size to default (\(ConfigManager.shared.defaultMaxStorageMB) MB)")
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(currentSizeBytesText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)

                        Button(action: {
                            onPurgeRecordings()
                        }) {
                            Text("(\(totalChunksCount) clips)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .underline()
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Click to purge all stored recordings")
                    }
                }

                Divider()

                // Row 2: Max Time
                HStack {
                    HStack(spacing: 6) {
                        Text("Max Time:")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 68, alignment: .leading)

                        TextField("", value: $settings.maxStorageMinutes, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)

                        Text("Minutes")
                            .font(.system(size: 13))
                            .frame(width: 54, alignment: .leading)

                        Stepper("", value: $settings.maxStorageMinutes, in: ConfigManager.shared.minStorageMinutes...ConfigManager.shared.maxAllowedStorageMinutes, step: ConfigManager.shared.stepStorageMinutes)
                            .labelsHidden()

                        // Reset time 🔄
                        Button(action: {
                            resetStorageMinutes()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Reset Max Time to default (\(ConfigManager.shared.defaultMaxStorageMinutes) Minutes)")
                    }

                    Spacer()

                    Text(currentDurationText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .padding(.top, 12)
        .padding(.bottom, 22)
        .padding(.horizontal, 18)

        if windowController.isQuitPromptVisible {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
                Text("Press again to quit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.96))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
            )
            .padding(.bottom, 10)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
    .frame(width: ConfigManager.shared.preferencesWindowWidth, height: ConfigManager.shared.preferencesWindowHeight)
    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: windowController.isQuitPromptVisible)
    .onAppear {
        updateUsageStats()
    }
    .onReceive(timer) { _ in
        updateUsageStats()
    }
}

    func chooseDirectory() {
        openPanelPresenter.chooseDirectory { path in
            if let path = path {
                settings.exportsDirectoryPath = path
            }
        }
    }

    func resetStorageMB() {
        settings.maxStorageMB = ConfigManager.shared.defaultMaxStorageMB
    }

    func resetStorageMinutes() {
        settings.maxStorageMinutes = ConfigManager.shared.defaultMaxStorageMinutes
    }

    private func updateUsageStats() {
        let chunks = chunkStore.chunks
        totalChunksCount = chunks.count
        
        let totalSecs = chunkStore.totalRecordedDuration
        let mins = Int(totalSecs) / 60
        let secs = Int(totalSecs) % 60
        currentDurationText = String(format: "%dm %02ds / %dm max", mins, secs, settings.maxStorageMinutes)

        let totalBytes = chunks.reduce(0) { $0 + $1.sizeBytes }
        let mb = Double(totalBytes) / (1024.0 * 1024.0)
        currentSizeBytesText = String(format: "%.1f MB / %d MB max", mb, settings.maxStorageMB)
    }
}
