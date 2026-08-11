//
//  RunnerDiscovery.swift
//  RunningCrew
//
//  머신에 설치된 self-hosted runner 를 찾는다.
//  1) ~/Library/LaunchAgents 의 actions.runner.*.plist (svc.sh 설치본)
//  2) 실행 중인 Runner.Listener 프로세스
//  3) 홈 디렉토리 얕은 스캔 (.runner 파일 존재 여부)
//

import Foundation

struct DiscoveredProcess {
    let pid: Int32
    let directory: URL
}

enum RunnerDiscovery {
    /// svc.sh 로 설치된 LaunchAgent 목록: [러너 디렉토리: launchd 라벨]
    static func launchAgentServices() -> [URL: String] {
        let fm = FileManager.default
        let agentsDir = fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents")
        guard let files = try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [URL: String] = [:]
        for file in files
        where file.lastPathComponent.hasPrefix("actions.runner.") && file.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let workingDir = plist["WorkingDirectory"] as? String,
                  let label = plist["Label"] as? String else { continue }
            result[URL(fileURLWithPath: workingDir).standardizedFileURL] = label
        }
        return result
    }

    /// 실행 중인 Runner.Listener 프로세스를 러너 디렉토리와 함께 반환
    static func runningListeners() async -> [DiscoveredProcess] {
        let result = await Shell.run("/usr/bin/pgrep", ["-fl", "Runner.Listener"])
        var found: [DiscoveredProcess] = []
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            let command = String(parts[1])
            guard let range = command.range(of: "/bin/Runner.Listener"),
                  command.hasPrefix("/") else { continue }
            let directory = URL(fileURLWithPath: String(command[..<range.lowerBound])).standardizedFileURL
            found.append(DiscoveredProcess(pid: pid, directory: directory))
        }
        return found
    }

    /// 러너 디렉토리 경로가 커맨드라인에 포함된 모든 프로세스 PID.
    /// run.sh, run-helper.sh, Runner.Listener, Runner.Worker 가 모두 잡힌다.
    static func processIDs(inTree directory: URL) async -> [Int32] {
        let result = await Shell.run("/usr/bin/pgrep", ["-f", directory.path + "/"])
        return result.stdout.split(separator: "\n").compactMap {
            Int32($0.trimmingCharacters(in: .whitespaces))
        }
    }

    /// 홈 디렉토리를 얕게 (depth 2) 스캔해 .runner 파일이 있는 디렉토리를 찾는다
    static func scanHomeForRunners() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let skip: Set<String> = [
            "Library", "Applications", "Pictures", "Music", "Movies", "Public",
            "node_modules", ".Trash",
        ]
        var found: [URL] = []

        func hasRunnerFile(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appending(path: ".runner").path)
        }

        guard let level1 = try? fm.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for dir in level1 {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !skip.contains(dir.lastPathComponent) else { continue }
            if hasRunnerFile(dir) {
                found.append(dir.standardizedFileURL)
                continue
            }
            guard let level2 = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for sub in level2 {
                guard (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      !skip.contains(sub.lastPathComponent) else { continue }
                if hasRunnerFile(sub) {
                    found.append(sub.standardizedFileURL)
                }
            }
        }
        return found
    }

    /// 러너 디렉토리의 .runner 설정 파일을 읽는다 (UTF-8 BOM 포함 대응)
    static func loadConfig(at directory: URL) -> RunnerFileConfig? {
        let file = directory.appending(path: ".runner")
        guard var data = try? Data(contentsOf: file) else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data.removeFirst(3)
        }
        return try? JSONDecoder().decode(RunnerFileConfig.self, from: data)
    }
}
