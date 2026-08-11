//
//  AppModel+GitHub.swift
//  RunningCrew
//
//  GitHub 토큰 관리와 원격 상태 폴링.
//

import Foundation

extension AppModel {
    // MARK: - 토큰

    func loadToken() async {
        guard let token = TokenStore.load() else {
            tokenState = .missing
            return
        }
        await validate(token: token)
    }

    func setToken(_ token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        // 먼저 검증해서 연결부터 성립시키고, Keychain 저장은 best-effort 로 한다.
        await validate(token: token)
        guard case .connected = tokenState else { return }
        if let status = TokenStore.save(token) {
            tokenPersistenceFailed = true
            NSLog("TokenStore.save failed: OSStatus \(status)")
        } else {
            tokenPersistenceFailed = false
        }
        await syncWithGitHub()
    }

    func importTokenFromGHCLI() async {
        tokenState = .validating
        guard let token = await TokenStore.importFromGHCLI() else {
            tokenState = .invalid(String(localized: "Couldn't get a token from the gh CLI. Check gh auth status in Terminal."))
            return
        }
        await setToken(token)
    }

    func disconnectGitHub() {
        TokenStore.delete()
        activeToken = nil
        tokenPersistenceFailed = false
        tokenState = .missing
        for runner in runners {
            runner.remote = .notConnected
            runner.activeJob = nil
        }
    }

    private func validate(token: String) async {
        tokenState = .validating
        do {
            let user = try await GitHubClient(token: token).user()
            activeToken = token
            tokenState = .connected(login: user.login)
        } catch {
            tokenState = .invalid(error.localizedDescription)
        }
    }

    // MARK: - 폴링

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncWithGitHub()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func syncWithGitHub() async {
        guard case .connected = tokenState, let token = activeToken else {
            for runner in runners {
                runner.remote = .notConnected
                runner.activeJob = nil
            }
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        // repo 를 알 수 없는 러너 (GHE 등) 는 원격 상태를 판단하지 않는다
        for runner in runners where runner.repo == nil {
            runner.remote = .unknown
            runner.activeJob = nil
        }

        let client = GitHubClient(token: token)
        let repos = Set(runners.compactMap(\.repo))

        for repo in repos {
            let repoRunners = runners.filter { $0.repo == repo }
            do {
                let ghRunners = try await client.runners(in: repo)
                var jobs: [GHJob] = []
                if ghRunners.contains(where: \.busy) {
                    jobs = (try? await client.inProgressJobs(in: repo)) ?? []
                }
                for runner in repoRunners {
                    apply(ghRunners: ghRunners, jobs: jobs, to: runner)
                }
                lastSync = Date()
            } catch {
                for runner in repoRunners {
                    // 확인할 수 없는 상태를 정직하게 표시: 낡은 job 정보도 지운다
                    runner.remote = .unknown
                    runner.activeJob = nil
                }
            }
        }
    }

    private func apply(ghRunners: [GHRunner], jobs: [GHJob], to runner: ManagedRunner) {
        guard let gh = ghRunners.first(where: { $0.name == runner.name }) else {
            runner.remote = .notFound
            runner.activeJob = nil
            return
        }
        runner.remote = gh.status == "online" ? .online(busy: gh.busy) : .offline
        if let labels = gh.labels, !labels.isEmpty {
            runner.labels = labels.map(\.name)
        }

        if gh.busy, let job = jobs.first(where: { $0.runnerName == runner.name }) {
            runner.activeJob = ActiveJob(
                workflowName: job.workflowName ?? String(localized: "Workflow"),
                jobName: job.name,
                branch: job.headBranch,
                startedAt: job.startedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                htmlURL: job.htmlUrl.flatMap(URL.init(string:))
            )
        } else if gh.busy {
            runner.activeJob = ActiveJob(
                workflowName: String(localized: "Running a job"),
                jobName: "",
                branch: nil,
                startedAt: nil,
                htmlURL: nil
            )
        } else {
            runner.activeJob = nil
        }

        // "작업 끝나면 정지" 예약 처리 — 폴링 스냅샷은 낡았을 수 있으므로
        // 한 번 더 새로 조회해 여전히 idle 일 때만 정지한다
        if case .stopPending = runner.local, !gh.busy {
            Task { await self.confirmIdleThenStop(runner) }
        }
    }

    /// 정지 예약 실행 전 재확인: 그 사이 새 job 이 시작됐다면 취소하지 않도록.
    private func confirmIdleThenStop(_ runner: ManagedRunner) async {
        guard case .stopPending = runner.local,
              let repo = runner.repo,
              let token = activeToken else { return }
        guard let fresh = try? await GitHubClient(token: token).runners(in: repo),
              let gh = fresh.first(where: { $0.name == runner.name }) else { return }
        guard case .stopPending = runner.local else { return }
        if !gh.busy {
            runner.log.append(String(localized: "Job finished; running the scheduled stop."))
            stopNow(runner)
        }
    }
}
