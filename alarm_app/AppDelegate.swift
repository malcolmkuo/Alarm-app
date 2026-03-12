//  AppDelegate.swift — alarm_app

import UIKit
import SwiftUI
import AlarmKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    // Print device token so you can send it to your server for APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 Device token: \(token)")
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
        let stop = AlarmButton(text: "Stop", textColor: .red, systemImageName: "stop.circle")
        let attrs = AlarmAttributes<EmptyMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Alarm!", stopButton: stop)),
            tintColor: .red
        )
        _ = try? await AlarmManager.shared.schedule(id: UUID(), configuration: .timer(duration: TimeInterval(seconds), attributes: attrs))
    }
}
