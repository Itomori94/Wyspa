import Foundation
import WyspaCore

/// Karta ze skryptu (`wyspa notify`).
public struct ScriptNotice: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String?

    public init(id: UUID = UUID(), title: String, body: String?) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// Postęp ze skryptu (`wyspa progress`).
public struct ScriptProgress: Equatable, Identifiable, Sendable {
    public let id: String
    /// nil = postęp nieokreślony.
    public let fraction: Double?
    public let label: String?
    public let isFinished: Bool
    public let updatedAt: Date

    public init(id: String, fraction: Double?, label: String?, isFinished: Bool = false, updatedAt: Date) {
        self.id = id
        self.fraction = fraction
        self.label = label
        self.isFinished = isFinished
        self.updatedAt = updatedAt
    }
}

/// Stan modułu: kolejka kart i lista postępów. Niemutowalny, każde polecenie daje nowy stan.
public struct ScriptsState: Equatable, Sendable {
    public static let maxWaiting = 5
    public static let maxProgress = 6
    /// Postęp, którego nikt nie aktualizuje (skrypt padł bez `wyspa done`), znika po tym czasie.
    public static let staleAfter: TimeInterval = 15 * 60

    public let notice: ScriptNotice?
    public let waiting: [ScriptNotice]
    public let progress: [ScriptProgress]

    public init(notice: ScriptNotice? = nil, waiting: [ScriptNotice] = [], progress: [ScriptProgress] = []) {
        self.notice = notice
        self.waiting = waiting
        self.progress = progress
    }

    public func applying(_ command: ScriptCommand, at date: Date, noticeID: UUID = UUID()) -> ScriptsState {
        switch command {
        case .notify(let title, let body):
            let card = ScriptNotice(id: noticeID, title: title, body: body)
            guard notice != nil else { return ScriptsState(notice: card, waiting: waiting, progress: progress) }
            return ScriptsState(notice: notice, waiting: Array((waiting + [card]).suffix(Self.maxWaiting)), progress: progress)
        case .progress(let id, let fraction, let label):
            let previous = progress.first { $0.id == id }
            // Opis zostaje z poprzedniej aktualizacji, gdy skrypt podaje już tylko wartość.
            let item = ScriptProgress(id: id, fraction: fraction, label: label ?? previous?.label,
                                      isFinished: (fraction ?? 0) >= 1, updatedAt: date)
            return replacing(item)
        case .done(let id):
            guard let previous = progress.first(where: { $0.id == id }) else { return self }
            return replacing(ScriptProgress(id: id, fraction: 1, label: previous.label, isFinished: true, updatedAt: date))
        }
    }

    /// Nowy postęp dochodzi na koniec (najstarsze odpadają ponad limit), istniejący zostaje na swoim miejscu.
    private func replacing(_ item: ScriptProgress) -> ScriptsState {
        let updated = progress.contains { $0.id == item.id }
            ? progress.map { $0.id == item.id ? item : $0 }
            : Array((progress + [item]).suffix(Self.maxProgress))
        return ScriptsState(notice: notice, waiting: waiting, progress: updated)
    }

    public func advancingNotice() -> ScriptsState {
        ScriptsState(notice: waiting.first, waiting: Array(waiting.dropFirst()), progress: progress)
    }

    public func removingProgress(_ id: String) -> ScriptsState {
        ScriptsState(notice: notice, waiting: waiting, progress: progress.filter { $0.id != id })
    }

    /// Bez postępów nieaktualizowanych dłużej niż `staleAfter`.
    public func expiring(at date: Date) -> ScriptsState {
        ScriptsState(notice: notice, waiting: waiting,
                     progress: progress.filter { date.timeIntervalSince($0.updatedAt) < Self.staleAfter })
    }

    /// Najbliższa chwila, w której któryś postęp się przedawni (do jednego zaplanowanego wybudzenia).
    public var nextExpiry: Date? {
        progress.filter { !$0.isFinished }.map { $0.updatedAt.addingTimeInterval(Self.staleAfter) }.min()
    }

    /// Łączny postęp do skrzydła: średnia określonych wartości; nil, gdy żaden nie jest określony.
    public var overallFraction: Double? {
        ProgressSummary.average(progress.map(\.fraction))
    }
}
