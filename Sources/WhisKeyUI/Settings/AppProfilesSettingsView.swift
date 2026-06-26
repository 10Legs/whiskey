import AppKit
import SwiftUI
import WhisKeyCore

/// Settings panel for per-app transcription profiles (ADR-009).
///
/// Lets the user view, add, edit, and delete `AppProfile` records stored in
/// `SettingsManager.appProfiles`. The key control added by ADR-009 is the
/// Text Injection Method picker in the per-profile editor.
public struct AppProfilesSettingsView: View {

    @Bindable var settings: SettingsManager

    @State private var selectedProfileID: UUID?
    @State private var newBundleID: String = ""
    @State private var newDisplayName: String = ""
    @State private var addError: String?
    @State private var frontmostBundleID: String = ""

    public init(settings: SettingsManager) {
        self.settings = settings
    }

    // MARK: - Derived state

    private var selectedIndex: Int? {
        guard let id = selectedProfileID else { return nil }
        return settings.appProfiles.firstIndex(where: { $0.id == id })
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                activeAppHintSection
                addProfileSection

                profileListSection

                if let index = selectedIndex {
                    profileEditorSection(index: index)
                }
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
        .onAppear { refreshFrontmostApp() }
    }

    // MARK: - Sections

    private var activeAppHintSection: some View {
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
                    Button("Use") { newBundleID = frontmostBundleID }
                        .buttonStyle(HalideSecondaryButtonStyle())
                }
                Text("Tap Use to fill the bundle ID in the Add form below.")
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }
        }
    }

    private var addProfileSection: some View {
        HalideSection(title: "Add profile") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("com.example.app", text: $newBundleID)
                        .halideTextField()
                        .font(.caption)
                        .onSubmit { commitAdd() }

                    TextField("Display name", text: $newDisplayName)
                        .halideTextField()
                        .font(.caption)
                        .onSubmit { commitAdd() }

                    Button("ADD") { commitAdd() }
                        .buttonStyle(HalidePrimaryButtonStyle())
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let addError {
                    Text(addError)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(HalideTokens.accentDestructive)
                }
            }
        }
    }

    private var profileListSection: some View {
        let profiles = settings.appProfiles
        return HalideSection(title: "Profiles (\(profiles.count))") {
            if profiles.isEmpty {
                Text("No profiles configured.")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { _, profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.caption)
                                    .foregroundColor(HalideTokens.textPrimary)
                                Text(profile.bundleIdentifier)
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(HalideTokens.textSecondary)
                            }
                            Spacer()

                            // Badge for non-auto injection method
                            if profile.injectionMethod != .auto {
                                Text(profile.injectionMethod.displayName.uppercased())
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(HalideTokens.accentAmber.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(HalideTokens.accentAmber.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            Button(selectedProfileID == profile.id ? "Close" : "Edit") {
                                selectedProfileID = (selectedProfileID == profile.id)
                                    ? nil : profile.id
                            }
                            .buttonStyle(HalideSecondaryButtonStyle())

                            // Wildcard default profile cannot be deleted
                            if profile.bundleIdentifier != "*" {
                                Button {
                                    let idToRemove = profile.id
                                    settings.appProfiles.removeAll { $0.id == idToRemove }
                                    if selectedProfileID == idToRemove { selectedProfileID = nil }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove profile for \(profile.displayName)")
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            selectedProfileID == profile.id
                                ? HalideTokens.accentAmber.opacity(0.07)
                                : Color.clear
                        )

                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(HalideTokens.accentAmber.opacity(0.08))
                    }
                }
                .overlay(Rectangle().stroke(HalideTokens.accentAmber.opacity(0.15), lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func profileEditorSection(index: Int) -> some View {
        let profile = settings.appProfiles[index]
        HalideSection(title: "Edit: \(profile.displayName)") {

            // Enabled toggle
            Toggle("Profile enabled", isOn: $settings.appProfiles[index].enabled)
                .tint(HalideTokens.accentAmber)
                .foregroundColor(HalideTokens.textPrimary)

            Divider()

            // Display name
            HStack {
                Text("Display Name")
                    .foregroundColor(HalideTokens.textSecondary)
                Spacer()
                TextField("App Name", text: $settings.appProfiles[index].displayName)
                    .halideTextField()
                    .frame(maxWidth: 200)
            }

            Divider()

            // Advanced settings — injection method (ADR-009)
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text Injection Method")
                            .foregroundColor(HalideTokens.textSecondary)
                        Spacer()
                        Picker("Text Injection Method",
                               selection: $settings.appProfiles[index].injectionMethod) {
                            ForEach(InjectionMethod.allCases, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 210)
                        .tint(HalideTokens.accentAmber)
                        .labelsHidden()
                    }
                    Text(
                        "Automatic tries the fastest method and falls back as needed. " +
                        "If text from WhisKey doesn't appear in this app " +
                        "(e.g. Telegram, Messages), choose Paste."
                    )
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .foregroundColor(HalideTokens.textPrimary)
        }
    }

    // MARK: - Private helpers

    private func refreshFrontmostApp() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    private func commitAdd() {
        let bundleID = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }

        if settings.appProfiles.contains(where: { $0.bundleIdentifier == bundleID }) {
            addError = "A profile for \"\(bundleID)\" already exists."
            return
        }

        let profile = AppProfile(
            bundleIdentifier: bundleID,
            displayName: name.isEmpty ? bundleID : name
        )
        settings.appProfiles.append(profile)
        selectedProfileID = profile.id
        newBundleID = ""
        newDisplayName = ""
        addError = nil
    }
}
