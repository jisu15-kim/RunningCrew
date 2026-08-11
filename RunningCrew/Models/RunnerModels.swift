//
//  RunnerModels.swift
//  RunningCrew
//

import Foundation
import Observation

/// GitHub 저장소 참조 (owner/name)
struct RepoRef: Hashable {
    let owner: String
    let name: String

    var fullName: String { "\(owner)/\(name)" }
    var apiPath: String { "repos/\(owner)/\(name)" }
    var webURL: URL? { URL(string: "https://github.com/\(owner)/\(name)") }

    init?(gitHubUrl: String) {
        guard let url = URL(string: gitHubUrl), let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            // GitHub Enterprise 등 다른 호스트는 지원 전까지 원격 상태를 조회하지 않는다.
            // (host 를 무시하고 api.github.com 을 조회하면 무관한 저장소를 폴링하게 된다)
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        self.owner = parts[0]
        self.name = parts[1]
    }
}

/// 러너 디렉토리의 .runner 파일 내용
struct RunnerFileConfig: Codable {
    let agentName: String
    let gitHubUrl: String?
    let workFolder: String?
}

/// GitHub 에서 실행 중이라고 알려준 현재 작업 정보
struct ActiveJob: Equatable {
    let workflowName: String
    let jobName: String
    let branch: String?
    let startedAt: Date?
    let htmlURL: URL?
}

/// 로컬 프로세스 관점의 러너 상태
enum LocalRunState: Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case stopPending(pid: Int32)   // 현재 작업이 끝나면 정지 예약
    case stopping
    case orphan(pid: Int32)        // 앱 관리 밖에서 실행 중 (직접 run.sh 실행 또는 앱 크래시 잔여)
    case service(pid: Int32?)      // launchd 서비스가 관리 중 (pid nil 이면 등록만 되고 정지 상태)
    case failed(String)

    /// 어떤 형태로든 프로세스가 살아있는 상태인지
    var isAlive: Bool {
        switch self {
        case .running, .stopPending, .orphan, .starting:
            return true
        case .service(let pid):
            return pid != nil
        case .stopped, .stopping, .failed:
            return false
        }
    }

    /// 앱이 자식 프로세스로 직접 관리 중인 상태인지
    var isAppManaged: Bool {
        switch self {
        case .running, .stopPending, .starting, .stopping:
            return true
        default:
            return false
        }
    }
}

/// GitHub API 관점의 러너 상태
enum RemoteState: Equatable {
    case unknown        // 아직 조회 전 또는 조회 실패
    case notConnected   // 토큰 미연결
    case notFound       // 저장소에 이 이름의 러너가 없음
    case offline
    case online(busy: Bool)

    var isBusy: Bool {
        if case .online(true) = self { return true }
        return false
    }
}

/// 러너 한 개의 로그 버퍼 (최근 N 줄 유지)
@Observable
final class RunnerLog {
    struct Line: Identifiable {
        let id: Int
        let date: Date
        let text: String
    }

    private(set) var lines: [Line] = []
    private var nextID = 0
    private let capacity = 2000

    func append(_ text: String) {
        lines.append(Line(id: nextID, date: Date(), text: text))
        nextID += 1
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    func clear() {
        lines.removeAll()
    }
}

/// 앱이 관리하는 러너 한 개. 로컬 상태와 원격 상태를 모두 가진다.
@Observable
final class ManagedRunner: Identifiable {
    let directory: URL
    var name: String
    var repo: RepoRef?
    var labels: [String] = []

    var local: LocalRunState = .stopped
    var remote: RemoteState = .unknown
    var activeJob: ActiveJob?

    var autoRestart = true
    let log = RunnerLog()

    // 런타임 전용
    @ObservationIgnored var process: Process?
    @ObservationIgnored var lastStartDate: Date?
    @ObservationIgnored var consecutiveFailures = 0
    @ObservationIgnored var pendingRestart = false
    @ObservationIgnored var logTail: LogTail?

    var id: String { directory.path }

    /// 러너 출력이 쌓이는 로그 파일 (파이프 대신 파일로 받는다)
    var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/RunningCrew/\(name).log")
    }

    /// 시작 직후 GitHub 쪽 상태가 따라오기까지의 유예시간 (offline 경고 억제용)
    var isInStartupGrace: Bool {
        guard let started = lastStartDate else { return false }
        return Date().timeIntervalSince(started) < 90
    }

    init(directory: URL, name: String, repo: RepoRef?) {
        self.directory = directory
        self.name = name
        self.repo = repo
    }
}
