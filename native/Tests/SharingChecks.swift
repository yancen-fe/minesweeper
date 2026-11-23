import Foundation

struct SharingFixture: Decodable {
    let level: Difficulty
    let mode: GameMode
    let first: Int
    let seconds: Int
    let mines: [Int]
    let opened: [Int]
    let flags: [Int]
    let questions: [Int]
    let id: String
    let challenge: String
    let progress: String
}
struct InvalidSharingFixture: Decodable { let reason: String; let code: String }
@main struct SharingChecks {
    @MainActor static func main() async throws {
        let fixtures = try JSONDecoder().decode([SharingFixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var checks = 0
        func check(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
        func rejects(_ code: String) { do { _ = try GameSharing.decode(code); preconditionFailure("Accepted invalid sharing code") } catch { checks += 1 } }
        for f in fixtures {
            let shared = try GameSharing.decode(f.progress)
            check(shared.id == f.id && shared.first == f.first && shared.mode == f.mode && shared.seconds == f.seconds, "Portable identity and elapsed time")
            check(shared.field.cells.indices.filter { shared.field.cells[$0].mine } == f.mines, "Identical mine locations")
            check(shared.field.cells.indices.filter { shared.field.cells[$0].open } == f.opened, "Identical revealed cells")
            check(shared.field.cells.indices.filter { shared.field.cells[$0].flagged } == f.flags, "Identical flags")
            check(shared.field.cells.indices.filter { shared.field.cells[$0].questioned } == f.questions, "Identical questions")
            check(try GameSharing.encode(field: shared.field, mode: shared.mode, first: shared.first, seconds: shared.seconds, progress: true) == f.progress, "Swift emits the exact JS progress code")
            check(try GameSharing.encode(field: shared.field, mode: shared.mode, first: shared.first, seconds: shared.seconds, progress: false) == f.challenge, "Swift emits the exact JS challenge code")
            let challenge = try GameSharing.decode(f.challenge), fresh = challenge.restored(continueProgress: false)
            check(challenge.id == shared.id && fresh.cells[f.first].open && fresh.flags == 0, "Fresh challenge repeats the first click")
            check(try GameSharing.decode(" \n" + f.progress + "\n ").id == f.id, "Pasted whitespace accepted")
            let suite = "Minesweeper.SharingChecks.\(UUID())", storage = UserDefaults(suiteName: suite)!
            defer { storage.removePersistentDomain(forName: suite) }
            var now: TimeInterval = 50
            let game = GameModel(storage: storage, clock: { now })
            try game.importGame(shared, continueProgress: true)
            check(game.firstMove == f.first && game.seconds == f.seconds && game.isPaused && game.shareID == f.id, "Imported progress initially paused with correct ID")
            check(game.field.cells == shared.field.cells && game.history.isEmpty, "Exact progress and independent local session")
            game.resume(); now += 3; game.pause()
            check(game.seconds == f.seconds + 3, "Imported elapsed time continues")
            let progressCode = try game.shareCode(progress: true)
            check(try GameSharing.decode(progressCode).seconds == f.seconds + 3, "Continued progress can be shared again")
            try game.importGame(shared, continueProgress: false)
            check(game.seconds == 0 && game.field.flags == 0 && game.shareID == f.id, "Restart same layout with zero timer")
            check(game.history.count == 1 && game.history[0].result == .abandoned, "Replacing a local game records it once")
            check(game.mode == f.mode && game.difficulty == f.level, "Import restores difficulty and mode")
            let before = game.field.cells
            do { try game.importGame(challenge, continueProgress: true); preconditionFailure("Accepted missing progress") } catch { checks += 1 }
            check(game.field.cells == before, "Failed import never replaces the current game")
            for code in ["", "MS2." + f.progress.split(separator: ".").dropFirst().joined(separator: "."), String(f.progress.dropLast()), f.progress + ".extra", String(repeating: "x", count: 3000)] { rejects(code) }
        }
        let invalidURL = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("share-v1-invalid.json")
        for sample in try JSONDecoder().decode([InvalidSharingFixture].self, from: Data(contentsOf: invalidURL)) { rejects(sample.code) }
        // Importing while generation is in flight cancels its result without replacing the imported board.
        let suite = "Minesweeper.ImportCancellation.\(UUID())", storage = UserDefaults(suiteName: suite)!, game = GameModel(storage: storage)
        defer { storage.removePersistentDomain(forName: suite) }
        game.chooseMode(.logical); game.restart(.hard); game.click(0)
        let imported = try GameSharing.decode(fixtures[0].progress)
        try game.importGame(imported, continueProgress: true)
        try? await Task.sleep(for: .milliseconds(200))
        check(game.field.cells == imported.field.cells && !game.isGenerating && game.shareID == imported.id, "Old worker cannot overwrite imported progress")
        print("PASS: \(checks) cross-platform sharing, validation, timer, session and cancellation checks")
    }
}
