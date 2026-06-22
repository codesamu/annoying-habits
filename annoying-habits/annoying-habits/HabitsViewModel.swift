import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class HabitsViewModel {
    private let notificationManager = HabitNotificationManager()

    func requestNotificationAccess() async -> Bool {
        await notificationManager.requestAuthorization()
    }

    func notificationSettings() async -> UNNotificationSettings {
        await notificationManager.notificationSettings()
    }

    func refreshNotifications(for habits: [Habit]) async {
        await notificationManager.refreshTodayReminders(for: habits)
    }

    func cancelNotifications(for habit: Habit) {
        notificationManager.cancelTodayReminders(for: habit)
    }

    func addHabit(
        name: String,
        colorHex: String,
        reminderHour: Int,
        reminderMinute: Int,
        context: ModelContext
    ) throws {
        let habit = Habit(
            name: name,
            colorHex: colorHex,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        context.insert(habit)
        try context.save()
    }

    func deleteHabit(_ habit: Habit, context: ModelContext) throws {
        context.delete(habit)
        try context.save()
        cancelNotifications(for: habit)
    }

    func resetAllData(context: ModelContext) throws {
        let habitFetch = FetchDescriptor<Habit>()
        let completionFetch = FetchDescriptor<HabitCompletion>()
        let habits = try context.fetch(habitFetch)
        let completions = try context.fetch(completionFetch)

        for completion in completions {
            context.delete(completion)
        }

        for habit in habits {
            context.delete(habit)
        }

        try context.save()
        notificationManager.cancelAllNotifications()
    }

    func toggleCompletion(for habit: Habit, on date: Date = .now, context: ModelContext) throws {
        let calendar = Calendar.current
        let matchingCompletions = habit.completions.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }

        if matchingCompletions.isEmpty {
            let completion = HabitCompletion(completedAt: date, habit: habit)
            context.insert(completion)
        } else {
            for completion in matchingCompletions {
                context.delete(completion)
            }
        }

        try context.save()

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    func isCompleted(_ habit: Habit, on date: Date = .now) -> Bool {
        habit.isCompleted(on: date)
    }

    func selectedCompletionStatus(for habit: Habit, on date: Date) -> HabitCompletion? {
        habit.completion(on: date)
    }
}
