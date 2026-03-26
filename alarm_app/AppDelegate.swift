//  AppDelegate.swift — alarm_app

import UIKit
import SwiftUI
import AlarmKit

extension Notification.Name {
    static let deviceTokenReceived = Notification.Name("deviceTokenReceived")
}

class AppDelegate: NSObject, UIApplicationDelegate {

    /// Latest APNs device token — shared with AlarmViewModel so it can register with the server.
    static var deviceToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    // Print device token and broadcast so AlarmViewModel can send it to the relay server
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 Device token: \(token)")
        AppDelegate.deviceToken = token
        NotificationCenter.default.post(name: .deviceTokenReceived, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on simulator — xcrun simctl push bypasses APNs and still works
        print("ℹ️ APNs skipped (simulator): \(error.localizedDescription)")
    }

    // Fires when a silent push arrives — even when the app is closed
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let event = userInfo["event"] as? String, event == "alarm_ringing",
              let seconds = userInfo["countdown"] as? Int else {
            completionHandler(.noData); return
        }
        Task { @MainActor in await AppDelegate.fireAlarm(seconds: seconds) }
        completionHandler(.newData)
    }

    @MainActor
    static func fireAlarm(seconds: Int) async {
        let attrs = AlarmAttributes<EmptyMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Alarm!")),
            tintColor: .red
        )
        _ = try? await AlarmManager.shared.schedule(id: UUID(), configuration: .timer(duration: TimeInterval(seconds), attributes: attrs))
    }
}
