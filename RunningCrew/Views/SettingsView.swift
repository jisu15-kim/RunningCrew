//
//  SettingsView.swift
//  RunningCrew
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GitHubSettingsView()
                .tabItem {
                    Label("GitHub", systemImage: "link")
                }
            GeneralSettingsView()
                .tabItem {
                    Label("일반", systemImage: "gearshape")
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
                Text("토큰 직접 입력")
                    .font(.system(size: 13, weight: .semibold))
                Text("Fine-grained PAT 은 저장소의 Administration: Read 권한이 필요해요. 토큰은 Keychain 에 안전하게 보관돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("github_pat_… 또는 ghp_…", text: $manualToken)
                        .textFieldStyle(.roundedBorder)
                    Button("연결") {
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
                    Text("\(login) 으로 연결됨")
                        .font(.system(size: 14, weight: .semibold))
                    Text("러너 상태를 20초마다 동기화해요.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if model.tokenPersistenceFailed {
                        Text("Keychain 저장에 실패해서 이번 실행 동안만 연결이 유지돼요. 앱을 다시 시작하면 다시 연결해주세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                    }
                }
                Spacer()
                Button("연결 해제") {
                    model.disconnectGitHub()
                }

            case .validating:
                ProgressView().controlSize(.small)
                Text("토큰을 확인하는 중…")
                    .font(.system(size: 13))
                Spacer()

            case .missing, .invalid:
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub 미연결")
                        .font(.system(size: 14, weight: .semibold))
                    if case .invalid(let message) = model.tokenState {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("gh CLI 에 로그인되어 있다면 버튼 한 번으로 연결돼요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("gh CLI 에서 가져오기") {
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
                Toggle("로그인할 때 RunningCrew 자동 실행", isOn: $launchAtLogin)
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
                Text("러너를 앱이 직접 관리하므로, 로그인 시 앱이 자동 실행되어야 러너도 함께 관리돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                }
            }
            .card()
        }
        .padding(20)
    }
}
