//
//  annoying_habitsApp.swift
//  annoying-habits
//
//  Created by Samuel Fronthaler on 22.06.26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct annoying_habitsApp: App {
    private let notificationDelegate = NotificationDelegate()
    private let viewModel = HabitsViewModel()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(for: [Habit.self, HabitCompletion.self])
    }
}
