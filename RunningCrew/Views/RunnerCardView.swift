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

                Button("로그") {
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
        .confirmationDialog(
            "러너를 정지할까요?",
            isPresented: $showStopOptions,
            titleVisibility: .visible
        ) {
            Button("작업이 끝나면 정지 (권장)") {
                model.stopAfterJob(runner)
            }
            Button("지금 정지", role: .destructive) {
                model.stopNow(runner)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("지금 정지하면 실행 중인 작업이 취소돼요.")
        }
        .alert("앱 관리로 전환할까요?", isPresented: $showMigrateConfirm) {
            Button("전환") {
                model.migrateFromService(runner)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("시스템 서비스(launchd) 등록을 해제하고 앱이 직접 실행을 맡아요. 실행 중인 작업이 있다면 취소될 수 있어요.")
        }
        .alert("앱 관리로 연결할까요?", isPresented: $showAdoptConfirm) {
            Button("연결") {
                model.adoptOrphan(runner)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(adoptMessage)
        }
    }

    private var adoptMessage: String {
        if runner.remote.isBusy {
            return "지금 이 러너가 작업을 실행하고 있어요. 연결 과정에서 러너를 재시작하므로 실행 중인 작업이 취소돼요."
        }
        return "기존 프로세스를 정리하고 앱이 다시 시작해요. 잠깐 offline 상태가 될 수 있어요."
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch runner.primaryAction {
        case .start:
            Button("시작") {
                model.start(runner)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case .stop:
            if case .stopPending = runner.local {
                Button("예약 취소") {
                    model.cancelScheduledStop(runner)
                }
                .buttonStyle(.bordered)
                Button("지금 정지") {
                    model.stopNow(runner)
                }
                .buttonStyle(.bordered)
            } else {
                Button("정지") {
                    if runner.remote.isBusy {
                        showStopOptions = true
                    } else {
                        model.stopNow(runner)
                    }
                }
                .buttonStyle(.bordered)
            }

        case .adopt:
            Button("앱 관리로 연결") {
                showAdoptConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

        case .migrate:
            Button("앱 관리로 전환") {
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
                        Text("· \(startedAt, style: .relative) 실행 중")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let url = job.htmlURL {
                Link("열기", destination: url)
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
