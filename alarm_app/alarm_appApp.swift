//
//  alarm_appApp.swift
//  alarm_app
//
//  Created by Malcolm Kuo on 2026/3/11.
//

import SwiftUI

@main
struct alarm_appApp: App {
    // This line connects the AppDelegate to the SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
