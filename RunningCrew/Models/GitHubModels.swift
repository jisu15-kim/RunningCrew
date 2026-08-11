//
//  GitHubModels.swift
//  RunningCrew
//
//  GitHub REST API 응답 모델 (JSONDecoder .convertFromSnakeCase 사용)
//

import Foundation

struct GHUser: Decodable {
    let login: String
}

struct GHRunnerList: Decodable {
    let runners: [GHRunner]
}

struct GHRunner: Decodable {
    let id: Int
    let name: String
    let status: String       // "online" / "offline"
    let busy: Bool
    let labels: [GHLabel]?
}

struct GHLabel: Decodable {
    let name: String
}

struct GHWorkflowRuns: Decodable {
    let workflowRuns: [GHRun]
}

struct GHRun: Decodable {
    let id: Int
    let name: String?
    let headBranch: String?
}

struct GHJobs: Decodable {
    let jobs: [GHJob]
}

struct GHJob: Decodable {
    let name: String
    let status: String       // "queued" / "in_progress" / "completed"
    let runnerName: String?
    let startedAt: String?
    let workflowName: String?
    let htmlUrl: String?
    let headBranch: String?
}
