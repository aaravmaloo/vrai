import Observation
import SwiftUI
import VraiCore

public enum ConsoleFilter: String, Sendable, Hashable, CaseIterable {
    case all
    case failed
    case background
}

@MainActor
@Observable
public final class ConsoleModel {
    public var open = false
    public var height: CGFloat = Vrai.Size.console
    public var filter: ConsoleFilter = .all
    public var query = ""
    public var prompt = ""
    public var notice: String?
    public var focusPrompt = false
    public var openGroups: Set<UUID> = []
    var historyIndex: Int?
    var historyDraft = ""
    @ObservationIgnored var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func toggle() {
        open.toggle()
    }

    public func show(focusingPrompt: Bool = false) {
        open = true
        if focusingPrompt { focusPrompt = true }
    }

    func recall(_ history: [String], older: Bool) -> Bool {
        guard !history.isEmpty else { return false }
        if older {
            if historyIndex == nil { historyDraft = prompt }
            let next = historyIndex.map { max(0, $0 - 1) } ?? history.count - 1
            historyIndex = next
            prompt = history[next]
            return true
        }
        guard let index = historyIndex else { return false }
        if index + 1 >= history.count {
            historyIndex = nil
            prompt = historyDraft
        } else {
            historyIndex = index + 1
            prompt = history[index + 1]
        }
        return true
    }

    func resetRecall() {
        historyIndex = nil
        historyDraft = ""
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
    }
}
