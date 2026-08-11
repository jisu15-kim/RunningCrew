//
//  GitHubClient.swift
//  RunningCrew
//

import Foundation

struct GitHubClient {
    let token: String

    enum ClientError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(401): return String(localized: "The token is invalid")
            case .http(403): return String(localized: "Insufficient permissions or rate limit exceeded")
            case .http(404): return String(localized: "Can't access the repository (admin permission required)")
            case .http(let code): return String(localized: "GitHub request failed (HTTP \(code))")
            }
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(string: "https://api.github.com/\(path)") else {
            throw URLError(.badURL)
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.http(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func user() async throws -> GHUser {
        try await get("user")
    }

    func runners(in repo: RepoRef) async throws -> [GHRunner] {
        let list: GHRunnerList = try await get(
            "\(repo.apiPath)/actions/runners",
            query: [URLQueryItem(name: "per_page", value: "100")]
        )
        return list.runners
    }

    /// 진행 중인 워크플로우 런의 job 목록 (runner_name 으로 러너와 매칭)
    func inProgressJobs(in repo: RepoRef) async throws -> [GHJob] {
        let runs: GHWorkflowRuns = try await get(
            "\(repo.apiPath)/actions/runs",
            query: [
                URLQueryItem(name: "status", value: "in_progress"),
                URLQueryItem(name: "per_page", value: "20"),
            ]
        )
        var jobs: [GHJob] = []
        for run in runs.workflowRuns {
            let response: GHJobs = try await get(
                "\(repo.apiPath)/actions/runs/\(run.id)/jobs",
                query: [URLQueryItem(name: "per_page", value: "50")]
            )
            jobs.append(contentsOf: response.jobs.filter { $0.status == "in_progress" })
        }
        return jobs
    }
}
