import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    let viewModel: HabitsViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Habit.createdAt, order: .reverse) private var habits: [Habit]
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue

    @State private var showingAddHabit = false
    @State private var showingSettings = false
    @State private var selectedHabit: Habit?
    @State private var selectedDay: HabitDaySelection?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        summaryCard
                        notificationBanner

                        if habits.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(habits) { habit in
                                    HabitCardView(
                                        habit: habit,
                                        viewModel: viewModel,
                                        modelContext: modelContext,
                                        onSelectDay: { selectedDay = HabitDaySelection(habit: habit, date: $0) },
                                        onOpenHabit: { selectedHabit = habit }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddHabit) {
            AddHabitView(viewModel: viewModel, modelContext: modelContext)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel, modelContext: modelContext)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
        .sheet(item: $selectedHabit) { habit in
            HabitEditorView(
                habit: habit,
                viewModel: viewModel,
                modelContext: modelContext
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(28)
        }
        .sheet(item: $selectedDay) { selection in
            HabitDayDetailView(
                habit: selection.habit,
                date: selection.date,
                viewModel: viewModel,
                modelContext: modelContext
            )
            .presentationDetents([.medium])
            .presentationCornerRadius(28)
        }
        .task(id: habits.map(\.id)) {
            await refreshNotifications()
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshNotifications()
                await refreshNotificationStatus()
            }
        }
        .preferredColorScheme(currentAppearance.colorScheme)
    }

    private var currentAppearance: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var effectiveColorScheme: ColorScheme {
        currentAppearance.colorScheme ?? colorScheme
    }

    private var background: some View {
        let palette: [Color] = effectiveColorScheme == .light
            ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.92, green: 0.95, blue: 0.98), Color(red: 0.87, green: 0.90, blue: 0.96)]
            : [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.08, green: 0.10, blue: 0.14), Color.black]

        return LinearGradient(
            colors: palette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            RadialGradient(
                colors: [Color.primary.opacity(effectiveColorScheme == .light ? 0.08 : 0.10), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 320
            )
            .blendMode(.screen)
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Annoying Habits")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            HStack(spacing: 10) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(Color.primary.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open settings")

                Button {
                    showingAddHabit = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
                }
                .accessibilityLabel("Add habit")
            }
        }
    }

    private var summaryCard: some View {
        let completedToday = habits.filter { viewModel.isCompleted($0) }.count
        let totalHabits = habits.count
        let strongestStreak = habits.map { $0.currentStreak() }.max() ?? 0

        return HStack(alignment: .center, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.55))
                    Text("\(completedToday)/\(totalHabits)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Streak")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.55))
                    Text("\(strongestStreak)d")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var notificationBanner: some View {
        Group {
            if notificationStatus == .denied {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.35), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reminders are off")
                            .foregroundStyle(.primary)
                            .font(.headline)
                        Text("Enable notifications in Settings to get the nagging reminders.")
                            .foregroundStyle(.primary.opacity(0.72))
                            .font(.subheadline)
                    }

                    Spacer()

                    Button("Enable") {
                        Task {
                            _ = await viewModel.requestNotificationAccess()
                            await refreshNotificationStatus()
                            await refreshNotifications()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(.black)
                }
                .padding(16)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else if notificationStatus == .notDetermined {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color.blue.opacity(0.35), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Turn on reminders")
                            .foregroundStyle(.primary)
                            .font(.headline)
                        Text("The app can schedule nagging notifications for each habit.")
                            .foregroundStyle(.primary.opacity(0.72))
                            .font(.subheadline)
                    }

                    Spacer()

                    Button("Allow") {
                        Task {
                            _ = await viewModel.requestNotificationAccess()
                            await refreshNotificationStatus()
                            await refreshNotifications()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(.black)
                }
                .padding(16)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checklist.unchecked")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))

            Text("No habits yet")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("Add a habit to start filling the grid and let the reminders keep it annoying.")
                .foregroundStyle(.primary.opacity(0.75))
                .font(.subheadline)

            Button {
                showingAddHabit = true
            } label: {
                Text("Create your first habit")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(.black)
        }
        .padding(20)
        .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func refreshNotifications() async {
        await viewModel.refreshNotifications(for: habits)
    }

    private func refreshNotificationStatus() async {
        let settings = await viewModel.notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}

struct HabitCardView: View {
    let habit: Habit
    let viewModel: HabitsViewModel
    let modelContext: ModelContext
    let onSelectDay: (Date) -> Void
    let onOpenHabit: () -> Void

    @State private var isTogglingToday = false

    private var completedToday: Bool {
        viewModel.isCompleted(habit)
    }

    private var progress: Double {
        habit.completionRatio()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(habit.themeColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: habit.themeColor.opacity(0.6), radius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Reminder \(habit.reminderLabel)")
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.6))
                }

                Spacer()

                Menu {
                    Button {
                        Task { await toggleToday() }
                    } label: {
                        Label(completedToday ? "Mark incomplete" : "Mark completed", systemImage: completedToday ? "circle" : "checkmark.circle.fill")
                    }

                    Button(role: .destructive) {
                        deleteHabit()
                    } label: {
                        Label("Delete habit", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.primary.opacity(0.72))
                }
            }

            HStack(spacing: 8) {
                StatusPill(
                    title: completedToday ? "Done" : "Open",
                    icon: completedToday ? "checkmark.seal.fill" : "hourglass",
                    accent: completedToday ? habit.themeColor : .gray
                )

                StatusPill(
                    title: "\(habit.currentStreak())d",
                    icon: "flame.fill",
                    accent: habit.themeColor
                )

                Spacer(minLength: 0)

                Button {
                    Task { await toggleToday() }
                } label: {
                    Image(systemName: completedToday ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(completedToday ? habit.themeColor : .primary)
                        .frame(width: 32, height: 32)
                        .background((completedToday ? habit.themeColor : Color.primary).opacity(0.12), in: Circle())
                }
                .disabled(isTogglingToday)
                .accessibilityLabel(completedToday ? "Undo today" : "Complete today")
            }

            HabitContributionGridView(
                habit: habit,
                onSelectDay: onSelectDay
            )
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            onOpenHabit()
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func toggleToday() async {
        guard !isTogglingToday else { return }
        isTogglingToday = true
        defer { isTogglingToday = false }

        do {
            try viewModel.toggleCompletion(for: habit, context: modelContext)
            if viewModel.isCompleted(habit) {
                viewModel.cancelNotifications(for: habit)
            } else {
                await viewModel.refreshNotifications(for: [habit])
            }
        } catch {
            return
        }
    }

    private func deleteHabit() {
        do {
            try viewModel.deleteHabit(habit, context: modelContext)
        } catch {
            return
        }
    }
}

struct StatusPill: View {
    let title: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent.opacity(0.12), in: Capsule())
    }
}

struct HabitContributionGridView: View {
    let habit: Habit
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    private let dayCount = 126
    private let rows = 7
    private let columnSpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 3
    private let minimumCellSize: CGFloat = 10

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GeometryReader { proxy in
                let columns = columnsForHabit()
                let availableWidth = max(proxy.size.width, 1)
                let totalSpacing = CGFloat(max(columns.count - 1, 0)) * columnSpacing
                let calculatedCellSize = floor((availableWidth - totalSpacing) / CGFloat(max(columns.count, 1)))
                let cellSize = max(minimumCellSize, calculatedCellSize)
                let contentWidth = CGFloat(columns.count) * cellSize + CGFloat(max(columns.count - 1, 0)) * columnSpacing

                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: rowSpacing) {
                            ForEach(column) { day in
                                dayCell(for: day, size: cellSize)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .frame(width: max(contentWidth, availableWidth), alignment: .leading)
            }
            .frame(height: CGFloat(rows) * minimumCellSize + CGFloat(rows - 1) * rowSpacing + 3)
        }
    }

    private func columnsForHabit() -> [[ContributionDay]] {
        let padded = paddedContributionDays()
        return stride(from: 0, to: padded.count, by: rows).map { start in
            Array(padded[start..<min(start + rows, padded.count)])
        }
    }

    private func paddedContributionDays() -> [ContributionDay] {
        let start = calendar.startOfDay(for: .now)
        let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: start) ?? start
        let weekdayOffset = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7

        var days: [ContributionDay] = Array(repeating: .empty, count: weekdayOffset)
        days.append(contentsOf: (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return ContributionDay(date: day, isCompleted: habit.isCompleted(on: day, calendar: calendar))
        })

        let remainder = days.count % 7
        if remainder != 0 {
            days.append(contentsOf: Array(repeating: .empty, count: 7 - remainder))
        }

        return days
    }

    @ViewBuilder
    private func dayCell(for day: ContributionDay, size: CGFloat) -> some View {
        if let date = day.date {
            Button {
                onSelectDay(date)
            } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.isCompleted ? habit.themeColor : Color.gray.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(isToday(date) ? Color.primary.opacity(0.7) : .clear, lineWidth: 1)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: day.isCompleted ? habit.themeColor.opacity(0.35) : .clear, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: day, date: date))
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: size, height: size)
                .opacity(0.3)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func accessibilityLabel(for day: ContributionDay, date: Date) -> String {
        let status = day.isCompleted ? "completed" : "not completed"
        return "\(date.formatted(date: .abbreviated, time: .omitted)), \(status)"
    }
}

