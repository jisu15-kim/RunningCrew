//
//  RunnerCardView.swift
//  RunningCrew
//
//  러너 한 개의 상태 카드. 상태 인지 → 다음 행동이 한 카드 안에서 끝난다.
//

import SwiftUI

struct RunnerCardView: View {
    @Environment(AppModel.self) private var model
    let runner: ManagedRunner
    let onOpenDetail: () -> Void

    @State private var showStopOptions = false
    @State private var showMigrateConfirm = false
    @State private var showAdoptConfirm = false
    @State private var showRemoveConfirm = false

    private var presentation: StatusPresentation { runner.statusPresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(presentation.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(runner.repo?.fullName ?? runner.directory.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(presentation.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(presentation.color)

                Button("Logs") {
                    onOpenDetail()
                }
                .controlSize(.regular)

                actionButton
            }

            if let job = runner.activeJob {
                jobRow(job)
            }

            if let detail = presentation.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .contextMenu {
            Button("Logs") {
                onOpenDetail()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.open(runner.directory)
            }
            Divider()
            Button("Remove…", role: .destructive) {
                showRemoveConfirm = true
            }
        }
        .confirmationDialog(
            "Remove this runner?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Move Folder to Trash and Remove", role: .destructive) {
                Task { await model.removeRunner(runner) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The runner folder is moved to the Trash, so you can restore it. A running runner is stopped first. The GitHub registration remains, but it's cleaned up automatically after 14 days offline.")
        }
        .confirmationDialog(
            "Stop this runner?",
            isPresented: $showStopOptions,
            titleVisibility: .visible
        ) {
            Button("Stop After Job (Recommended)") {
                model.stopAfterJob(runner)
            }
            Button("Stop Now", role: .destructive) {
                model.stopNow(runner)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stopping now cancels the job in progress.")
        }
        .alert("Manage this runner with the app?", isPresented: $showMigrateConfirm) {
            Button("Manage") {
                model.migrateFromService(runner)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the system service registration (launchd) and lets the app manage the runner directly. A job in progress may be canceled.")
        }
        .alert("Manage this runner with the app?", isPresented: $showAdoptConfirm) {
            Button("Manage") {
                model.adoptOrphan(runner)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(adoptMessage)
        }
    }

    private var adoptMessage: String {
        if runner.remote.isBusy {
            return String(localized: "This runner is running a job right now. Connecting restarts the runner, which cancels the job in progress.")
        }
        return String(localized: "The existing process is cleaned up and the app restarts the runner. It may go offline briefly.")
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch runner.primaryAction {
        case .start:
            Button("Start") {
                model.start(runner)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case .stop:
            if case .stopPending = runner.local {
                Button("Cancel Scheduled Stop") {
                    model.cancelScheduledStop(runner)
                }
                .buttonStyle(.bordered)
                Button("Stop Now") {
                    model.stopNow(runner)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Stop") {
                    if runner.remote.isBusy {
                        showStopOptions = true
                    } else {
                        model.stopNow(runner)
                    }
                }
                .buttonStyle(.bordered)
            }

        case .adopt:
            Button("Manage This Runner") {
                showAdoptConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case .migrate:
            Button("Manage This Runner") {
                showMigrateConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case .none:
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Job Row

    private func jobRow(_ job: ActiveJob) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.busy)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(job.workflowName)
                        .font(.system(size: 12, weight: .semibold))
                    if !job.jobName.isEmpty {
                        Text("— \(job.jobName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let branch = job.branch {
                        Text(branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let startedAt = job.startedAt {
                        Text("· \(startedAt, style: .relative) elapsed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let url = job.htmlURL {
                Link("Open", destination: url)
                    .font(.system(size: 12))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.busy.opacity(0.08))
        )
    }
}
