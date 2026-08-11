//
//  AppModel+Process.swift
//  RunningCrew
//
//  러너 프로세스 수명주기: 시작, 정지(graceful), 고아 연결, 시스템 서비스 전환.
//
//  프로세스 트리 주의: 앱이 직접 띄우는 것은 `bash run.sh` 이고, 실제 러너는
//  run.sh → run-helper.sh → Runner.Listener (→ Runner.Worker) 로 두 단계 아래에 있다.
//  run.sh 는 시그널을 아래로 전달하지 않으므로, 시그널은 개별 PID 가 아니라
//  러너 디렉토리 기준 트리 전체에 보낸다 (터미널 Ctrl+C 와 같은 의미).
//

import Foundation
import Darwin

extension AppModel {
    // MARK: - 시작

    func start(_ runner: ManagedRunner) {
        switch runner.local {
        case .stopped:
            break
        case .failed:
            runner.consecutiveFailures = 0 // 사용자가 직접 재시작하면 재시도 기회를 초기화
        default:
            return
        }
        runner.local = .starting
        Task {
            // 중복 실행 방지: 외부에서 이미 돌고 있으면 시작하지 않는다
            let listeners = await RunnerDiscovery.runningListeners()
            if let external = listeners.first(where: { $0.directory == runner.directory }) {
                let hasService = RunnerDiscovery.launchAgentServices()[runner.directory] != nil
                runner.local = hasService ? .service(pid: external.pid) : .orphan(pid: external.pid)
                runner.log.append(String(localized: "Already running elsewhere (PID \(Int(external.pid)))."))
                return
            }
            self.spawn(runner)
        }
    }

