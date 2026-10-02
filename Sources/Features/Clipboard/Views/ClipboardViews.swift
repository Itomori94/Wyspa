import AppKit
import SwiftUI
import WyspaUI

struct ClipboardView: View {
    @Bindable var module: ClipboardModule

    var body: some View {
        let entries = module.history.matching(module.query)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                TextField("Szukaj w historii", text: $module.query)
                    .textFieldStyle(.plain)
                if let feedback = module.feedback {
                    Text(feedback).foregroundStyle(.green).lineLimit(1).transition(.opacity)
                } else if module.history.entries.contains(where: { !$0.isPinned }) {
                    Button("Wyczyść", action: module.clear)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55))
                        .help("Usuwa wpisy poza przypiętymi")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.07)))

            if entries.isEmpty {
                Text(module.history.entries.isEmpty ? "Skopiuj coś, a pojawi się tutaj." : "Nic nie pasuje do wyszukiwania.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(entries) { entry in
                            ClipboardRow(entry: entry, pastes: module.pastesOnClick,
                                         choose: { module.choose(entry) },
                                         togglePin: { module.togglePin(entry) },
                                         remove: { module.remove(entry) })
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let pastes: Bool
    let choose: () -> Void
    let togglePin: () -> Void
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            preview
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.searchableText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(entry.copiedAt, format: .relative(presentation: .named))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 4)
            if isHovered || entry.isPinned {
                Button(action: togglePin) { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain)
                    .foregroundStyle(entry.isPinned ? Color.orange : .white.opacity(0.5))
                    .help(entry.isPinned ? "Odepnij" : "Przypnij — wpis nie wypadnie z historii")
            }
            if isHovered {
                Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Usuń z historii")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isHovered ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: choose)
        .help(pastes ? "Kliknij, żeby wkleić do aktywnej aplikacji" : "Kliknij, żeby skopiować ponownie")
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.content {
        case .text:
            Image(systemName: "text.alignleft").frame(width: 24).foregroundStyle(.white.opacity(0.5))
        case .files(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls.first?.path ?? "")).resizable().frame(width: 24, height: 24)
        case .image(let png, _, _):
            if let image = NSImage(data: png) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

struct ClipboardSettingsView: View {
    @Bindable var module: ClipboardModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Stepper("Zapamiętuj \(module.limit) wpisów", value: $module.limit,
                        in: ClipboardHistory.limitRange, step: 10)
                Spacer()
                Button("Wyczyść historię", action: module.clear)
            }
            Toggle("Kliknięcie wkleja do aktywnej aplikacji", isOn: $module.pastesOnClick)
            if module.pastesOnClick, !AXIsProcessTrusted() {
                HStack {
                    Text("Wklejanie wymaga uprawnienia Dostępność — bez niego kliknięcie tylko kopiuje.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Otwórz: Dostępność") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
            Text("Przypięte wpisy (pinezka przy wpisie) nie wypadają z historii i zostają po „Wyczyść”. "
                 + "Cała historia, także przypięta, jest tylko w pamięci i znika po zamknięciu Wyspy.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
