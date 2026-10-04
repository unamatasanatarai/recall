import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager = SettingsManager.shared
    var chunkStore: ChunkStore = ChunkManager.shared
    var openPanelPresenter: OpenPanelPresenter = DefaultOpenPanelPresenter()
    var onPurgeRecordings: () -> Void = { MenuBarManager.shared.purgeRecordings() }
    @State private var currentDurationText: String = ""
    @State private var currentSizeBytesText: String = ""
    @State private var totalChunksCount: Int = 0

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Invisible Escape Key Shortcut to close Preferences
            Button("") {
                SettingsWindowController.shared.closeWindow()
            }
            .keyboardShortcut(.escape, modifiers: [])
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

                        Stepper("", value: $settings.maxStorageMB, in: 50...100000, step: 50)
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
                        .help("Reset Max Size to default (\(SettingsManager.defaultMaxStorageMB) MB)")
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

                        Stepper("", value: $settings.maxStorageMinutes, in: 5...10080, step: 15)
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
                        .help("Reset Max Time to default (\(SettingsManager.defaultMaxStorageMinutes) Minutes)")
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
        .frame(width: 536, height: 192)
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
        settings.maxStorageMB = SettingsManager.defaultMaxStorageMB
    }

    func resetStorageMinutes() {
        settings.maxStorageMinutes = SettingsManager.defaultMaxStorageMinutes
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
