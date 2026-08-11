//
//  Theme.swift
//  RunningCrew
//
//  Toss Tech Design 스타일 디자인 토큰: 인지 속도와 신뢰를 우선한다.
//

import SwiftUI

enum Theme {
    /// Toss Blue (#3182F6) — 진행/작업 중 강조
    static let accent = Color(red: 0.192, green: 0.510, blue: 0.965)
    /// 대기(정상) 상태 (#00C471)
    static let running = Color(red: 0.0, green: 0.769, blue: 0.443)
    /// 작업 실행 중
    static let busy = accent
    /// 주의가 필요한 상태 (#FF9F14)
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.078)
    /// 실패/위험 (#F04452)
    static let danger = Color(red: 0.941, green: 0.267, blue: 0.322)

    static let cardCorner: CGFloat = 16
    static let spacing: CGFloat = 16
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

extension View {
    /// Toss 스타일 카드 컨테이너
    func card() -> some View {
        modifier(CardBackground())
    }
}
