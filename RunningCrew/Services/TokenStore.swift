//
//  TokenStore.swift
//  RunningCrew
//
//  GitHub 토큰을 Keychain 에 보관한다.
//

import Foundation
import Security

enum TokenStore {
    private static let service = "com.jisukim.running-crew.github-token"
    private static let account = "github"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 토큰을 저장하고 실패 시 OSStatus 를 반환한다 (성공이면 nil).
    static func save(_ token: String) -> OSStatus? {
        let data = Data(token.utf8)
        var add = baseQuery
        add[kSecValueData as String] = data
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 기존 항목(이전 빌드가 만든 것 포함)이 있으면 값 갱신을 시도
            status = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if status != errSecSuccess {
                SecItemDelete(baseQuery as CFDictionary)
                status = SecItemAdd(add as CFDictionary, nil)
            }
        }
        return status == errSecSuccess ? nil : status
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// gh CLI 에 로그인된 토큰을 가져온다 (`gh auth token`).
    static func importFromGHCLI() async -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let result = await Shell.run(gh, ["auth", "token"])
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !token.isEmpty else { return nil }
        return token
    }
}
