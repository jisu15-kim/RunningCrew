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
            infoRow(label: String(localized: "Directory")) {
                HStack(spacing: 6) {
                    Text(runner.directory.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Show in Finder") {
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
                infoRow(label: String(localized: "Labels")) {
                    Text(runner.labels.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            infoRow(label: String(localized: "Auto-restart")) {
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
            Text("Logs")
                .font(.system(size: 12, weight: .semibold))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if runner.log.lines.isEmpty {
                            Text("No logs yet. Start the runner from the app to stream logs here.")
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
            Button("Clear Logs") {
                runner.log.clear()
            }
            Button("Open _diag Folder") {
                NSWorkspace.shared.open(runner.directory.appending(path: "_diag"))
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
