import Foundation
import Observation

/// One application library, shared by independent game sessions on the main actor.
@MainActor @Observable final class GameLibrary {
    static let shared = GameLibrary(storage: .standard)
    private(set) var history: [GameRecord] = []
    private var bests: [String: Int] = [:]
    private let storage: UserDefaults
    private static let historyKey = "history-v1"
    init(storage: UserDefaults) { self.storage = storage; reload() }
    func reload() {
        if let data = storage.data(forKey: Self.historyKey), let archive = try? JSONDecoder().decode(HistoryArchive.self, from: data) {
            history = archive.records.sorted { $0.endedAt > $1.endedAt }
        } else { history = [] }
        var values: [String: Int] = [:]
        for mode in GameMode.allCases { for level in Difficulty.allCases {
            let key = "\(mode.bestPrefix)-\(level.rawValue)"
            if storage.object(forKey: key) != nil { values[key] = storage.integer(forKey: key) }
        } }
        bests = values
    }
    func best(for level: Difficulty, mode: GameMode) -> Int? { bests["\(mode.bestPrefix)-\(level.rawValue)"] }
    func append(_ record: GameRecord) {
        // Merge against persisted data too, so independent callers cannot overwrite prior sessions.
        reload()
        guard !history.contains(where: { $0.id == record.id }) else { return }
        history.append(record); history.sort { $0.endedAt > $1.endedAt }
        if record.result == .won {
            let key = "\(record.gameMode.bestPrefix)-\(record.difficulty.rawValue)"
            if bests[key] == nil || record.seconds < bests[key]! { bests[key] = record.seconds; storage.set(record.seconds, forKey: key) }
        }
        if let data = try? JSONEncoder().encode(HistoryArchive(records: history)) { storage.set(data, forKey: Self.historyKey) }
    }
    func clear() {
        history = []; bests = [:]; storage.removeObject(forKey: Self.historyKey)
        for level in Difficulty.allCases {
            for mode in GameMode.allCases { storage.removeObject(forKey: "\(mode.bestPrefix)-\(level.rawValue)") }
            storage.removeObject(forKey: "best-\(level.rawValue)")
        }
    }
}
