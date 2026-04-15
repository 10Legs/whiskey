import SwiftUI
import WhisKeyCore

/// Tabbed settings window.
///
/// Tabs: General | Hotkey | Transcription | AI Cleanup | Privacy
public struct SettingsView: View {

    @Bindable private var settings: SettingsManager

    public init(settings: SettingsManager) {
        self.settings = settings
    }

    public var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            HotkeyTab()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            TranscriptionTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "waveform") }

            AICleanupTab(settings: settings)
                .tabItem { Label("AI Cleanup", systemImage: "sparkles") }

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: .constant(false))
                    .disabled(true)
                    .help("Coming soon — requires SMAppService integration.")
            }

            Section("Whisper Model") {
                Picker("Active Model", selection: $settings.whisperModel) {
                    Text("ggml-tiny.en").tag("ggml-tiny.en")
                    Text("ggml-base.en").tag("ggml-base.en")
                    Text("ggml-small.en").tag("ggml-small.en")
                    Text("ggml-medium.en").tag("ggml-medium.en")
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Tab

private struct HotkeyTab: View {
    var body: some View {
        Form {
            Section("Push-to-Talk Hotkey") {
                HStack {
                    Text("Current Hotkey:")
                    Spacer()
                    Text("Right Option (hold)")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("Hold to record, release to transcribe and inject.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Transcription Tab

private struct TranscriptionTab: View {
    @Bindable var settings: SettingsManager

    private static let languages: [(String, String?)] = [
        ("Auto-detect", nil),
        ("English", "en"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Japanese", "ja"),
        ("Chinese", "zh"),
        ("Korean", "ko"),
    ]

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language Hint", selection: $settings.languageHint) {
                    ForEach(Self.languages, id: \.1) { name, code in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
                Text("Providing a language hint improves accuracy when you know the spoken language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - AI Cleanup Tab

private struct AICleanupTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $settings.llmProviderName) {
                    Text("None (raw transcript)").tag("none")
                    Text("LlamaCpp (local)").tag("llamacpp")
                    Text("Ollama (local HTTP)").tag("ollama")
                }
                .pickerStyle(.menu)
            }

            Section("Cleanup Options") {
                Toggle("Remove Filler Words", isOn: $settings.removeFillers)
                Toggle("Add Punctuation", isOn: $settings.addPunctuation)
                Toggle("Raw Mode (skip cleanup)", isOn: $settings.rawMode)
            }

            Section("Tone Style") {
                Picker("Default Tone", selection: $settings.toneStyle) {
                    ForEach(ToneStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("The tone auto-adjusts based on the active application unless overridden here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Privacy Tab

private struct PrivacyTab: View {
    var body: some View {
        Form {
            Section("Required Permissions") {
                PrivacyRow(
                    title: "Microphone",
                    description: "Required for voice capture.",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                PrivacyRow(
                    title: "Accessibility",
                    description: "Required for text injection via AX API.",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PrivacyRow(
                    title: "Input Monitoring",
                    description: "Required for global hotkey (Right Option).",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PrivacyRow: View {
    let title: String
    let description: String
    let urlString: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
