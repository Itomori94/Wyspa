import SwiftUI
import WyspaCore

struct ModulesSettingsView: View {
    let registry: ModuleRegistry
    let permissions: PermissionCenter

    var body: some View {
        let entries = registry.entries
        if entries.isEmpty {
            ContentUnavailableView(
                "Brak modułów",
                systemImage: "square.grid.2x2",
                description: Text("Ta wersja Wyspy nie zawiera żadnych modułów.")
            )
        } else {
            Form {
                Section {
                    ForEach(entries) { entry in
                        ModuleRow(entry: entry, registry: registry, permissions: permissions)
                    }
                } footer: {
                    Text("Wyłączony moduł nie działa w tle i nie prosi o uprawnienia.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ModuleRow: View {
    let entry: ModuleEntry
    let registry: ModuleRegistry
    let permissions: PermissionCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.descriptor.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.descriptor.name).font(.headline)
                    Text(entry.descriptor.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !entry.descriptor.permissions.isEmpty {
                        Text("Wymaga: " + entry.descriptor.permissions.map(\.displayName).sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if registry.isPending(entry.id) {
                    ProgressView().controlSize(.small)
                }
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { enabled in Task { await registry.setEnabled(entry.id, enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if let problem = entry.problem {
                HStack {
                    ProblemText(problem)
                    Spacer()
                    ForEach(Array(entry.descriptor.permissions).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { permission in
                        if permissions.status(of: permission) != .granted {
                            Button("Otwórz: \(permission.displayName)") {
                                permissions.openSystemSettings(for: permission)
                            }
                        }
                    }
                }
            }
            if entry.isActive, entry.id == "quickactions" {
                Text("Kafelki i skróty ustawisz w karcie „Szybkie akcje”.")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 40)
            } else if entry.isActive, let detail = registry.settingsView(for: entry.id) {
                detail.padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
    }
}
