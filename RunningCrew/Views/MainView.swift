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
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                }
                .help("상태 새로고침")
            }
            ToolbarItem {
                Button {
                    showFolderImporter = true
                } label: {
                    Label("러너 폴더 추가", systemImage: "plus")
                }
                .help("러너 폴더 직접 추가")
            }
            ToolbarItem {
                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
                .help("설정")
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
                    addFolderError = "이 폴더에서 러너 설정(.runner)을 찾지 못했어요. self-hosted runner 가 설치된 폴더를 선택해주세요."
                }
            }
        }
        .alert("러너를 추가하지 못했어요", isPresented: .init(
            get: { addFolderError != nil },
            set: { if !$0 { addFolderError = nil } }
        )) {
            Button("확인", role: .cancel) {}
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
                    Text("마지막 동기화 \(lastSync, style: .relative) 전")
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
        if model.runners.isEmpty { return "러너를 찾는 중이에요" }
        if model.busyCount > 0 { return "러너 \(model.runners.count)개 · \(model.busyCount)개 작업 중" }
        return "러너 \(model.runners.count)개"
    }

    private var summarySubtitle: String {
        let alive = model.aliveCount
        if model.runners.isEmpty {
            return "LaunchAgent 와 실행 중인 프로세스를 자동으로 찾아요."
        }
        if alive == model.runners.count {
            return "모든 러너가 실행 중이에요."
        }
        return "\(alive)개 실행 중 · \(model.runners.count - alive)개 정지됨"
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
                Text("GitHub 연결이 필요해요")
                    .font(.system(size: 14, weight: .semibold))
                Text(tokenBannerMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if case .validating = model.tokenState {
                ProgressView().controlSize(.small)
            } else {
                Button("gh CLI 에서 가져오기") {
                    Task { await model.importTokenFromGHCLI() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                SettingsLink {
                    Text("직접 입력")
                }
            }
        }
        .card()
    }

    private var tokenBannerMessage: String {
        if case .invalid(let message) = model.tokenState {
            return message
        }
        return "연결하면 러너의 online/busy 상태와 실행 중인 작업을 볼 수 있어요."
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("러너를 찾지 못했어요")
                .font(.system(size: 15, weight: .semibold))
            Text("self-hosted runner 가 설치된 폴더를 직접 추가할 수 있어요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("러너 폴더 추가") {
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
