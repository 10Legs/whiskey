import AppKit
import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Settings tab for per-app tone profiles (S4-T7).
///
/// Displays the current app → profile mappings, lets the user add new entries
/// (bundle ID + tone picker), and delete existing ones.
public struct ToneProfilesSettingsView: View {

    @Bindable private var store: AppToneProfileStore

    // MARK: - Add-row state

    @State private var newBundleID: String = ""
    @State private var newProfile: ToneProfile = .casual
    @State private var addError: String?

    // MARK: - Frontmost app hint

    @State private var frontmostBundleID: String = ""

    public init(store: AppToneProfileStore = .shared) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Active App Hint ─────────────────────────────────────────
                PhosphorToneSection(title: "ACTIVE APP") {
                    if frontmostBundleID.isEmpty {
                        Text("No frontmost app detected.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen.opacity(0.4))
                    } else {
                        HStack {
                            Text(frontmostBundleID)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen)
                            Spacer()
                            let currentProfile = store.profile(for: frontmostBundleID)
                            Text(currentProfile.displayName.uppercased())
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.6))
                        }
                        Text("Tap the bundle ID to use it in the Add field below.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen.opacity(0.4))
                            .onTapGesture { newBundleID = frontmostBundleID }
                    }
                }

                // ── Add New Mapping ─────────────────────────────────────────
                PhosphorToneSection(title: "ADD MAPPING") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("com.example.app", text: $newBundleID)
                                .textFieldStyle(.plain)
                                .foregroundColor(phosphorGreen)
                                .fontDesign(.monospaced)
                                .font(.caption)
                                .onSubmit { commitAdd() }

                            Picker("", selection: $newProfile) {
                                ForEach(ToneProfile.allCases, id: \.self) { profile in
                                    Text(profile.displayName).tag(profile)
                                }
                            }
                            .pickerStyle(.menu)
                            .accentColor(phosphorGreen)
                            .foregroundColor(phosphorGreen)
                            .frame(width: 140)

                            Button("ADD") { commitAdd() }
                                .buttonStyle(PhosphorToneButtonStyle())
                                .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke(phosphorGreen.opacity(0.25), lineWidth: 1))

                        if let addError {
                            Text(addError)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.red.opacity(0.85))
                        } else if !newProfile.systemPromptSuffix.isEmpty {
                            Text("Prompt suffix: \"\(newProfile.systemPromptSuffix.trimmingCharacters(in: .whitespaces))\"")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.45))
                        } else {
                            Text("Raw mode — LLM cleanup skipped entirely.")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.45))
                        }
                    }
                }

                // ── Configured Mappings ─────────────────────────────────────
                let mappings = store.allMappings
                PhosphorToneSection(title: "CONFIGURED MAPPINGS  (\(mappings.count))") {
                    if mappings.isEmpty {
                        Text("No app-specific tone profiles configured.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen.opacity(0.4))
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mappings, id: \.bundleID) { mapping in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mapping.bundleID)
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .foregroundColor(phosphorGreen)
                                        Text(mapping.profile.displayName.uppercased())
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundColor(phosphorGreen.opacity(0.55))
                                    }
                                    Spacer()
                                    Button {
                                        store.removeProfile(for: mapping.bundleID)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundColor(phosphorGreen.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove tone profile for \(mapping.bundleID)")
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 4)

                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(phosphorGreen.opacity(0.08))
                            }
                        }
                        .overlay(Rectangle().stroke(phosphorGreen.opacity(0.15), lineWidth: 1))
                    }
                }
            }
            .padding()
        }
        .background(hudBackground)
        .onAppear { refreshFrontmostApp() }
    }

    // MARK: - Private

    private func commitAdd() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.setProfile(newProfile, for: trimmed)
            newBundleID = ""
            newProfile = .casual
            addError = nil
        } catch {
            addError = error.localizedDescription
        }
    }

    private func refreshFrontmostApp() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}

// MARK: - Private shared components (file-private to avoid colliding with SettingsView's copies)

private struct PhosphorToneSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.6))

            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.2))

            content()
        }
    }
}

private struct PhosphorToneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundColor(phosphorGreen.opacity(configuration.isPressed ? 0.6 : 1.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                Rectangle()
                    .stroke(phosphorGreen.opacity(0.4), lineWidth: 1)
            )
            .background(hudBackground)
    }
}
