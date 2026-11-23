import Foundation
@main struct MultiwindowChecks {
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let values = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: Any]]
        let easy = try GameSharing.decode(values[0]["progress"] as! String)
        let hard = try GameSharing.decode(values[5]["progress"] as! String)
        let suite = "Minesweeper.MultiwindowChecks.\(UUID())", storage = UserDefaults(suiteName: suite)!
        defer { storage.removePersistentDomain(forName: suite) }
        let library = GameLibrary(storage: storage)
        var now: TimeInterval = 0
        let a = GameModel(storage: storage, library: library, clock: { now })
        let b = GameModel(storage: storage, library: library, clock: { now })
        try a.importGame(easy, continueProgress: true); try b.importGame(hard, continueProgress: true)
        let originalA = a.field.cells, originalB = b.field.cells
        a.resume(); now = 3; b.resume(); b.flag(b.field.cells.firstIndex { !$0.open }!)
        a.pause(); b.pause()
        precondition(a.seconds == easy.seconds + 3 && b.seconds == hard.seconds)
        precondition(a.field.cells == originalA && b.field.cells != originalB)
        precondition(a.difficulty == .easy && b.difficulty == .hard)
        func finish(_ game: GameModel) {
            game.resume()
            for i in game.field.cells.indices where !game.field.cells[i].open {
                while game.field.cells[i].mark != .none && !game.field.ended { game.flag(i) }
            }
            for i in game.field.cells.indices where !game.field.cells[i].mine { game.click(i) }
            precondition(game.field.phase == .won)
        }
        finish(a); let aID = a.sessionRecord!.id
        finish(b); precondition(a.history.count == 2 && b.history.count == 2)
        precondition(a.sessionRecord?.id == aID && b.sessionRecord?.id != aID)
        let presentation = GamePresentation(); presentation.showCompletion(game: a)
        precondition(presentation.completion?.record.id == aID, "A result never shows B's latest record")
        precondition(a.best != nil && b.best != nil)
        b.resetRecords(); precondition(a.history.isEmpty && b.history.isEmpty && a.best == nil && b.best == nil)
        try a.importGame(easy, continueProgress: true); try b.importGame(hard, continueProgress: true)
        a.closeWindow(); a.closeWindow()
        precondition(b.field.cells == hard.field.cells && b.isPaused && a.history.count == 1)
        b.resume(); now += 2; b.pause(); precondition(b.seconds == hard.seconds + 2)
        b.closeWindow(); precondition(a.history.count == 2)
        // Separate clients sharing persistence also merge instead of replacing one another.
        let other = GameLibrary(storage: storage)
        let record = GameRecord(id: UUID(), difficulty: .easy, startedAt: Date(), endedAt: Date(), seconds: 9, result: .won, mode: .classic)
        other.append(record); library.append(record); precondition(library.history.count == 3)
        print("PASS: independent boards, timers, close lifecycle, shared records, bests and completion ownership")
    }
}
