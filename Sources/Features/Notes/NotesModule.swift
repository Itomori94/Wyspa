import AppKit
import SwiftUI
import WyspaCore
import WyspaUI

/// Szybka notatka z autozapisem.
@MainActor
@Observable
public final class NotesModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "notes",
        name: "Notatka",
        summary: "Szybka notatka z autozapisem. Kliknij w tekst, żeby pisać; Esc zwija wyspę.",
        symbol: "note.text"
    )

    static let autosaveDelay: Duration = .milliseconds(600)

    public var text: String = "" {
        didSet {
            guard text != oldValue, isLoaded else { return }
            scheduleSave()
        }
    }
    public private(set) var saveState: SaveState = .saved
    public private(set) var problem: String?

    public enum SaveState: Equatable { case saved, pending }

    @ObservationIgnored private let store = NoteStore()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private let log = Log.logger("notes")

    public required init(context: ModuleContext) {}

    public func activate() async throws {
        text = try store.load()
        isLoaded = true
    }

    /// Wyłączenie zapisuje od razu, bez czekania na opóźnienie autozapisu.
    public func deactivate() {
        saveTask?.cancel()
        if saveState == .pending { saveNow() }
        isLoaded = false
    }

    public var liveActivity: LiveActivity? { nil }

    public func makeExpandedView() -> AnyView? {
        AnyView(NotesView(module: self))
    }

    func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    private func scheduleSave() {
        saveState = .pending
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try store.save(text)
            saveState = .saved
            problem = nil
        } catch {
            log.error("Zapis notatki nie powiódł się: \(error.localizedDescription)")
            problem = "Nie udało się zapisać notatki: \(error.localizedDescription)"
        }
    }
}

struct NotesView: View {
    @Bindable var module: NotesModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if module.text.isEmpty {
                    Text("Zapisz myśl, numer, link…")
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $module.text)
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 8)
            }
            .font(.system(size: 13))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
            HStack(spacing: 8) {
                if let problem = module.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(1)
                } else {
                    Label(module.saveState == .saved ? "Zapisano" : "Zapisywanie…",
                          systemImage: module.saveState == .saved ? "checkmark" : "ellipsis")
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Text("\(module.text.count) znaków").foregroundStyle(.white.opacity(0.35)).monospacedDigit()
                Button("Pokaż plik", action: module.revealFile)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 10.5, weight: .medium))
        }
    }
}
