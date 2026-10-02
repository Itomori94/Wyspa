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
                if !module.history.entries.isEmpty {
                    Button("Wyczyść", action: module.clear)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55))
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
                            ClipboardRow(entry: entry, copy: { module.copy(entry) }, remove: { module.remove(entry) })
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let copy: () -> Void
    let remove: () -> Void
    @State private var isHovered = false
    @State private var copied = false

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
            if copied {
                Label("Skopiowano", systemImage: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
            } else if isHovered {
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
        .onTapGesture {
            copy()
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation { copied = false }
            }
        }
        .help("Kliknij, żeby skopiować ponownie")
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
        HStack {
            Stepper("Zapamiętuj \(module.limit) wpisów", value: $module.limit,
                    in: ClipboardHistory.limitRange, step: 10)
            Spacer()
            Button("Wyczyść historię", action: module.clear)
        }
    }
}
