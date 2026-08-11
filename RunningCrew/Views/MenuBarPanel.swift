//
//  MenuBarPanel.swift
//  RunningCrew
//
//  메뉴바 요약 패널: 러너별 한 줄 상태 + 빠른 제어.
//

import SwiftUI
import Sparkle

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.runners.isEmpty {
                Text("No runners found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(model.runners) { runner in
                    runnerRow(runner)
                    if runner.id != model.runners.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Check for Updates…") {
                    Updater.controller.checkForUpdates(nil)
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .frame(width: 320)
    }

    private func runnerRow(_ runner: ManagedRunner) -> some View {
        let presentation = runner.statusPresentation
        return HStack(spacing: 10) {
            Circle()
                .fill(presentation.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(runner.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(presentation.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            quickAction(runner)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func quickAction(_ runner: ManagedRunner) -> some View {
        switch runner.primaryAction {
        case .start:
            Button {
                model.start(runner)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Start")

        case .stop:
            Button {
                if runner.remote.isBusy {
                    // 작업 취소 여부는 대시보드에서 명확히 선택하게 한다
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    model.stopNow(runner)
                }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Stop")

        case .adopt, .migrate:
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Manage in Dashboard")

        case .none:
            ProgressView()
                .controlSize(.small)
        }
    }
}
