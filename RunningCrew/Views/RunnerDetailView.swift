//
//  RunnerDetailView.swift
//  RunningCrew
//
//  러너 상세: 정보 + 실시간 로그 콘솔.
//

import SwiftUI

struct RunnerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var runner: ManagedRunner

    private var presentation: StatusPresentation { runner.statusPresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            infoSection
            logConsole
            footer
        }
        .padding(20)
        .frame(width: 680, height: 560)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(presentation.color)
                .frame(width: 10, height: 10)
            Text(runner.name)
                .font(.system(size: 18, weight: .bold))
            Text(presentation.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(presentation.color)
            Spacer()
            if let repo = runner.repo, let url = repo.webURL {
                Link(repo.fullName, destination: url)
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(label: "디렉토리") {
                HStack(spacing: 6) {
                    Text(runner.directory.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Finder 에서 열기") {
                        NSWorkspace.shared.open(runner.directory)
                    }
                    .controlSize(.small)
                }
            }
            if let pid = runner.displayPID {
                infoRow(label: "PID") {
                    Text("\(pid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if !runner.labels.isEmpty {
                infoRow(label: "라벨") {
                    Text(runner.labels.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            infoRow(label: "자동 재시작") {
                Toggle("", isOn: $runner.autoRestart)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
        .card()
    }

    private func infoRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Log Console

    private var logConsole: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("로그")
                .font(.system(size: 12, weight: .semibold))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if runner.log.lines.isEmpty {
                            Text("아직 로그가 없어요. 앱에서 러너를 시작하면 실시간 로그가 여기에 보여요.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(8)
                        }
                        ForEach(runner.log.lines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .onChange(of: runner.log.lines.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("로그 지우기") {
                runner.log.clear()
            }
            Button("_diag 폴더 열기") {
                NSWorkspace.shared.open(runner.directory.appending(path: "_diag"))
            }
            Spacer()
            Button("닫기") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
