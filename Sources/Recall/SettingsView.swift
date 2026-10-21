import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager = SettingsManager.shared
    @ObservedObject var windowController: SettingsWindowController = SettingsWindowController.shared
    var chunkStore: ChunkStore = ChunkManager.shared
    var openPanelPresenter: OpenPanelPresenter = DefaultOpenPanelPresenter()
    var alertPresenter: AlertPresenter = DefaultAlertPresenter()
    var loginItem: LoginItemControlling = LoginItemController()
    var onPurgeRecordings: () -> Void = { MenuBarManager.shared.purgeRecordings() }
    @State private var usage = ChunkUsage()
    @State private var launchAtLogin = false

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }()

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

                        TextField("", value: storageMBBinding, formatter: SettingsView.numberFormatter)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)

                        Text("MB")
                            .font(.system(size: 13))
                            .frame(width: 54, alignment: .leading)

                        Stepper("", value: storageMBBinding, in: ConfigManager.shared.minStorageMB...ConfigManager.shared.maxAllowedStorageMB, step: ConfigManager.shared.stepStorageMB)
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
                        Text(SettingsView.sizeText(usage, maxMB: settings.maxStorageMB))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)

                        Button(action: {
                            onPurgeRecordings()
                        }) {
                            Text("(\(usage.count) clips)")
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

                        TextField("", value: storageMinutesBinding, formatter: SettingsView.numberFormatter)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)

                        Text("Minutes")
                            .font(.system(size: 13))
                            .frame(width: 54, alignment: .leading)

                        Stepper("", value: storageMinutesBinding, in: ConfigManager.shared.minStorageMinutes...ConfigManager.shared.maxAllowedStorageMinutes, step: ConfigManager.shared.stepStorageMinutes)
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

                    Text(SettingsView.durationText(usage, maxMinutes: settings.maxStorageMinutes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            // Card 3: Recording Options
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch Recall at login", isOn: launchAtLoginBinding)

                Toggle("Record at native Retina resolution (sharper text, larger files)", isOn: $settings.recordAtNativeResolution)

                Toggle("Use HEVC encoding (about 40% smaller files)", isOn: $settings.useHEVC)
                    .disabled(!EncoderSupport.isHEVCHardwareEncoderAvailable)
                    .help(EncoderSupport.isHEVCHardwareEncoderAvailable
                          ? "Fits roughly twice the history into the same Max Size"
                          : "This Mac has no hardware HEVC encoder")
            }
            .font(.system(size: 13))
            .toggleStyle(.checkbox)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        usage = chunkStore.usage
        launchAtLogin = loginItem.isEnabled
    }
    .onReceive(chunkStore.usagePublisher) { newUsage in
        usage = newUsage
    }
}

    // MARK: - Bindings

    private var storageMBBinding: Binding<Int> {
        Binding(get: { settings.maxStorageMB }, set: { applyStorageMB($0) })
    }

    private var storageMinutesBinding: Binding<Int> {
        Binding(get: { settings.maxStorageMinutes }, set: { applyStorageMinutes($0) })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })
    }

    // MARK: - Actions

    func chooseDirectory() {
        openPanelPresenter.chooseDirectory { path in
            if let path = path {
                settings.exportsDirectoryPath = path
            }
        }
    }

    func resetStorageMB() {
        applyStorageMB(ConfigManager.shared.defaultMaxStorageMB)
    }

    func resetStorageMinutes() {
        applyStorageMinutes(ConfigManager.shared.defaultMaxStorageMinutes)
    }

    /// Clamps the value and, when it would delete existing recordings, asks first.
    func applyStorageMB(_ requested: Int) {
        let value = SettingsManager.clampedStorageMB(requested)
        let currentUsage = chunkStore.usage
        let excessMB = (Double(currentUsage.totalBytes) - Double(value) * 1024 * 1024) / (1024 * 1024)
        if value < settings.maxStorageMB, excessMB > 0 {
            let message = String(format: "Lowering Max Size to %d MB permanently deletes the oldest %.0f MB of recordings.", value, excessMB)
            guard alertPresenter.confirmLimitReduction(message: message) else {
                // Re-render the field with the unchanged value.
                settings.objectWillChange.send()
                return
            }
        }
        settings.maxStorageMB = value
        if value != requested {
            settings.objectWillChange.send()
        }
    }

    func applyStorageMinutes(_ requested: Int) {
        let value = SettingsManager.clampedStorageMinutes(requested)
        let currentUsage = chunkStore.usage
        let excessSeconds = currentUsage.totalDuration - TimeInterval(value) * 60
        if value < settings.maxStorageMinutes, excessSeconds > 0 {
            let message = "Lowering Max Time to \(value) minutes permanently deletes the oldest \(OverlayHUDBeamView.formatDuration(excessSeconds)) of recordings."
            guard alertPresenter.confirmLimitReduction(message: message) else {
                settings.objectWillChange.send()
                return
            }
        }
        settings.maxStorageMinutes = value
        if value != requested {
            settings.objectWillChange.send()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            alertPresenter.showError(title: "Could Not Change Login Item", message: error.localizedDescription)
        }
        launchAtLogin = loginItem.isEnabled
    }

    // MARK: - Formatting

    static func durationText(_ usage: ChunkUsage, maxMinutes: Int) -> String {
        let totalSecs = Int(usage.totalDuration)
        return String(format: "%dm %02ds / %dm max", totalSecs / 60, totalSecs % 60, maxMinutes)
    }

    static func sizeText(_ usage: ChunkUsage, maxMB: Int) -> String {
        let mb = Double(usage.totalBytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB / %d MB max", mb, maxMB)
    }
}
