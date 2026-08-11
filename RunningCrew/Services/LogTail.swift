//
//  LogTail.swift
//  RunningCrew
//
//  러너 로그 파일을 폴링으로 tail 해서 RunnerLog 버퍼로 흘린다.
//  러너 출력을 파이프 대신 파일로 받는 구조의 짝. 파일 기반이라
//  앱을 재시작해도 이전 로그 꼬리를 이어서 볼 수 있다.
//

import Foundation

final class LogTail {
    private let url: URL
    private let log: RunnerLog
    private var task: Task<Void, Never>?
    private var offset: UInt64 = 0
    private var pending = ""

    init(url: URL, log: RunnerLog) {
        self.url = url
        self.log = log
    }

    func start() {
        guard task == nil else { return }
        seekToRecent()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 최초 시작 시 파일 끝 부근(최근 16KB)부터 읽는다.
    private func seekToRecent() {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? UInt64 ?? 0
        offset = size > 16_384 ? size - 16_384 : 0
    }

    private func poll() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // 파일이 교체되거나 줄어듦 (로테이션)
            offset = 0
            pending = ""
        }
        guard size > offset,
              (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: Int(min(size - offset, 512_000))),
              !data.isEmpty else { return }
        offset += UInt64(data.count)
        pending += String(decoding: data, as: UTF8.self)
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending = String(pending[pending.index(after: newline)...])
            if !line.isEmpty {
                log.append(line)
            }
        }
    }
}
