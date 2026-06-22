import SwiftUI
import SwiftData

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        reminderHour: Int,
        reminderMinute: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
    }
}

@Model
final class HabitCompletion {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var habit: Habit?

    init(id: UUID = UUID(), completedAt: Date = .now, habit: Habit? = nil) {
        self.id = id
        self.completedAt = completedAt
        self.habit = habit
    }
}

struct HabitColorOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let hex: String

    var color: Color {
        Color(hex: hex)
    }
}

extension HabitColorOption {
    static let palette: [HabitColorOption] = [
        HabitColorOption(name: "Forest", hex: "1B8A70"),
        HabitColorOption(name: "Sky", hex: "3B82F6"),
        HabitColorOption(name: "Sun", hex: "F59E0B"),
        HabitColorOption(name: "Berry", hex: "E879F9"),
        HabitColorOption(name: "Mint", hex: "10B981"),
        HabitColorOption(name: "Slate", hex: "64748B"),
        HabitColorOption(name: "Rose", hex: "FB7185")
    ]
}

extension Habit {
    var themeColor: Color {
        Color(hex: colorHex)
    }

    var reminderLabel: String {
        let components = DateComponents(hour: reminderHour, minute: reminderMinute)
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var completedDaysCount: Int {
        completions.count
    }

    func completion(on day: Date, calendar: Calendar = .current) -> HabitCompletion? {
        completions.first { calendar.isDate($0.completedAt, inSameDayAs: day) }
    }

    func isCompleted(on day: Date, calendar: Calendar = .current) -> Bool {
        completion(on: day, calendar: calendar) != nil
    }

    func completionRatio(lastDays: Int = 90, calendar: Calendar = .current) -> Double {
        let days = recentDays(count: lastDays, calendar: calendar)
        guard !days.isEmpty else { return 0 }

        let completed = days.filter { isCompleted(on: $0, calendar: calendar) }.count
        return Double(completed) / Double(days.count)
    }

    func currentStreak(calendar: Calendar = .current) -> Int {
        var streak = 0
        var day = calendar.startOfDay(for: .now)

        while isCompleted(on: day, calendar: calendar) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    func recentDays(count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: .now)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start)
        }.reversed()
    }

    func contributionDays(lastDays: Int = 90, calendar: Calendar = .current) -> [ContributionDay] {
        let start = calendar.startOfDay(for: .now)
        let startDate = calendar.date(byAdding: .day, value: -(lastDays - 1), to: start) ?? start
        let firstWeekday = calendar.firstWeekday - 1
        let startWeekday = calendar.component(.weekday, from: startDate) - 1
        let leadingPadding = (startWeekday - firstWeekday + 7) % 7

        var days: [ContributionDay] = Array(repeating: .empty, count: leadingPadding)
        days.append(contentsOf: recentDays(count: lastDays, calendar: calendar).map { day in
            ContributionDay(date: day, isCompleted: isCompleted(on: day, calendar: calendar))
        })

        let remainder = days.count % 7
        if remainder != 0 {
            days.append(contentsOf: Array(repeating: .empty, count: 7 - remainder))
        }

        return days
    }
}

struct ContributionDay: Identifiable, Hashable {
    let id = UUID()
    let date: Date?
    let isCompleted: Bool

    static let empty = ContributionDay(date: nil, isCompleted: false)
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue: Double
        switch cleaned.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
        default:
            red = 0.2
            green = 0.7
            blue = 0.5
        }

        self.init(red: red, green: green, blue: blue)
    }

    var hexDescription: String {
        "#"
    }
}
