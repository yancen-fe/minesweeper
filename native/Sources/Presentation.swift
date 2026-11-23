import Foundation
import Observation

struct GameCompletion {
    let record: GameRecord
    let best: Int?
    let statistics: HistoryStatistics
}

@MainActor @Observable final class GamePresentation {
    enum Dialog { case history, settings, result, share, importGame }
    var dialog: Dialog?
    private(set) var completion: GameCompletion?
    private var shownRecordID: UUID?
    func show(_ dialog: Dialog, game: GameModel) {
        game.pause(); completion = nil; self.dialog = dialog
    }
    func showCompletion(game: GameModel) {
        guard game.field.ended, let record = game.sessionRecord,
              record.result == (game.field.phase == .won ? .won : .lost), record.id != shownRecordID else { return }
        shownRecordID = record.id
        completion = GameCompletion(record: record, best: game.savedBest(for: record.difficulty, mode: record.gameMode), statistics: HistoryStatistics(records: game.history.filter { $0.difficulty == record.difficulty && $0.gameMode == record.gameMode }))
        dialog = .result
    }
    func close() { dialog = nil; completion = nil }
}
