//
//  RunningCrewApp.swift
//  RunningCrew
//
//  GitHub self-hosted runner 를 자식 프로세스로 관리하는 상시 실행 메뉴바 앱.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        alert.messageText = "실행 중인 러너가 \(running)개 있어요"
        alert.informativeText = busy > 0
            ? "지금 \(busy)개 러너가 작업을 실행하고 있어요. 정지하면 실행 중인 작업이 취소돼요. 실행 상태로 두면 러너는 계속 돌고, 다음에 앱을 열 때 다시 연결할 수 있어요."
            : "정지하고 종료할까요? 실행 상태로 두면 러너는 계속 돌고, 다음에 앱을 열 때 다시 연결할 수 있어요."
        alert.addButton(withTitle: "정지 후 종료")
        alert.addButton(withTitle: "실행 상태로 두고 종료")
        alert.addButton(withTitle: "취소")

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
