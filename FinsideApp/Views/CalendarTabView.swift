import SwiftUI

struct CalendarTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var events: [CalendarEvent] = []
    @State private var datesWithEvents: Set<String> = []
    @State private var isLoading = false
    @State private var selectedTypeFilter: CalendarEventType?
    @State private var selectedStatusFilter: EventStatusFilter?
    @State private var didScrollToToday = false
    @State private var swipeForward = true

    private let calendar = Calendar.current
    private let ruLocale = Locale(identifier: "ru_RU")

    /// Как в Finpro: окно дней вокруг «сегодня» для горизонтальной ленты.
    private var dayStrip: [Date] {
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: Date())) ?? Date()
        return (0 ..< 84).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var datesWithMarkers: Set<String> {
        var set = datesWithEvents
        for t in appState.taskItems {
            set.insert(dateISO(t.calendarPlacementDate))
        }
        return set
    }

    private var tasksForSelectedDate: [TaskItem] {
        appState.taskItems.filter {
            calendar.isDate($0.calendarPlacementDate, inSameDayAs: selectedDate)
        }
        .sorted { a, b in
            if a.priority != b.priority { return a.priority == .high }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Незавершённые задачи с датой в календаре строго раньше выбранного дня.
    private var pastIncompleteTasks: [TaskItem] {
        guard selectedTypeFilter == nil else { return [] }
        let selStart = calendar.startOfDay(for: selectedDate)
        return appState.taskItems.filter {
            !$0.isDone && calendar.startOfDay(for: $0.calendarPlacementDate) < selStart
        }
        .sorted { $0.calendarPlacementDate < $1.calendarPlacementDate }
    }

    private func taskDayStart(_ t: TaskItem) -> Date {
        calendar.startOfDay(for: t.calendarPlacementDate)
    }

    private func tasksMatchingStatus(_ filter: EventStatusFilter) -> [TaskItem] {
        let today = calendar.startOfDay(for: Date())
        return appState.taskItems.filter { t in
            switch filter {
            case .overdue: return !t.isDone && taskDayStart(t) < today
            case .upcoming: return !t.isDone && taskDayStart(t) >= today
            case .completed: return t.isDone
            }
        }
        .sorted { taskDayStart($0) < taskDayStart($1) }
    }

    private var selectedDateISO: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        applyFilters(events.filter { $0.dueDate == selectedDateISO })
    }

    private var allEventsFiltered: [CalendarEvent] {
        applyFilters(events)
    }

    private func applyFilters(_ source: [CalendarEvent]) -> [CalendarEvent] {
        var result = source
        if let typeFilter = selectedTypeFilter {
            result = result.filter { $0.eventType == typeFilter }
        }
        if let statusFilter = selectedStatusFilter {
            switch statusFilter {
            case .overdue: result = result.filter { $0.isOverdue }
            case .upcoming: result = result.filter { !$0.isCompleted && !$0.isOverdue }
            case .completed: result = result.filter { $0.isCompleted }
            }
        }
        return result
    }

    private var overdueCount: Int {
        let today = calendar.startOfDay(for: Date())
        let ev = events.filter(\.isOverdue).count
        let tasks = appState.taskItems.filter { !$0.isDone && taskDayStart($0) < today }.count
        return ev + tasks
    }

    private var upcomingCount: Int {
        let today = calendar.startOfDay(for: Date())
        let ev = events.filter { !$0.isCompleted && !$0.isOverdue }.count
        let tasks = appState.taskItems.filter { !$0.isDone && taskDayStart($0) >= today }.count
        return ev + tasks
    }

    private var completedCount: Int {
        events.filter(\.isCompleted).count + appState.taskItems.filter(\.isDone).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                CalendarLiquidBackdrop().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        dayStripView
                        summaryBar
                        typeFilterBar
                        eventsSection
                            .id(selectedDate.timeIntervalSince1970)
                            .transition(daySlideTransition)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.84), value: selectedDate)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .simultaneousGesture(daySwipeGesture)
            }
            .navigationTitle("Календарь")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        AvatarMenuButton()
                    }
                }
            }
            .task { await loadEvents() }
            .onChange(of: selectedDate) { oldDate, newDate in
                let oldMonth = calendar.component(.month, from: oldDate)
                let newMonth = calendar.component(.month, from: newDate)
                let oldYear = calendar.component(.year, from: oldDate)
                let newYear = calendar.component(.year, from: newDate)
                if oldMonth != newMonth || oldYear != newYear {
                    Task { await loadEvents() }
                }
            }
            .refreshable { await loadEvents() }
        }
    }

    private var daySlideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: swipeForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: swipeForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 48)
            .onEnded { value in
                let w = value.translation.width
                let h = value.translation.height
                guard abs(w) > abs(h), abs(w) > 56 else { return }
                let step = w < 0 ? 1 : -1
                shiftSelectedDay(by: step)
            }
    }

    private func ruRecordsLabel(_ n: Int) -> String {
        let n10 = n % 10
        let n100 = n % 100
        let word: String
        if n100 >= 11, n100 <= 14 {
            word = "записей"
        } else {
            switch n10 {
            case 1: word = "запись"
            case 2, 3, 4: word = "записи"
            default: word = "записей"
            }
        }
        return "\(n) \(word)"
    }

    private func shiftSelectedDay(by delta: Int) {
        swipeForward = delta > 0
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        let nextDay = calendar.startOfDay(for: next)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            selectedDate = nextDay
        }
        DashboardHaptics.lightImpact()
    }

    // MARK: - Day strip (как Finpro)

    private var dayStripView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(dayStrip, id: \.self) { day in
                        dayCell(day)
                            .id(day.timeIntervalSince1970)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear {
                guard !didScrollToToday else { return }
                let today = calendar.startOfDay(for: Date())
                selectedDate = today
                proxy.scrollTo(today.timeIntervalSince1970, anchor: .center)
                didScrollToToday = true
            }
            .onChange(of: selectedDate) { _, new in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    proxy.scrollTo(new.timeIntervalSince1970, anchor: .center)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let cellWidth: CGFloat = isToday ? 76 : 52
        let dayIso = dateISO(day)
        let hasEventsOnDay = datesWithMarkers.contains(dayIso)

        return Button {
            let previous = selectedDate
            swipeForward = day.timeIntervalSince1970 >= previous.timeIntervalSince1970
            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                selectedDate = calendar.startOfDay(for: day)
            }
            DashboardHaptics.lightImpact()
        } label: {
            VStack(spacing: 6) {
                Text(weekdayShort(day))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(dayNumber(day))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if hasEventsOnDay {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.9) : Color.accentColor)
                        .frame(width: 5, height: 5)
                } else {
                    Spacer()
                        .frame(height: 5)
                }
                if isToday {
                    Text("Сегодня")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: cellWidth, height: 78)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isToday && !isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.1) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = ruLocale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func dateISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: calendar.startOfDay(for: date))
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryPill(count: overdueCount, label: "Просрочено", tint: .red, status: .overdue)
            summaryPill(count: upcomingCount, label: "Предстоит", tint: .orange, status: .upcoming)
            summaryPill(count: completedCount, label: "Выполнено", tint: .green, status: .completed)
        }
    }

    private func summaryPill(count: Int, label: String, tint: Color, status: EventStatusFilter) -> some View {
        let isActive = selectedStatusFilter == status
        return Button {
            DashboardHaptics.lightImpact()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStatusFilter = isActive ? nil : status
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : (count > 0 ? tint : .secondary))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint)
                }
            }
            .liquidGlassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type Filter

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "Все", icon: "list.bullet", isSelected: selectedTypeFilter == nil) {
                    selectedTypeFilter = nil
                }
                ForEach(CalendarEventType.allCases) { type in
                    filterChip(
                        label: type.label,
                        icon: type.icon,
                        isSelected: selectedTypeFilter == type
                    ) {
                        selectedTypeFilter = selectedTypeFilter == type ? nil : type
                    }
                }
            }
        }
    }

    private func filterChip(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? .white : .primary)
            .liquidGlassChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let statusFilter = selectedStatusFilter {
                HStack {
                    Text(statusFilter.sectionTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { selectedStatusFilter = nil }
                    } label: {
                        Label("Сбросить", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                let statusEvents = allEventsFiltered.sorted { $0.dueDate < $1.dueDate }
                let statusTasks = tasksMatchingStatus(statusFilter)
                    .sorted { taskDayStart($0) < taskDayStart($1) }

                if statusEvents.isEmpty && statusTasks.isEmpty {
                    emptyFilterCard(statusFilter)
                } else {
                    ForEach(statusEvents) { event in
                        CalendarEventRow(event: event) {
                            await toggleEvent(event)
                        }
                    }
                    ForEach(statusTasks) { task in
                        CalendarTaskRow(task: task, showRelativeDay: true)
                    }
                }
            } else {
                HStack {
                    Text(selectedDateTitle)
                        .font(.headline)
                    Spacer()
                    let n = eventsForSelectedDate.count + (selectedTypeFilter == nil ? tasksForSelectedDate.count : 0)
                    Text(ruRecordsLabel(n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let showTasks = selectedTypeFilter == nil
                let noDayEntries = eventsForSelectedDate.isEmpty && (!showTasks || tasksForSelectedDate.isEmpty)
                let noPast = pastIncompleteTasks.isEmpty || !showTasks

                if noDayEntries && noPast {
                    emptyDayCard
                } else {
                    ForEach(eventsForSelectedDate) { event in
                        CalendarEventRow(event: event) {
                            await toggleEvent(event)
                        }
                    }

                    if showTasks {
                        ForEach(tasksForSelectedDate) { task in
                            CalendarTaskRow(task: task, showRelativeDay: false)
                        }

                        if !pastIncompleteTasks.isEmpty {
                            Text("Задачи с предыдущих дней")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)

                            ForEach(pastIncompleteTasks) { task in
                                CalendarTaskRow(task: task, showRelativeDay: true)
                            }
                        }
                    }
                }

                upcomingSection
            }
        }
    }

    private var selectedDateTitle: String {
        selectedDate.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(ruLocale)
        )
    }

    private var emptyDayCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("На эту дату записей нет")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .liquidGlassCard(cornerRadius: 16)
    }

    private func emptyFilterCard(_ filter: EventStatusFilter) -> some View {
        VStack(spacing: 10) {
            Image(systemName: filter.emptyIcon)
                .font(.system(size: 36, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(filter.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        let upcoming = allEventsFiltered
            .filter { !$0.isCompleted && $0.dueDate >= selectedDateISO }
            .prefix(5)

        return Group {
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ближайшие")
                        .font(.headline)
                        .padding(.top, 8)

                    ForEach(Array(upcoming)) { event in
                        CalendarEventRow(event: event) {
                            await toggleEvent(event)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadEvents() async {
        isLoading = true
        let cal = Calendar.current
        let month = cal.component(.month, from: selectedDate)
        let year = cal.component(.year, from: selectedDate)

        do {
            let response = try await APIService.shared.calendarEvents(month: month, year: year)
            events = response.events
            datesWithEvents = Set(response.datesWithEvents)
        } catch {
            #if DEBUG
            print("Calendar load error: \(error)")
            #endif
        }
        isLoading = false
    }

    private func toggleEvent(_ event: CalendarEvent) async {
        do {
            let updated = try await APIService.shared.toggleCalendarEvent(eventId: event.id)
            if let idx = events.firstIndex(where: { $0.id == updated.id }) {
                events[idx] = updated
            }
            DashboardHaptics.lightImpact()
        } catch {
            #if DEBUG
            print("Toggle error: \(error)")
            #endif
        }
    }
}

// MARK: - Event Row

struct CalendarEventRow: View {
    let event: CalendarEvent
    let onToggle: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isToggling = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                guard !isToggling else { return }
                isToggling = true
                Task {
                    await onToggle()
                    isToggling = false
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(event.type.tint.opacity(event.isCompleted ? 0.15 : 0.1))
                        .frame(width: 36, height: 36)
                    if event.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(event.type.tint)
                    } else {
                        Image(systemName: event.type.icon)
                            .font(.caption)
                            .foregroundStyle(event.type.tint)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(event.isCompleted, color: .secondary)
                        .foregroundStyle(event.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if event.isOverdue {
                        Text("Просрочено")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Label(event.formattedDueDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let amount = event.formattedAmount {
                        Label(amount, systemImage: "banknote")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(event.type.tint)
                    }
                }

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 14)
        .opacity(event.isCompleted ? 0.75 : 1)
    }
}

// MARK: - Task row (локальные задачи)

private struct CalendarTaskRow: View {
    @Environment(AppState.self) private var appState
    let task: TaskItem
    var showRelativeDay: Bool

    private var dayCaption: String {
        if showRelativeDay {
            let d = task.calendarPlacementDate
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.setLocalizedDateFormatFromTemplate("EEE dMMM")
            return f.string(from: d)
        }
        return task.calendarDetailLabel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                let becomesDone = !task.isDone
                TaskFeedback.toggle(toDone: becomesDone)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    appState.toggleTaskDone(id: task.id)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(task.isDone ? 0.12 : 0.14))
                        .frame(width: 36, height: 36)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.indigo)
                    } else {
                        Image(systemName: "checklist")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text("Задача")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.indigo, in: Capsule())
                }

                HStack(spacing: 8) {
                    Label(dayCaption, systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                    if task.priority == .high {
                        Text("Важно")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 14)
        .opacity(task.isDone ? 0.75 : 1)
    }
}

// MARK: - Status Filter

enum EventStatusFilter: String, CaseIterable {
    case overdue, upcoming, completed

    var sectionTitle: String {
        switch self {
        case .overdue: return "Просроченные"
        case .upcoming: return "Предстоящие"
        case .completed: return "Выполненные"
        }
    }

    var emptyIcon: String {
        switch self {
        case .overdue: return "checkmark.seal"
        case .upcoming: return "calendar.badge.checkmark"
        case .completed: return "tray"
        }
    }

    var emptyMessage: String {
        switch self {
        case .overdue: return "Нет просроченных событий"
        case .upcoming: return "Нет предстоящих событий"
        case .completed: return "Нет выполненных событий"
        }
    }
}

// MARK: - Liquid Backdrop

private struct CalendarLiquidBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.18),
                                Color.accentColor.opacity(0),
                            ],
                            center: .center, startRadius: 0, endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .blur(radius: 48)
                    .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.02)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.45, green: 0.72, blue: 0.98)
                                    .opacity(colorScheme == .dark ? 0.14 : 0.11),
                                Color.clear,
                            ],
                            center: .center, startRadius: 0, endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .blur(radius: 42)
                    .offset(x: geo.size.width * 0.42, y: geo.size.height * 0.22)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.12),
                                Color.clear,
                            ],
                            center: .center, startRadius: 0, endRadius: 100
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 36)
                    .offset(x: geo.size.width * 0.08, y: geo.size.height * 0.52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    CalendarTabView()
        .environment(AppState())
}
