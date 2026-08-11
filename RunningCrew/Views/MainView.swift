//
//  MainView.swift
//  RunningCrew
//
//  러너 대시보드: 상태 요약 + 러너 카드 목록.
//

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRunner: ManagedRunner?
    @State private var showFolderImporter = false
    @State private var addFolderError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header

                if needsTokenBanner {
                    tokenBanner
                }

                if model.runners.isEmpty {
                    emptyState
                } else {
                    ForEach(model.runners) { runner in
                        RunnerCardView(runner: runner) {
                            selectedRunner = runner
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("RunningCrew")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await model.discoverRunners() // 새로 설치한 러너도 다시 찾는다
                        await model.refreshLocalStates()
                        await model.syncWithGitHub()
                    }
                } label: {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Refresh status")
            }
            ToolbarItem {
                Button {
                    showFolderImporter = true
                } label: {
                    Label("Add Runner Folder", systemImage: "plus")
                }
                .help("Add a runner folder")
            }
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(item: $selectedRunner) { runner in
            RunnerDetailView(runner: runner)
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                if !model.addRunnerIfNeeded(at: url) {
                    addFolderError = String(localized: "Couldn't find a runner configuration (.runner) in this folder. Choose a folder where a self-hosted runner is installed.")
                }
            }
        }
        .alert(String(localized: "Couldn't add the runner"), isPresented: .init(
            get: { addFolderError != nil },
            set: { if !$0 { addFolderError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addFolderError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(summaryTitle)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                if let lastSync = model.lastSync {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(summarySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var summaryTitle: String {
        if model.runners.isEmpty {
            return String(localized: "Looking for runners")
        }
        if model.busyCount > 0 {
            return String(localized: "\(model.runners.count) runners · \(model.busyCount) busy")
        }
        return String(localized: "\(model.runners.count) runners")
    }

    private var summarySubtitle: String {
        let alive = model.aliveCount
        if model.runners.isEmpty {
            return String(localized: "Automatically finds LaunchAgents and running processes.")
        }
        if alive == model.runners.count {
            return String(localized: "All runners are running.")
        }
        return String(localized: "\(alive) running · \(model.runners.count - alive) stopped")
    }

    // MARK: - Token Banner

    private var needsTokenBanner: Bool {
        switch model.tokenState {
        case .connected: return false
        default: return true
        }
    }

    private var tokenBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect to GitHub")
                    .font(.system(size: 14, weight: .semibold))
                Text(tokenBannerMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .validating = model.tokenState {
                ProgressView().controlSize(.small)
            } else {
                Button("Import from gh CLI") {
                    Task { await model.importTokenFromGHCLI() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                SettingsLink {
                    Text("Enter Manually")
                }
            }
        }
        .card()
    }

    private var tokenBannerMessage: String {
        if case .invalid(let message) = model.tokenState {
            return message
        }
        return String(localized: "Connect to see each runner's online/busy status and current jobs.")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No runners found")
                .font(.system(size: 15, weight: .semibold))
            Text("You can add a folder where a self-hosted runner is installed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Add Runner Folder") {
                showFolderImporter = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }
}
