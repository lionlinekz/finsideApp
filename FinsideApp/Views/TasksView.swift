import SwiftUI

struct TasksView: View {
    @Environment(AppState.self) private var appState
    @State private var showCompleted = false
    @State private var showAdd = false

    private var active: [TaskItem] { appState.taskItems.filter { !$0.isDone }.sorted(by: taskSort) }
    private var done: [TaskItem] { appState.taskItems.filter(\.isDone).sorted(by: taskSort) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(active) { row in
                        taskRow(row)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.removeTask(id: row.id)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }

                if !done.isEmpty {
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCompleted.toggle()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(showCompleted ? "Скрыть" : "Выполненные · \(done.count)")
                                    .font(.footnote)
                                    .foregroundStyle(.quaternary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                        if showCompleted {
                            ForEach(done) { row in
                                taskRow(row)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            appState.removeTask(id: row.id)
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                Section {
                    NavigationLink {
                        TasksHistoryView()
                    } label: {
                        Text("История")
                            .font(.footnote)
                            .fontWeight(.regular)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .accessibilityHint("Завершённые задачи из прошлого")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 10, trailing: 0))
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Задачи")
            .toolbar {
                #if os(iOS) || os(visionOS)
                ToolbarItem(placement: .topBarTrailing) {
                    AvatarMenuButton()
                }
                #else
                ToolbarItem(placement: .automatic) {
                    AvatarMenuButton()
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Новая задача")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTaskSheet(onSave: { title, deadline, priority in
                    appState.addUserTask(title: title, deadline: deadline, priority: priority)
                })
            }
        }
    }

    private func taskSort(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority != b.priority { return a.priority == .high }
        return a.calendarPlacementDate < b.calendarPlacementDate
    }

    @ViewBuilder
    private func taskRow(_ t: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TaskCheckControl(isDone: t.isDone) {
                let becomesDone = !t.isDone
                TaskFeedback.toggle(toDone: becomesDone)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    appState.toggleTaskDone(id: t.id)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(t.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(t.isDone)
                    .foregroundStyle(t.isDone ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: t.isDone)

                HStack(spacing: 10) {
                    Text(TaskItem.dueLabel(deadline: t.deadline, createdAt: t.createdAt))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)

                    if t.priority == .high {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 5, height: 5)
                        Text("Приоритет")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TaskCheckControl: View {
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isDone ? Color.accentColor : Color.secondary.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: isDone)
    }
}

private struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDeadline = true
    @State private var due = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var priority: TaskPriority = .normal

    let onSave: (String, Date?, TaskPriority) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $title)
                }
                Section {
                    Toggle("Указать срок", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Срок", selection: $due, displayedComponents: .date)
                    }
                }
                Section {
                    Picker("", selection: $priority) {
                        Text(TaskPriority.normal.rawValue).tag(TaskPriority.normal)
                        Text(TaskPriority.high.rawValue).tag(TaskPriority.high)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Приоритет")
                        .textCase(nil)
                }
            }
            .navigationTitle("Новая задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, hasDeadline ? due : nil, priority)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct TasksHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var source: [TaskItem] {
        appState.taskItems.filter(\.isDone).sorted { $0.calendarPlacementDate > $1.calendarPlacementDate }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [TaskItem] {
        guard !trimmedQuery.isEmpty else { return source }
        return source.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var monthSections: [(title: String, tasks: [TaskItem])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_KZ")
        fmt.dateFormat = "LLLL yyyy"

        let grouped = Dictionary(grouping: filtered) { task -> Date in
            let c = cal.dateComponents([.year, .month], from: task.calendarPlacementDate)
            return cal.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? task.calendarPlacementDate
        }
        let orderedKeys = grouped.keys.sorted(by: >)
        return orderedKeys.map { key in
            let tasks = (grouped[key] ?? []).sorted { $0.calendarPlacementDate > $1.calendarPlacementDate }
            return (fmt.string(from: key), tasks)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Нет записей",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("В архиве пока ничего нет.")
                    )
                } else {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            } else {
                List {
                    ForEach(monthSections, id: \.title) { section in
                        Section {
                            ForEach(section.tasks) { t in
                                historyRow(t)
                            }
                        } header: {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск")
    }

    private func historyRow(_ t: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.title)
                .font(.body)
                .foregroundStyle(.primary)
            Text("\(TaskItem.dueLabel(deadline: t.deadline, createdAt: t.createdAt)) · \(t.origin.rawValue)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TasksView()
        .environment(AppState())
}