    private func spawn(_ runner: ManagedRunner) {
        let runScript = runner.directory.appending(path: "run.sh")
        guard FileManager.default.fileExists(atPath: runScript.path) else {
            runner.local = .failed(String(localized: "Couldn't find run.sh"))
            runner.log.append(String(localized: "Couldn't find run.sh at \(runScript.path)"))
            return
        }
        guard let logHandle = prepareLogFile(for: runner) else {
            runner.local = .failed(String(localized: "Couldn't create the log file"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runScript.path]
        process.currentDirectoryURL = runner.directory
        process.standardInput = FileHandle.nullDevice
        // 출력은 파이프가 아니라 파일로 받는다. 파이프는 앱 종료/크래시 시 reader 가
        // 사라져 러너가 SIGPIPE 로 죽을 수 있고, 종료 시점의 블로킹 읽기 문제도 있다.
        process.standardOutput = logHandle
        process.standardError = logHandle

        process.terminationHandler = { @Sendable [weak self, weak runner] p in
            let status = p.terminationStatus
            let model = self
            let target = runner
            Task { @MainActor in
                guard let model, let target else { return }
                model.handleTermination(of: target, status: status)
            }
        }

        do {
            try process.run()
            runner.process = process
            runner.lastStartDate = Date()
            runner.local = .running(pid: process.processIdentifier)
            runner.log.append(String(localized: "Runner started."))
            startLogTail(runner)
        } catch {
            runner.local = .failed(error.localizedDescription)
            runner.log.append(String(localized: "Failed to start: \(error.localizedDescription)"))
        }
    }

    /// 러너 출력용 로그 파일 핸들을 준비한다 (5MB 초과 시 .old 로 로테이션).
    private func prepareLogFile(for runner: ManagedRunner) -> FileHandle? {
        let fm = FileManager.default
        let url = runner.logFileURL
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? UInt64, size > 5_000_000 {
            let old = url.appendingPathExtension("old")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }

    // MARK: - 정지

    /// 현재 작업이 끝나면 정지하도록 예약한다.
    func stopAfterJob(_ runner: ManagedRunner) {
        guard case .running(let pid) = runner.local else { return }
        runner.local = .stopPending(pid: pid)
        runner.log.append(String(localized: "Will stop after the current job finishes."))
    }

    /// 정지 예약을 취소하고 계속 실행한다.
    func cancelScheduledStop(_ runner: ManagedRunner) {
        guard case .stopPending(let pid) = runner.local else { return }
        runner.local = .running(pid: pid)
        runner.log.append(String(localized: "Scheduled stop canceled."))
    }

    /// 즉시 정지한다. 러너 트리 전체에 SIGINT 를 보내 GitHub 에 정상 해제를 알린다.
    func stopNow(_ runner: ManagedRunner) {
        switch runner.local {
        case .running, .stopPending:
            break
        default:
            return
        }
        // 이 정지 요청이 겨냥한 프로세스. 에스컬레이션은 이 프로세스가
        // 여전히 현재 프로세스일 때만 실행한다 (그 사이 정상 종료 후 재시작됐을 수 있다).
        let target = runner.process
        runner.local = .stopping
        runner.log.append(String(localized: "Stopping the runner…"))
        Task {
            let pids = await RunnerDiscovery.processIDs(inTree: runner.directory)
            if pids.isEmpty {
                if let target, target.isRunning { target.interrupt() }
            } else {
                for pid in pids { kill(pid, SIGINT) }
            }

            // 20초 안에 안 내려가면 강제 종료로 승격
            try? await Task.sleep(for: .seconds(20))
            guard let target, runner.process === target, target.isRunning else { return }
            runner.log.append(String(localized: "Stop is taking too long; forcing termination."))
            let remaining = await RunnerDiscovery.processIDs(inTree: runner.directory)
            for pid in remaining { kill(pid, SIGTERM) }
            try? await Task.sleep(for: .seconds(3))
            if runner.process === target, target.isRunning {
                target.terminate()
            }
        }
    }

    func restart(_ runner: ManagedRunner) {
        guard runner.local.isAppManaged else { return }
        runner.pendingRestart = true
        stopNow(runner)
    }

    // MARK: - 종료 처리

    func handleTermination(of runner: ManagedRunner, status: Int32) {
        runner.process = nil
        let uptime = runner.lastStartDate.map { Date().timeIntervalSince($0) } ?? 0
        if uptime > 60 {
            runner.consecutiveFailures = 0
        }

        switch runner.local {
        case .stopping, .stopPending:
            runner.local = .stopped
            runner.log.append(String(localized: "Runner stopped."))
            if runner.pendingRestart {
                runner.pendingRestart = false
                start(runner)
            }

        default:
            runner.log.append(String(localized: "Runner exited unexpectedly (code \(Int(status)))."))
            if runner.autoRestart, runner.consecutiveFailures < 3 {
                runner.consecutiveFailures += 1
                runner.local = .stopped
                runner.log.append(String(localized: "Restarting automatically in 5 seconds. (\(runner.consecutiveFailures)/3)"))
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if case .stopped = runner.local {
                        self.start(runner)
                    }
                }
            } else {
                runner.local = .failed(String(localized: "Exited unexpectedly (code \(Int(status)))"))
            }
        }
    }

    // MARK: - 고아 프로세스 연결

    /// 앱 밖에서 실행 중인 러너 트리를 정리하고 앱 관리로 다시 시작한다.
    func adoptOrphan(_ runner: ManagedRunner) {
        guard case .orphan = runner.local else { return }
        runner.local = .stopping
        runner.log.append(String(localized: "Cleaning up the existing process and switching to app management…"))
        Task {
            var pids = await RunnerDiscovery.processIDs(inTree: runner.directory)
            for pid in pids { kill(pid, SIGINT) }
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                pids = await RunnerDiscovery.processIDs(inTree: runner.directory)
                if pids.isEmpty { break }
            }
            if !pids.isEmpty {
                for pid in pids { kill(pid, SIGTERM) }
                try? await Task.sleep(for: .seconds(2))
            }
            runner.local = .stopped
            self.start(runner)
        }
    }

    // MARK: - 시스템 서비스 전환

    /// svc.sh uninstall 로 시스템 서비스를 해제하고 앱 관리로 시작한다.
    func migrateFromService(_ runner: ManagedRunner) {
        guard case .service = runner.local else { return }
        runner.local = .stopping
        runner.log.append(String(localized: "Removing the system service… (svc.sh uninstall)"))
        Task {
            let result = await Shell.run("/bin/bash", ["./svc.sh", "uninstall"], currentDirectory: runner.directory)
            guard result.status == 0 else {
                runner.local = .failed(String(localized: "Failed to remove the service"))
                runner.log.append(String(localized: "Couldn't remove the service: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
                return
            }
            runner.log.append(String(localized: "Service removed. The app now manages this runner."))
            try? await Task.sleep(for: .seconds(2))
            runner.local = .stopped
            self.start(runner)
        }
    }

    // MARK: - 앱 종료 지원

    var appManagedRunningCount: Int {
        runners.filter { $0.local.isAppManaged }.count
    }

    var appManagedBusyCount: Int {
        runners.filter { $0.local.isAppManaged && $0.remote.isBusy }.count
    }

    /// 종료 전 앱 관리 러너를 모두 정지하고 완료까지 기다린다 (최대 30초).
    func stopAllForQuit() async {
        let targets = runners.filter { $0.local.isAppManaged }
        for runner in targets {
            stopNow(runner)
        }
        for _ in 0..<30 {
            if targets.allSatisfy({ !($0.process?.isRunning ?? false) }) { break }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// 러너를 실행 상태로 둔 채 종료할 때: 종료 핸들러만 끊는다.
    /// 러너 출력은 파일로 가고 있으므로 앱이 죽어도 SIGPIPE 위험이 없다.
    func detachAllForQuit() {
        for runner in runners {
            runner.process?.terminationHandler = nil
            runner.process = nil
        }
    }
}
