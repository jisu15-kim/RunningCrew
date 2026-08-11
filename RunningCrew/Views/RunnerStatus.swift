//
//  RunnerStatus.swift
//  RunningCrew
//
//  로컬 상태 × 원격 상태를 사용자가 한눈에 이해할 표현으로 병합한다.
//  원칙: 상태를 속이지 않는다 — 불일치는 숨기지 않고 그대로 보여준다.
//

import SwiftUI

struct StatusPresentation {
    let color: Color
    let title: String
    var detail: String?
}

enum PrimaryAction {
    case start      // 시작
    case stop       // 정지 (busy 면 선택지 제공)
    case adopt      // 고아 프로세스를 앱 관리로 연결
    case migrate    // 시스템 서비스를 앱 관리로 전환
    case none       // 전이 중
}

extension ManagedRunner {
    var statusPresentation: StatusPresentation {
        switch local {
        case .starting:
            return StatusPresentation(color: Theme.busy, title: String(localized: "Starting…"))
        case .stopping:
            return StatusPresentation(color: .secondary, title: String(localized: "Stopping…"))
        case .stopPending:
            if case .online = remote {
                return StatusPresentation(color: Theme.busy, title: String(localized: "Stops after current job"))
            }
            return StatusPresentation(
                color: Theme.busy,
                title: String(localized: "Stops after current job"),
                detail: String(localized: "Can't verify GitHub status, so the runner keeps waiting. Use Stop Now to stop immediately.")
            )
        case .failed(let reason):
            return StatusPresentation(color: Theme.danger, title: String(localized: "Something went wrong"), detail: reason)
        case .orphan:
            return StatusPresentation(
                color: Theme.warning,
                title: String(localized: "Running outside the app"),
                detail: String(localized: "Connect to app management to control status and stops from here.")
            )
        case .service(let pid):
            if pid == nil {
                return StatusPresentation(
                    color: .secondary,
                    title: String(localized: "Registered as system service · Stopped"),
                    detail: String(localized: "Switch to app management to control it from here.")
                )
            }
            return StatusPresentation(
                color: Theme.warning,
                title: String(localized: "Running as system service"),
                detail: String(localized: "Switch to app management for live logs and control from here.")
            )
        case .stopped:
            return StatusPresentation(color: .secondary, title: String(localized: "Stopped"))
        case .running:
            switch remote {
            case .online(busy: true):
                return StatusPresentation(color: Theme.busy, title: String(localized: "Running a job"))
            case .online(busy: false):
                return StatusPresentation(color: Theme.running, title: String(localized: "Idle"))
            case .offline:
                if isInStartupGrace {
                    // 시작 직후에는 GitHub 상태가 따라오기 전이라 경고하지 않는다
                    return StatusPresentation(color: Theme.running, title: String(localized: "Running · Checking connection"))
                }
                return StatusPresentation(
                    color: Theme.warning,
                    title: String(localized: "Running · Not connected to GitHub"),
                    detail: String(localized: "The process is alive but GitHub reports it offline. Check the network or the runner registration.")
                )
            case .notFound:
                return StatusPresentation(
                    color: Theme.warning,
                    title: String(localized: "Running · Not registered on GitHub"),
                    detail: String(localized: "No runner with this name is registered in the repository.")
                )
            case .notConnected, .unknown:
                return StatusPresentation(color: Theme.running, title: String(localized: "Running"))
            }
        }
    }

    var primaryAction: PrimaryAction {
        switch local {
        case .stopped, .failed: return .start
        case .running, .stopPending: return .stop
        case .orphan: return .adopt
        case .service: return .migrate
        case .starting, .stopping: return .none
        }
    }

    var displayPID: Int32? {
        switch local {
        case .running(let pid), .stopPending(let pid), .orphan(let pid):
            return pid
        case .service(let pid):
            return pid
        default:
            return nil
        }
    }
}
