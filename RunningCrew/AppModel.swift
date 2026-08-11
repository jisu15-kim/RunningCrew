//
//  AppModel.swift
//  RunningCrew
//
//  앱 전체 상태의 단일 소스. 러너 발견/등록, 로컬 상태 갱신 루프를 담당한다.
//

import Foundation
import Observation

@Observable
final class AppModel {
    static let shared = AppModel()

    var runners: [ManagedRunner] = []

    enum TokenState: Equatable {
        case missing
        case validating
        case connected(login: String)
        case invalid(String)
    }

    var tokenState: TokenState = .missing
    var lastSync: Date?
    var isSyncing = false
    /// Keychain 영속화 실패 여부 (연결은 유지되지만 앱 재시작 시 다시 연결해야 함)
    var tokenPersistenceFailed = false

    /// 현재 세션에서 사용하는 토큰. Keychain 은 영속화 용도로만 쓴다.
    @ObservationIgnored var activeToken: String?

    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored private var localTask: Task<Void, Never>?
    @ObservationIgnored private var bootstrapped = false

    private static let registeredPathsKey = "registeredRunnerPaths"

    private var registeredPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.registeredPathsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.registeredPathsKey) }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await loadToken()
        await discoverRunners()
        await refreshLocalStates()
        startLocalMonitor()
        startPolling()
    }

    /// 러너 로그 파일 tail 을 시작한다 (앱 재시작 후에도 이전 로그 꼬리를 이어서 본다).
    func startLogTail(_ runner: ManagedRunner) {
        guard runner.logTail == nil else { return }
        let tail = LogTail(url: runner.logFileURL, log: runner.log)
        tail.start()
        runner.logTail = tail
    }

    // MARK: - 러너 발견/등록

    /// LaunchAgent, 실행 중 프로세스, 홈 스캔, 저장된 경로를 합쳐 러너 목록을 만든다.
    func discoverRunners() async {
        var directories = Set(registeredPaths.map { URL(fileURLWithPath: $0).standardizedFileURL })
        for (dir, _) in RunnerDiscovery.launchAgentServices() {
            directories.insert(dir)
        }
        for process in await RunnerDiscovery.runningListeners() {
            directories.insert(process.directory)
        }
        for dir in RunnerDiscovery.scanHomeForRunners() {
            directories.insert(dir)
        }

        for directory in directories.sorted(by: { $0.path < $1.path }) {
            addRunnerIfNeeded(at: directory)
        }
        registeredPaths = runners.map { $0.directory.path }
        for runner in runners {
            startLogTail(runner)
        }
    }

    /// 디렉토리가 유효한 러너면 목록에 추가한다. 성공 여부를 반환.
    @discardableResult
    func addRunnerIfNeeded(at directory: URL) -> Bool {
        let directory = directory.standardizedFileURL
        guard !runners.contains(where: { $0.directory == directory }) else { return true }
        guard let config = RunnerDiscovery.loadConfig(at: directory) else { return false }
        let runner = ManagedRunner(
            directory: directory,
            name: config.agentName,
            repo: config.gitHubUrl.flatMap { RepoRef(gitHubUrl: $0) }
        )
        runners.append(runner)
        registeredPaths = runners.map { $0.directory.path }
        startLogTail(runner)
        return true
    }

    func removeRunner(_ runner: ManagedRunner) {
        guard !runner.local.isAppManaged else { return }
        runners.removeAll { $0.id == runner.id }
        registeredPaths = runners.map { $0.directory.path }
    }

    // MARK: - 로컬 상태 갱신 루프

    func startLocalMonitor() {
        localTask?.cancel()
        localTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLocalStates()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// 프로세스 스캔 결과로 각 러너의 로컬 상태를 보정한다.
    func refreshLocalStates() async {
        let listeners = await RunnerDiscovery.runningListeners()
        let services = RunnerDiscovery.launchAgentServices()

        for runner in runners {
            let external = listeners.first { $0.directory == runner.directory }
            let hasService = services[runner.directory] != nil
            let childAlive = runner.process?.isRunning == true

            switch runner.local {
            case .starting, .stopping, .stopPending:
                continue // 전이 중에는 건드리지 않는다

            case .running(let pid):
                // 표시용 PID 를 실제 Runner.Listener 의 것으로 갱신
                if childAlive, let external, external.pid != pid {
                    runner.local = .running(pid: external.pid)
                }

            case .stopped, .orphan, .service, .failed:
                if childAlive { continue }
                if let external {
                    runner.local = hasService
                        ? .service(pid: external.pid)
                        : .orphan(pid: external.pid)
                } else if case .failed = runner.local {
                    continue // 실패 사유는 사용자가 확인할 때까지 유지
                } else if hasService {
                    runner.local = .service(pid: nil)
                } else {
                    runner.local = .stopped
                }
            }
        }
    }

    // MARK: - 요약 (메뉴바 등)

    var aliveCount: Int { runners.filter { $0.local.isAlive }.count }
    var busyCount: Int { runners.filter { $0.remote.isBusy }.count }

    var hasWarning: Bool {
        runners.contains { runner in
            if case .failed = runner.local { return true }
            if case .orphan = runner.local { return true }
            // 프로세스는 떠 있는데 GitHub 에서 offline 인 불일치.
            // 시작 직후에는 GitHub 상태가 따라오기 전이라 유예시간을 둔다.
            if runner.local.isAlive, case .offline = runner.remote, !runner.isInStartupGrace {
                return true
            }
            return false
        }
    }

}
