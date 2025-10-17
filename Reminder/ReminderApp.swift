//
//  ReminderApp.swift
//  Reminder
//
//  Created by Yilun Zhu on 10/9/25.
//

import SwiftUI

@main
struct ReminderApp: App {
    
    // ⚠️ 使用 @StateObject 确保管理器实例在整个应用生命周期中只被创建一次
    @StateObject private var manager = ReminderManager()

    // 2. 使用 @UIApplicationDelegateAdaptor 将 NotificationDelegate 挂接到 App 生命周期
    @UIApplicationDelegateAdaptor(AppDelegateAdapter.self) var appDelegateAdapter

    init() {
        // 3. 在初始化时，将 manager 实例传递给 NotificationDelegate
        // 这样代理在被唤醒时就能访问并调用 manager.resetTask()
        appDelegateAdapter.delegate.manager = manager
    }

    var body: some Scene {
        WindowGroup {
            // 4. 将 @StateObject 实例传递给 ContentView
            ContentView(manager: manager)
        }
    }
}

// 辅助结构体：将 NotificationDelegate 包装成 UIApplicationDelegate
class AppDelegateAdapter: NSObject, UIApplicationDelegate {
    let delegate = NotificationDelegate()
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // ⚠️ 在 App 启动时，立即设置我们自定义的代理
        UNUserNotificationCenter.current().delegate = delegate
        return true
    }
}
