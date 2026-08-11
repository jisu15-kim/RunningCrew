//
//  RunningCrewApp.swift
//  RunningCrew
//
//  GitHub self-hosted runner 를 자식 프로세스로 관리하는 상시 실행 메뉴바 앱.
//

import SwiftUI
import AppKit
import Sparkle

/// Sparkle 자동 업데이트 컨트롤러 (앱 수명 동안 단일 인스턴스)
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updater.controller // 런치 시 자동 업데이트 체크 시작
        Task {
            await AppModel.shared.bootstrap()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 메뉴바 상주
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        let running = model.appManagedRunningCount
        guard running > 0 else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        let busy = model.appManagedBusyCount
        let alert = NSAlert()
        alert.messageText = String(localized: "\(running) runners are still running")
        alert.informativeText = busy > 0
            ? String(localized: "\(busy) runners are running jobs right now. Stopping cancels those jobs. If you keep them running, they continue in the background and you can reconnect next time you open the app.")
            : String(localized: "Stop the runners and quit? If you keep them running, they continue in the background and you can reconnect next time you open the app.")
        alert.addButton(withTitle: String(localized: "Stop and Quit"))
        alert.addButton(withTitle: String(localized: "Keep Running and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await model.stopAllForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            model.detachAllForQuit()
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

@main
struct RunningCrewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("RunningCrew", id: "main") {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 720, height: 640)
        .defaultLaunchBehavior(.suppressed) // 메뉴바 상주 앱: 시작 시 창을 열지 않는다
        .commands {
            // ⌘Q 는 앱 종료가 아니라 창 닫기로 동작한다. 실제 종료는 메뉴바 패널의 Quit 으로.
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
        } label: {
            if model.hasWarning {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                Image("MenuBarIcon")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
