import Foundation

enum GameMode: String, Codable, CaseIterable, Sendable {
    case classic, logical
    var title: String { self == .logical ? "无猜" : "经典随机" }
    var bestPrefix: String { self == .logical ? "best-logic" : "best-classic" }
}
enum GameDuration {
    static func text(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) 秒" }
        return "\(s / 60) 分 \(String(format: "%02d", s % 60)) 秒"
    }

}

enum GameResult: String, Codable, Sendable {
    case won, lost, abandoned
    var title: String { switch self { case .won: "获胜"; case .lost: "踩雷"; case .abandoned: "未完成" } }
}
struct GameRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let difficulty: Difficulty
    let startedAt: Date
    let endedAt: Date
    let seconds: Int
    let result: GameResult
    var mode: GameMode? = nil
    var gameMode: GameMode { mode ?? .logical }
}
struct HistoryArchive: Codable {
    var version = 1
    var records: [GameRecord]
}
struct HistoryStatistics {
    let count: Int
    let wins: Int
    let losses: Int
    let best: Int?
    var completed: Int { wins + losses }
    var winRate: Double { completed == 0 ? 0 : Double(wins) / Double(completed) }
    init(records: [GameRecord]) {
        count = records.count
        wins = records.filter { $0.result == .won }.count
        losses = records.filter { $0.result == .lost }.count
        best = records.filter { $0.result == .won }.map(\.seconds).min()
    }
}

enum HistoryRange: String, CaseIterable {
    case all, today, week, month
    var title: String { switch self { case .all: "全部时间"; case .today: "今天"; case .week: "近 7 天"; case .month: "近 30 天" } }
}
enum HistoryOrder: String, CaseIterable {
    case newest, oldest, fastest, slowest
    var title: String { switch self { case .newest: "最新在前"; case .oldest: "最早在前"; case .fastest: "用时最短"; case .slowest: "用时最长" } }
}
struct HistoryFilter {
    var difficulty: Difficulty?
    var mode: GameMode?
    var result: GameResult?
    var range: HistoryRange = .all
    var order: HistoryOrder = .newest
    var isDefault: Bool { difficulty == nil && mode == nil && result == nil && range == .all && order == .newest }
    func apply(_ history: [GameRecord], now: Date = Date(), calendar: Calendar = .current) -> [GameRecord] {
        let today = calendar.startOfDay(for: now)
        let days = range == .week ? 6 : range == .month ? 29 : 0
        let lower = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        let upper = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return history.filter {
            (difficulty == nil || $0.difficulty == difficulty) && (mode == nil || $0.gameMode == mode) &&
            (result == nil || $0.result == result) && (range == .all || ($0.endedAt >= lower && $0.endedAt < upper))
        }.sorted { a, b in
            if order == .fastest && a.seconds != b.seconds { return a.seconds < b.seconds }
            if order == .slowest && a.seconds != b.seconds { return a.seconds > b.seconds }
            if a.endedAt != b.endedAt { return order == .oldest ? a.endedAt < b.endedAt : a.endedAt > b.endedAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
