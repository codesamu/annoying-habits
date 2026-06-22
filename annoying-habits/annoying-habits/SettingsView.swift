import SwiftUI
import SwiftData

struct SettingsView: View {
    let viewModel: HabitsViewModel
    let modelContext: ModelContext

    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false
    @State private var resetErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
                        set: { appearanceModeRaw = $0.rawValue }
                    )) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Data") {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Text("Reset all data")
                    }

                    Text("Deletes every habit, completion, and scheduled reminder from this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let resetErrorMessage {
                    Section {
                        Text(resetErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Reset all data?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset all data", role: .destructive) {
                    Task {
                        do {
                            try viewModel.resetAllData(context: modelContext)
                            dismiss()
                        } catch {
                            resetErrorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("This removes every habit and completion on this device.")
            }
        }
    }
}
