//
//  SettingsView.swift
//  RunningCrew
//

import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsView: View {
    var body: some View {
        TabView {
            GitHubSettingsView()
                .tabItem {
                    Label("GitHub", systemImage: "link")
                }
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 480)
    }
}

// MARK: - GitHub

private struct GitHubSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var manualToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            statusCard

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter Token Manually")
                    .font(.system(size: 13, weight: .semibold))
                Text("A fine-grained PAT needs the repository's Administration: Read permission. The token is stored securely in Keychain.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("github_pat_… or ghp_…", text: $manualToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Connect") {
                        let token = manualToken
                        manualToken = ""
                        Task { await model.setToken(token) }
                    }
                    .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .card()
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 12) {
            switch model.tokenState {
            case .connected(let login):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.running)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected as \(login)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Runner status syncs every 20 seconds.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if model.tokenPersistenceFailed {
                        Text("Couldn't save to Keychain, so the connection lasts only for this session. Reconnect after relaunching the app.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                    }
                }
                Spacer()
                Button("Disconnect") {
                    model.disconnectGitHub()
                }

            case .validating:
                ProgressView().controlSize(.small)
                Text("Verifying token…")
                    .font(.system(size: 13))
                Spacer()

            case .missing, .invalid:
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not connected to GitHub")
                        .font(.system(size: 14, weight: .semibold))
                    if case .invalid(let message) = model.tokenState {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("If you're signed in to the gh CLI, one click connects you.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Import from gh CLI") {
                    Task { await model.importTokenFromGHCLI() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .card()
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch RunningCrew at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("The app manages runners directly, so it needs to launch at login for your runners to be managed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text("Updates")
                    .font(.system(size: 13, weight: .semibold))
                Text("Updates are checked automatically. You can also check right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Check for Updates…") {
                    Updater.controller.checkForUpdates(nil)
                }
            }
            .card()
        }
        .padding(20)
    }
}
