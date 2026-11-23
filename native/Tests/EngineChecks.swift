import Foundation
import CoreGraphics
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
@main struct EngineChecks {
    @MainActor static func main() async {
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            if !value() { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); fatalError(message) }
        }
        let currentVersion = ReleaseTag.Version("1.9.0")!
        check(ReleaseTag.Version("1.10.0")! > currentVersion, "Release versions sort numerically")
        check(ReleaseTag.Version("1.8.0")! < currentVersion, "Older releases do not qualify")
        check(ReleaseTag.Version("1.9.0") == currentVersion, "Equal releases do not qualify")
        check(ReleaseTag(tag: "minesweeper-v1.10.0").version == "1.10.0", "Formal release tag is recognized")
        for tag in ["v1.9.4", "minesweeper-v1.01.0", "minesweeper-v1.1.0-beta", "minesweeper-v1.1.0+build", "minesweeper-v1.1"] {
            check(ReleaseTag(tag: tag).version == nil, "Reject non-release tag \(tag)")
        }
        for level in Difficulty.allCases {
            for first in [0, level.rows * level.columns / 2, level.rows * level.columns - 1] {
                var field = Minefield(level), random = SeededRandom(state: UInt64(first + 7))
                field.reveal(first, using: &random)
                check(field.cells.filter(\.mine).count == level.mines, "Mine count")
                for i in [first] + field.neighbors(first) { check(!field.cells[i].mine, "First click protection") }
                for i in field.cells.indices {
                    check(field.cells[i].number == field.neighbors(i).filter { field.cells[$0].mine }.count, "Adjacent numbers")
                }
                for i in field.cells.indices where !field.cells[i].mine && !field.cells[i].open { field.reveal(i) }
                check(field.phase == .won, "Win condition")
                check(field.flags == level.mines, "Auto flags on win")
                let snapshot = field.cells
                field.flag(0); field.reveal(0)
                check(field.cells == snapshot, "Lock after win")
            }
        }
        var wrongFlagBoard = Minefield()
        wrongFlagBoard.phase = .playing
        wrongFlagBoard.cells[42].mine = true
        for i in wrongFlagBoard.cells.indices { wrongFlagBoard.cells[i].number = wrongFlagBoard.neighbors(i).filter { wrongFlagBoard.cells[$0].mine }.count }
        wrongFlagBoard.flag(51); wrongFlagBoard.reveal(43); wrongFlagBoard.reveal(42)
        check(wrongFlagBoard.phase == .lost && wrongFlagBoard.cells[43].number == 1, "A one next to a wrong flag counts only the real mine")
        check(!wrongFlagBoard.cells[51].mine && wrongFlagBoard.cells[51].flagged, "The crossed wrong flag is a safe cell")
        var marks = Minefield()
        marks.flag(0)
        check(marks.cells[0].flagged && !marks.cells[0].questioned && marks.flags == 1, "Unmarked to flag")
        marks.flag(0)
        check(marks.cells[0].questioned && !marks.cells[0].flagged && marks.flags == 0, "Flag to question frees mine count")
        marks.flag(0)
        check(marks.cells[0].mark == .none && marks.flags == 0, "Question to unmarked")
        marks.flag(40); marks.flag(40)
        marks.reveal(40)
        check(marks.cells[40].open && marks.cells[40].mark == .none, "Left click opens and clears a question")
        var questionChord = Minefield()
        questionChord.phase = .playing
        for i in 0..<10 { questionChord.cells[i].mine = true }
        for i in questionChord.cells.indices { questionChord.cells[i].number = questionChord.neighbors(i).filter { questionChord.cells[$0].mine }.count }
        questionChord.reveal(10)
        for i in questionChord.neighbors(10) where questionChord.cells[i].mine { questionChord.flag(i); questionChord.flag(i) }
        let unchanged = questionChord.opened
        questionChord.reveal(10)
        check(questionChord.opened == unchanged && questionChord.phase == .playing, "Question marks do not satisfy chord flag count")
        var floodQuestions = Minefield()
        floodQuestions.phase = .playing
        for i in 0..<10 { floodQuestions.cells[i].mine = true }
        for i in floodQuestions.cells.indices { floodQuestions.cells[i].number = floodQuestions.neighbors(i).filter { floodQuestions.cells[$0].mine }.count }
        floodQuestions.flag(79); floodQuestions.flag(79)
        floodQuestions.reveal(80)
        check(floodQuestions.cells[79].open && !floodQuestions.cells[79].questioned, "Flood reveal clears question marks")
        var field = Minefield()
        for i in 0...10 { field.flag(i) }
        check(field.flags == 10 && !field.cells[10].flagged, "Flag cap")
        field.reveal(0); check(field.phase == .ready, "Flags prevent revealing")
        field.flag(0); field.reveal(0)
        for i in field.cells.indices where field.cells[i].flagged { field.flag(i) }
        let mine = field.cells.firstIndex(where: \.mine)!
        field.reveal(mine)
        check(field.phase == .lost && field.exploded == mine, "Lose condition")
        let snapshot = field.cells
        field.flag(0); field.reveal(1)
        check(field.cells == snapshot, "Lock after loss")
        func chordFixture() -> Minefield {
            var field = Minefield(); field.phase = .playing
            for i in 0..<10 { field.cells[i].mine = true }
            for i in field.cells.indices { field.cells[i].number = field.neighbors(i).filter { field.cells[$0].mine }.count }
            field.reveal(10)
            return field
        }
        var correct = chordFixture()
        for i in correct.neighbors(10) where correct.cells[i].mine { correct.flag(i) }
        let opened = correct.opened; correct.reveal(10)
        check(correct.opened > opened && correct.phase != .lost, "Correct chord")
        var wrong = chordFixture()
        let nearby = wrong.neighbors(10)
        let mineNeighbors = nearby.filter { wrong.cells[$0].mine }
        for i in mineNeighbors.dropFirst() { wrong.flag(i) }
        wrong.flag(nearby.first { !wrong.cells[$0].mine && !wrong.cells[$0].open }!)
        wrong.reveal(10)
        check(wrong.phase == .lost, "Wrong chord loses")
        // Independently enumerate all 3 × 3 layouts: every deduction must be true in the actual layout.
        var adjacent = Array(repeating: [Int](), count: 9)
        for i in 0..<9 {
            for j in 0..<9 {
                let dr = abs(i / 3 - j / 3), dc = abs(i % 3 - j % 3)
                if i != j && dr <= 1 && dc <= 1 { adjacent[i].append(j) }
            }
        }
        for layout in 1..<511 {
            let actual = Set((0..<9).filter { layout & (1 << $0) != 0 })
            var visible = Array(repeating: Cell(), count: 9)
            for i in [0, 2, 4, 6, 8] where !actual.contains(i) {
                visible[i].open = true; visible[i].number = adjacent[i].filter { actual.contains($0) }.count
            }
            var known = Set<Int>()
            while true {
                let moves = LogicalSolver.deductions(cells: visible, neighbors: adjacent, totalMines: actual.count, knownMines: known)
                check(moves.safe.isDisjoint(with: actual), "Solver never declares a mine safe")
                check(moves.mines.isSubset(of: actual), "Solver never invents a mine")
                let additions = moves.mines.subtracting(known)
                if additions.isEmpty { break }; known.formUnion(additions)
            }
        }
        let ambiguous = LogicalSolver.deductions(cells: [Cell(), Cell()], neighbors: [[], []], totalMines: 1, knownMines: [])
        check(ambiguous.safe.isEmpty && ambiguous.mines.isEmpty, "50/50 ambiguity is never guessed")
        // The entire board must fit every viewport without scrolling; actual windows enforce readable minimums.
        for level in Difficulty.allCases {
            for viewport in [CGSize(width: 360, height: 250), CGSize(width: 420, height: 450), CGSize(width: 900, height: 480)] {
                let layout = BoardLayout(difficulty: level, viewport: viewport)
                check(layout.tile >= 1, "Positive tile size")
                check(layout.size.width.isFinite && layout.size.height.isFinite, "Finite board layout")
                check(abs(layout.size.width - (viewport.width - 4)) < 0.01, "Board fills the available width up to its bevel")
                check(abs(layout.size.height - (viewport.height - 4)) < 0.01, "Board fills the available height up to its bevel")
            }
            let minimum = GameWindowLayout.minimumContentSize(for: level)
            let available = CGSize(width: minimum.width - 24, height: minimum.height - 142)
            let smallest = BoardLayout(difficulty: level, viewport: available)
            check(smallest.tile >= 20, "Minimum window preserves readable targets")
            check(smallest.size.width <= available.width - 4 && smallest.size.height <= available.height - 4, "Minimum window shows the complete board")
            for screen in [CGRect(x: 0, y: 0, width: 1024, height: 640), CGRect(x: -1440, y: 40, width: 1440, height: 860), CGRect(x: 0, y: 30, width: 1512, height: 920)] {
                let previous = CGRect(x: -1800, y: 2000, width: 2000, height: 1400)
                let frame = GameWindowLayout.frame(difficulty: level, current: previous, visible: screen)
                let another = GameWindowLayout.frame(difficulty: level, current: CGRect(x: 10, y: 10, width: 300, height: 338), visible: screen)
                check(frame.size == another.size, "Each mode has a fixed size regardless of the previous frame")
                check(screen.contains(frame), "Window fits on the visible screen")
                check(frame.width <= screen.width - 24 && frame.height <= screen.height - 24, "Window leaves screen margins")
            }
        }
        var rejectedSeed: UInt64?
        for seed in UInt64(1)...100 {
            var trial = SeededRandom(state: seed)
            var raw = Minefield(.easy); raw.plant(at: 0, using: &trial)
            if !LogicalSolver.isSolvable(raw, first: 0) { rejectedSeed = seed; break }
        }
        check(rejectedSeed != nil, "Find a raw board that needs guessing")
        var rejectedRandom = SeededRandom(state: rejectedSeed!)
        let replacement = NoGuessGenerator.generate(difficulty: .easy, first: 0, using: &rejectedRandom)!
        check(replacement.attempts > 1, "Generator actually rejects an unsolved candidate")
        check(LogicalSolver.isSolvable(replacement.field, first: 0), "Rejected candidate replaced with a proven board")
        var rng = SeededRandom(state: 8741)
        var samples = 0
        let generationStart = Date()
        for level in Difficulty.allCases {
            for first in [0, (level.rows/2)*level.columns+level.columns/2, level.rows*level.columns-1] {
                for repeatIndex in 0..<5 {
                    guard let generated = NoGuessGenerator.generate(difficulty: level, first: first, using: &rng) else { fatalError("Generation cancelled") }
                    check(LogicalSolver.isSolvable(generated.field, first: first), "Accepted boards have full proofs")
                    check(generated.field.cells.filter(\.mine).count == level.mines, "Exact mine count retained")
                    for i in [first] + generated.field.neighbors(first) { check(!generated.field.cells[i].mine, "Generated safe opening") }
                    if repeatIndex == 0 {
                        var replay = generated.field; replay.reveal(first)
                        while replay.phase == .playing {
                            guard let move = LogicalSolver.safeMove(in: replay) else { fatalError("Logical replay got stuck") }
                            check(!replay.cells[move].mine, "Hint must be safe")
                            // Wrong user flags must not influence the hint proof.
                            var incorrect = replay
                            if let safe = incorrect.cells.indices.first(where: { !incorrect.cells[$0].open && !incorrect.cells[$0].mine }) { incorrect.flag(safe) }
                            if let alternate = LogicalSolver.safeMove(in: incorrect) {
                                check(!incorrect.cells[alternate].mine, "Hints ignore unproven flags")
                            } else { check(false, "Flags cannot remove a logical hint") }
                            replay.reveal(move)
                        }
                        check(replay.phase == .won, "Complete game replay without guessing")
                    }
                    samples += 1
                }
            }
        }
        check(NoGuessGenerator.generate(difficulty: .hard, first: 0, using: &rng, cancelled: { true }) == nil, "Generation cancels without an unchecked fallback")
        let suite = "com.yancen.minesweeper.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(GameMode.logical.rawValue, forKey: "game-mode")
        var time: TimeInterval = 100
        let game = GameModel(storage: defaults, clock: { time })
        game.choose(.medium); game.click(136)
        let deadline = Date().addingTimeInterval(10)
        while game.isGenerating && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        check(!game.isGenerating && game.field.phase == .playing, "Async verified board arrives")
        check(LogicalSolver.isSolvable(game.field, first: 136), "App uses verified generator")
        let presentation = GamePresentation()
        presentation.showCompletion(game: game)
        check(presentation.dialog == nil, "An unfinished game does not open a result dialog")
        time = 111.25; game.pause()
        check(game.isPaused && game.seconds == 11, "Pause commits elapsed time")
        let pausedCells = game.field.cells
        game.click(0); game.flag(1); game.showHint()
        check(game.field.cells == pausedCells && game.hint == nil, "Pause blocks all game input")
        time = 211.25
        check(game.seconds == 11, "Paused time excluded")
        game.resume(); time = 214.25; game.pause()
        check(game.seconds == 14, "Resume retains fractional elapsed time")
        game.resume()
        for i in game.field.cells.indices where !game.field.cells[i].mine && !game.field.cells[i].open { game.click(i) }
        check(game.field.phase == .won && game.best != nil, "Record saved")
        check(GameModel(storage: defaults).best == game.best, "Record restored")
        check(game.history.count == 1 && game.history[0].result == .won && game.history[0].difficulty == .medium, "Win history saved once with correct difficulty")
        check(GameModel(storage: defaults).history == game.history, "History survives a new model instance")
        presentation.showCompletion(game: game)
        check(presentation.dialog == .result && presentation.completion?.record == game.history[0], "Win dialog uses the finalized result, difficulty and elapsed time")
        check(presentation.completion?.best == game.best && presentation.completion?.record.seconds == 14, "Result dialog retains final active time excluding pauses")
        check(presentation.completion?.statistics.count == 1 && presentation.completion?.statistics.wins == 1, "Win summary includes the just-completed game")
        let wonBoard = game.field.cells
        presentation.close()
        check(presentation.dialog == nil && game.field.cells == wonBoard, "Viewing the board preserves the completed game")
        presentation.showCompletion(game: game)
        check(presentation.dialog == nil, "A dismissed result does not reopen for the same game")
        game.finishSession()
        check(game.history.count == 1, "Finished session is not duplicated")
        game.restart(.hard); game.click(0)
        check(game.isGenerating, "Background generation starts")
        game.restart(.easy)
        try? await Task.sleep(for: .milliseconds(250))
        check(game.field.phase == .ready && game.difficulty == .easy && !game.isGenerating && game.seconds == 0 && !game.isPaused, "Cancelled old board cannot replace a new game")
        game.flag(80); game.flag(80)
        game.click(0); game.pause()
        while game.isGenerating { try? await Task.sleep(for: .milliseconds(10)) }
        check(game.isPaused, "Focus loss during generation keeps delivered board paused")
        check(game.seconds == 0, "Generation and paused generation do not count as play time")
        check(game.field.cells[80].open ? game.field.cells[80].mark == .none : game.field.cells[80].questioned, "Question marks survive generation unless revealed")
        game.restart()
        check(game.history.count == 2 && game.history[0].result == .abandoned, "Restart records an accepted unfinished game")
        let recorded = game.history
        game.restart(.hard); game.restart(.easy)
        check(game.history == recorded, "Unused boards are not history entries")
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let lostGame = GameModel(storage: defaults, date: { fixedDate })
        lostGame.click(40)
        while lostGame.isGenerating { try? await Task.sleep(for: .milliseconds(10)) }
        lostGame.click(lostGame.field.cells.firstIndex(where: \.mine)!)
        check(lostGame.history.count == 3 && lostGame.history[0].result == .lost, "Loss stored once")
        check(lostGame.history[0].startedAt == fixedDate && lostGame.history[0].endedAt == fixedDate, "Record timestamps use the wall clock")
        presentation.showCompletion(game: lostGame)
        check(presentation.dialog == .result && presentation.completion?.record.result == .lost, "The next completed game opens its own loss result")
        check(presentation.completion?.record.seconds == lostGame.seconds && presentation.completion?.record.difficulty == lostGame.difficulty, "Loss summary uses the finished game's details")
        check(presentation.completion?.statistics.count == 2 && presentation.completion?.statistics.wins == 0 && presentation.completion?.statistics.losses == 1, "Loss summary scopes statistics to its difficulty and excludes unfinished games from the win rate")
        presentation.close(); lostGame.restart()
        presentation.showCompletion(game: lostGame)
        check(presentation.dialog == nil, "Restart does not show a result from previous history")
        lostGame.finishSession()
        check(lostGame.history.count == 3, "Loss and later restart do not duplicate a record")
        let stats = HistoryStatistics(records: lostGame.history)
        check(stats.count == 3 && stats.wins == 1 && stats.losses == 1 && stats.winRate == 0.5, "Win rate excludes unfinished games")
        defaults.set(17, forKey: "best-logic-hard")
        let activeGame = GameModel(storage: defaults)
        activeGame.click(40)
        while activeGame.isGenerating { try? await Task.sleep(for: .milliseconds(10)) }
        activeGame.pause()
        let cellsBeforeReset = activeGame.field.cells
        activeGame.resetRecords()
        check(activeGame.history.isEmpty && activeGame.best == nil && activeGame.savedBest(for: .hard) == nil, "Reset clears history and every difficulty best")
        check(activeGame.field.cells == cellsBeforeReset && activeGame.isPaused, "Reset preserves the current game and pause state")
        check(GameModel(storage: defaults).history.isEmpty, "Reset persists across launches")
        activeGame.resume()
        for i in activeGame.field.cells.indices where !activeGame.field.cells[i].mine && !activeGame.field.cells[i].open { activeGame.click(i) }
        check(activeGame.history.count == 1 && activeGame.history[0].result == .won, "Active game can create a new record after reset")
        activeGame.restart()
        check(activeGame.history.count == 1, "New post-reset win remains unique")
        check(GameDuration.text(0) == "0 秒" && GameDuration.text(59) == "59 秒" && GameDuration.text(60) == "1 分 00 秒", "Dialogs omit zero minutes only for sub-minute times")
        check(GameDuration.text(100000) == "1666 分 40 秒", "History keeps full elapsed time beyond display limit")
        let legacy = GameRecord(id: UUID(), difficulty: .easy, startedAt: Date(), endedAt: Date(), seconds: 65, result: .won)
        let oldRecord = try! JSONDecoder().decode(GameRecord.self, from: JSONEncoder().encode(legacy))
        check(oldRecord.gameMode == .logical, "Old records without a mode remain logical")
        var needsGuess = false
        for seed in UInt64(1)...20 {
            var random = SeededRandom(state: seed)
            let result = NoGuessGenerator.generate(difficulty: .easy, first: 0, mode: .classic, using: &random)!
            check(result.attempts == 1 && result.field.cells.filter(\.mine).count == Difficulty.easy.mines, "Classic mode accepts the first random board")
            for index in [0] + result.field.neighbors(0) { check(!result.field.cells[index].mine, "Classic opening remains safe") }
            if !LogicalSolver.isSolvable(result.field, first: 0) { needsGuess = true }
        }
        check(needsGuess, "Classic mode can include boards that need guessing")
        let modeSuite = "Minesweeper-mode-check-\(UUID())"
        let modeStorage = UserDefaults(suiteName: modeSuite)!
        defer { modeStorage.removePersistentDomain(forName: modeSuite) }
        modeStorage.set(17, forKey: "best-logic-easy")
        let modeGame = GameModel(storage: modeStorage)
        check(modeGame.mode == .classic, "New users default to classic random gameplay")
        modeGame.chooseMode(.classic); modeGame.click(40)
        while modeGame.isGenerating { try? await Task.sleep(for: .milliseconds(10)) }
        for index in modeGame.field.cells.indices where !modeGame.field.cells[index].mine && !modeGame.field.cells[index].open { modeGame.click(index) }
        check(modeGame.history.first?.gameMode == .classic && modeGame.field.phase == .won, "Classic games record their own mode")
        check(modeGame.savedBest(for: .easy, mode: .logical) == 17, "Classic results do not overwrite logical best times")
        check(modeGame.savedBest(for: .easy, mode: .classic) != nil && GameModel(storage: modeStorage).mode == .classic, "Classic best and selected mode persist")
        modeGame.resetRecords()
        check(modeGame.savedBest(for: .easy, mode: .classic) == nil && modeGame.savedBest(for: .easy, mode: .logical) == nil, "Reset clears both modes")
        modeGame.restart(); modeGame.click(0); modeGame.chooseMode(.logical)
        try? await Task.sleep(for: .milliseconds(50))
        check(GameModel(storage: modeStorage).mode == .logical, "An explicit logical preference survives launch")
        check(modeGame.mode == .logical && modeGame.field.phase == .ready && !modeGame.isGenerating, "Switching mode cancels pending generation")
        var filterCalendar = Calendar(identifier: .gregorian)
        filterCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let filterNow = filterCalendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        func historyDate(_ day: Int) -> Date { filterCalendar.date(from: DateComponents(year: 2026, month: 3, day: day))! }
        let filterRows = [
            GameRecord(id: UUID(), difficulty: .easy, startedAt: historyDate(9), endedAt: historyDate(9), seconds: 65, result: .won, mode: .classic),
            GameRecord(id: UUID(), difficulty: .hard, startedAt: historyDate(3), endedAt: historyDate(3), seconds: 12, result: .lost, mode: .classic),
            GameRecord(id: UUID(), difficulty: .easy, startedAt: historyDate(2), endedAt: historyDate(2), seconds: 90, result: .won),
            GameRecord(id: UUID(), difficulty: .medium, startedAt: historyDate(1), endedAt: historyDate(1), seconds: 0, result: .abandoned, mode: .logical),
            GameRecord(id: UUID(), difficulty: .easy, startedAt: historyDate(10), endedAt: historyDate(10), seconds: 1, result: .won, mode: .classic)
        ]
        func filtered(_ filter: HistoryFilter) -> [GameRecord] { filter.apply(filterRows, now: filterNow, calendar: filterCalendar) }
        check(filtered(HistoryFilter(range: .today)) == [filterRows[0]], "Today uses local midnight and excludes tomorrow")
        check(filtered(HistoryFilter(range: .week)) == Array(filterRows.prefix(2)), "Seven calendar days cross DST without dropping boundary midnight")
        check(filtered(HistoryFilter(range: .month)).count == 4, "Thirty days exclude tomorrow")
        check(filtered(HistoryFilter(difficulty: .easy, mode: .classic, result: .won, range: .week)) == [filterRows[0]], "History filters combine")
        check(filtered(HistoryFilter(mode: .logical, result: .won)) == [filterRows[2]], "Legacy history is logical")
        check(filtered(HistoryFilter(order: .oldest)).map(\.seconds) == [0, 90, 12, 65, 1], "History oldest ordering")
        check(filtered(HistoryFilter(order: .fastest)).map(\.seconds) == [0, 1, 12, 65, 90], "History fastest ordering includes zero")
        check(filtered(HistoryFilter(order: .slowest)).map(\.seconds) == [90, 65, 12, 1, 0], "History slowest ordering")
        let filteredStats = HistoryStatistics(records: filtered(HistoryFilter(range: .week)))
        check(filteredStats.count == 2 && filteredStats.winRate == 0.5 && filteredStats.best == 65, "Statistics and best follow filtered records")
        check(filtered(HistoryFilter(difficulty: .hard, result: .won)).isEmpty, "Combined filters may yield empty records")
        check(HistoryFilter().isDefault && !HistoryFilter(range: .today).isDefault, "Reset returns to default filters")
        print("PASS: \(assertions) checks, \(samples) verified boards, complete no-guess replays, exhaustive small-board proof checks, pause/resume, cancellation and persistence")
        print("Generation/replay test elapsed: \(Date().timeIntervalSince(generationStart)) seconds")
    }
}
