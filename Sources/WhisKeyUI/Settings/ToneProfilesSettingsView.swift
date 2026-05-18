import AppKit
import SwiftUI
import WhisKeyCore

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
                HalideSection(title: "Active app") {
                    if frontmostBundleID.isEmpty {
                        Text("No frontmost app detected.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                    } else {
                        HStack {
                            Text(frontmostBundleID)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(HalideTokens.accentAmber)
                            Spacer()
                            let currentProfile = store.profile(for: frontmostBundleID)
                            Text(currentProfile.displayName.uppercased())
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                        }
                        Text("Tap the bundle ID to use it in the Add field below.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                            .onTapGesture { newBundleID = frontmostBundleID }
                    }
                }

                // ── Add New Mapping ─────────────────────────────────────────
                HalideSection(title: "Add mapping") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("com.example.app", text: $newBundleID)
                                .halideTextField()
                                .font(.caption)
                                .onSubmit { commitAdd() }

                            Picker("", selection: $newProfile) {
                                ForEach(ToneProfile.allCases, id: \.self) { profile in
                                    Text(profile.displayName).tag(profile)
                                }
                            }
                            .pickerStyle(.menu)
                            .accentColor(HalideTokens.accentAmber)
                            .frame(width: 140)

                            Button("ADD") { commitAdd() }
                                .buttonStyle(HalidePrimaryButtonStyle())
                                .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let addError {
                            Text(addError)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.red.opacity(0.85))
                        } else if !newProfile.systemPromptSuffix.isEmpty {
                            Text("Prompt suffix: \"\(newProfile.systemPromptSuffix.trimmingCharacters(in: .whitespaces))\"")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(HalideTokens.accentAmber.opacity(0.45))
                        } else {
                            Text("Raw mode — LLM cleanup skipped entirely.")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(HalideTokens.accentAmber.opacity(0.45))
                        }
                    }
                }

                // ── Configured Mappings ─────────────────────────────────────
                let mappings = store.allMappings
                HalideSection(title: "Configured mappings (\(mappings.count))") {
                    if mappings.isEmpty {
                        Text("No app-specific tone profiles configured.")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mappings, id: \.bundleID) { mapping in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mapping.bundleID)
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .foregroundColor(HalideTokens.accentAmber)
                                        HStack(spacing: 6) {
                                            Text(mapping.profile.displayName.uppercased())
                                                .font(.caption2)
                                                .fontDesign(.monospaced)
                                                .foregroundColor(HalideTokens.accentAmber.opacity(0.55))
                                            if let used = store.lastUsed[mapping.bundleID] {
                                                if Date().timeIntervalSince(used) < 60 {
                                                    Text("● Active")
                                                        .font(.caption2)
                                                        .fontDesign(.monospaced)
                                                        .foregroundColor(HalideTokens.accentAmber)
                                                } else {
                                                    Text(RelativeDateTimeFormatter.whiskey.localizedString(for: used, relativeTo: Date()))
                                                        .font(.caption2)
                                                        .fontDesign(.monospaced)
                                                        .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                                                }
                                            }
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        store.removeProfile(for: mapping.bundleID)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove tone profile for \(mapping.bundleID)")
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 4)

                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(HalideTokens.accentAmber.opacity(0.08))
                            }
                        }
                        .overlay(Rectangle().stroke(HalideTokens.accentAmber.opacity(0.15), lineWidth: 1))
                    }
                }
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
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

// MARK: - RelativeDateTimeFormatter convenience (S5-UX-2)

private extension RelativeDateTimeFormatter {
    @MainActor static let whiskey: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()
}
