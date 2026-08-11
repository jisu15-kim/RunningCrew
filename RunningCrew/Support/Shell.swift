//
//  Shell.swift
//  RunningCrew
//
//  외부 명령 실행 헬퍼 (pgrep, gh, svc.sh 등 짧은 명령 전용)
//

import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// 파이프 출력을 스레드 안전하게 누적하는 버퍼.
nonisolated final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

enum Shell {
    /// 명령을 실행하고 종료까지 기다린다. 출력이 짧은 명령에만 사용할 것.
    static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) async -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outCollector = PipeCollector()
        let errCollector = PipeCollector()
        outPipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            outCollector.append(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            errCollector.append(handle.availableData)
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { @Sendable p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                outCollector.append(outPipe.fileHandleForReading.availableData)
                errCollector.append(errPipe.fileHandleForReading.availableData)
                continuation.resume(returning: ShellResult(
                    status: p.terminationStatus,
                    stdout: outCollector.text,
                    stderr: errCollector.text
                ))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ShellResult(status: -1, stdout: "", stderr: error.localizedDescription))
            }
        }
    }
}
