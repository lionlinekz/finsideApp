import SwiftUI

struct AddNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDeadline: Bool
    @State private var due: Date
    @State private var priority: TaskPriority = .normal

    let onSave: (String, Date?, TaskPriority) -> Void

    init(initialDueDate: Date? = nil, onSave: @escaping (String, Date?, TaskPriority) -> Void) {
        self.onSave = onSave
        if let initialDueDate {
            _hasDeadline = State(initialValue: true)
            _due = State(initialValue: Calendar.current.startOfDay(for: initialDueDate))
        } else {
            _hasDeadline = State(initialValue: true)
            _due = State(initialValue: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date())
        }
    }

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
                            .environment(\.locale, Locale(identifier: "ru_RU"))
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
            .navigationTitle("Новая заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let deadline = hasDeadline ? Calendar.current.startOfDay(for: due) : nil
                        onSave(trimmed, deadline, priority)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
