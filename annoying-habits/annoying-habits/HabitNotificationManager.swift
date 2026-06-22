import Foundation
import UserNotifications

final class HabitNotificationManager {
    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    struct ReminderSlot {
        let offsetHours: Int
        let title: String
        let bodyPrefix: String
    }

    private let reminderSlots: [ReminderSlot] = [
        ReminderSlot(offsetHours: 0, title: "Time to act", bodyPrefix: "Do your habit:"),
        ReminderSlot(offsetHours: 3, title: "Still waiting", bodyPrefix: "Still not done:"),
        ReminderSlot(offsetHours: 6, title: "No escape", bodyPrefix: "You are avoiding it:"),
        ReminderSlot(offsetHours: 9, title: "Last reminder", bodyPrefix: "Last reminder:")
    ]
    private let scheduledDays = 7

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func refreshTodayReminders(for habits: [Habit]) async {
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let today = calendar.startOfDay(for: .now)
        let days = scheduledDates(startingAt: today)
        let identifiersToClear = habits.flatMap { habit in
            days.flatMap { reminderIdentifiers(for: habit, on: $0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiersToClear)
        center.removeDeliveredNotifications(withIdentifiers: identifiersToClear)

        for habit in habits {
            await scheduleReminders(for: habit, on: days)
        }
    }

    func cancelTodayReminders(for habit: Habit) {
        let today = calendar.startOfDay(for: .now)
        let identifiers = scheduledDates(startingAt: today).flatMap { reminderIdentifiers(for: habit, on: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func scheduleReminders(for habit: Habit, on days: [Date]) async {
        for day in days {
            guard let baseDate = calendar.date(
                bySettingHour: habit.reminderHour,
                minute: habit.reminderMinute,
                second: 0,
                of: day
            ) else {
                continue
            }

            guard !habit.isCompleted(on: day, calendar: calendar) else {
                continue
            }

            for (index, slot) in reminderSlots.enumerated() {
                guard let fireDate = calendar.date(byAdding: .hour, value: slot.offsetHours, to: baseDate) else {
                    continue
                }

                guard fireDate > .now else {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = slot.title
                content.body = "\(slot.bodyPrefix) \(habit.name)"
                content.sound = .default
                content.threadIdentifier = habit.id.uuidString
                content.userInfo = [
                    "habitID": habit.id.uuidString,
                    "habitName": habit.name,
                    "scheduledDay": dayKey(for: day)
                ]

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: reminderIdentifier(for: habit, on: day, slotIndex: index),
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                } catch {
                    continue
                }
            }
        }
    }

    private func scheduledDates(startingAt start: Date) -> [Date] {
        (0..<scheduledDays).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func reminderIdentifiers(for habit: Habit, on day: Date) -> [String] {
        reminderSlots.indices.map { reminderIdentifier(for: habit, on: day, slotIndex: $0) }
    }

    private func reminderIdentifier(for habit: Habit, on day: Date, slotIndex: Int) -> String {
        "annoying-habits.\(habit.id.uuidString).\(dayKey(for: day)).\(slotIndex)"
    }

    private func dayKey(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