struct HabitEditorView: View {
    let habit: Habit
    let viewModel: HabitsViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: HabitColorOption
    @State private var reminderDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(habit: Habit, viewModel: HabitsViewModel, modelContext: ModelContext) {
        self.habit = habit
        self.viewModel = viewModel
        self.modelContext = modelContext
        _name = State(initialValue: habit.name)
        _selectedColor = State(initialValue: HabitColorOption.palette.first { $0.hex == habit.colorHex } ?? HabitColorOption.palette[0])

        let calendar = Calendar.current
        _reminderDate = State(initialValue: calendar.date(
            bySettingHour: habit.reminderHour,
            minute: habit.reminderMinute,
            second: 0,
            of: .now
        ) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                } header: {
                    Text("Habit")
                }

                Section {
                    DatePicker("Reminder time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Reminder")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                        ForEach(HabitColorOption.palette) { option in
                            Button {
                                selectedColor = option
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 20, height: 20)
                                    Text(option.name)
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedColor == option ? option.color.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selectedColor == option ? option.color : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Color")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveHabit() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveHabit() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let hour = components.hour ?? habit.reminderHour
        let minute = components.minute ?? habit.reminderMinute

        habit.name = trimmedName
        habit.colorHex = selectedColor.hex
        habit.reminderHour = hour
        habit.reminderMinute = minute

        do {
            try modelContext.save()
            await viewModel.refreshNotifications(for: [habit])
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HabitDayDetailView: View {
    let habit: Habit
    let date: Date
    let viewModel: HabitsViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false

    private var isCompleted: Bool {
        viewModel.isCompleted(habit, on: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.title2.bold())
                    Text(date.formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(habit.themeColor)
                    .frame(width: 16, height: 16)
            }

            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCompleted ? habit.themeColor : Color.secondary.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: isCompleted ? "checkmark" : "circle")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(isCompleted ? "Completed" : "Not completed")
                        .font(.headline)
                    Text(isCompleted ? "Tap undo to remove the completion for this day." : "Tap complete to fill this day in the grid.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            Button {
                Task { await toggleCompletion() }
            } label: {
                Text(isCompleted ? "Mark incomplete" : "Mark complete")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(habit.themeColor)
            .disabled(isBusy)

            Button("Close", role: .cancel) {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
        }
        .padding(20)
    }

    private func toggleCompletion() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try viewModel.toggleCompletion(for: habit, on: date, context: modelContext)
            guard Calendar.current.isDateInToday(date) else { return }

            if viewModel.isCompleted(habit, on: date) {
                viewModel.cancelNotifications(for: habit)
            } else {
                await viewModel.refreshNotifications(for: [habit])
            }
        } catch {
            return
        }
    }
}

struct AddHabitView: View {
    let viewModel: HabitsViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = HabitColorOption.palette[0]
    @State private var reminderDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Habit name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                } header: {
                    Text("Habit")
                }

                Section {
                    DatePicker("Reminder time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("The app will schedule four daily nudges from this starting time.")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                        ForEach(HabitColorOption.palette) { option in
                            Button {
                                selectedColor = option
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 20, height: 20)
                                    Text(option.name)
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedColor == option ? option.color.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selectedColor == option ? option.color : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Color")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveHabit() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveHabit() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0

        do {
            try viewModel.addHabit(
                name: trimmedName,
                colorHex: selectedColor.hex,
                reminderHour: hour,
                reminderMinute: minute,
                context: modelContext
            )
            _ = await viewModel.requestNotificationAccess()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HabitDaySelection: Identifiable {
    let habit: Habit
    let date: Date

    var id: String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(habit.id.uuidString)-\(formatter.string(from: date))"
    }
}
