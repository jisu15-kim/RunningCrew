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
    case migrate    // launchd 서비스를 앱 관리로 전환
    case none       // 전이 중
}

extension ManagedRunner {
    var statusPresentation: StatusPresentation {
        switch local {
        case .starting:
            return StatusPresentation(color: Theme.busy, title: "시작하는 중…")
        case .stopping:
            return StatusPresentation(color: .secondary, title: "정지하는 중…")
        case .stopPending:
            if case .online = remote {
                return StatusPresentation(color: Theme.busy, title: "작업이 끝나면 정지해요")
            }
            return StatusPresentation(
                color: Theme.busy,
                title: "작업이 끝나면 정지해요",
                detail: "GitHub 상태를 확인할 수 없어 대기 중이에요. 바로 정지하려면 지금 정지를 눌러주세요."
            )
        case .failed(let reason):
            return StatusPresentation(color: Theme.danger, title: "문제가 생겼어요", detail: reason)
        case .orphan:
            return StatusPresentation(
                color: Theme.warning,
                title: "앱 밖에서 실행 중",
                detail: "앱 관리로 연결하면 상태와 정지를 여기서 제어할 수 있어요."
            )
        case .service(let pid):
            if pid == nil {
                return StatusPresentation(
                    color: .secondary,
                    title: "시스템 서비스로 등록됨 · 정지",
                    detail: "앱 관리로 전환하면 여기서 실행을 제어할 수 있어요."
                )
            }
            return StatusPresentation(
                color: Theme.warning,
                title: "시스템 서비스로 실행 중",
                detail: "앱 관리로 전환하면 실시간 로그와 정지를 여기서 제어할 수 있어요."
            )
        case .stopped:
            return StatusPresentation(color: .secondary, title: "정지됨")
        case .running:
            switch remote {
            case .online(busy: true):
                return StatusPresentation(color: Theme.busy, title: "작업 실행 중")
            case .online(busy: false):
                return StatusPresentation(color: Theme.running, title: "대기 중")
            case .offline:
                if isInStartupGrace {
                    // 시작 직후에는 GitHub 상태가 따라오기 전이라 경고하지 않는다
                    return StatusPresentation(color: Theme.running, title: "실행 중 · 연결 확인 중")
                }
                return StatusPresentation(
                    color: Theme.warning,
                    title: "실행 중 · GitHub 연결 안 됨",
                    detail: "프로세스는 떠 있지만 GitHub 에서는 offline 으로 보여요. 네트워크나 러너 등록 상태를 확인해주세요."
                )
            case .notFound:
                return StatusPresentation(
                    color: Theme.warning,
                    title: "실행 중 · GitHub 에 등록 없음",
                    detail: "이 이름의 러너가 저장소에 등록되어 있지 않아요."
                )
            case .notConnected, .unknown:
                return StatusPresentation(color: Theme.running, title: "실행 중")
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
