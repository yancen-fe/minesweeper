import Foundation
import Observation

enum Difficulty: String, CaseIterable, Identifiable, Codable, Sendable {
    case easy, medium, hard
    var id: String { rawValue }
    var title: String { switch self { case .easy: "入门"; case .medium: "进阶"; case .hard: "挑战" } }
    var rows: Int { self == .easy ? 9 : 16 }
    var columns: Int { switch self { case .easy: 9; case .medium: 16; case .hard: 30 } }
    var mines: Int { switch self { case .easy: 10; case .medium: 40; case .hard: 99 } }
    var tileSize: Double { switch self { case .easy: 36; case .medium: 30; case .hard: 28 } }
}
enum GamePhase: Equatable, Sendable { case ready, playing, won, lost }
enum CellMark: Sendable { case none, flag, question }
struct Cell: Equatable, Sendable {
    var mine = false
    var number = 0
    var open = false
    var mark: CellMark = .none
    var flagged: Bool {
        get { mark == .flag }
        set { mark = newValue ? .flag : .none }
    }
    var questioned: Bool { mark == .question }
}
struct Minefield: Sendable {
    let difficulty: Difficulty
    var cells: [Cell]
    let adjacency: [[Int]]
    var phase: GamePhase = .ready
    var flags = 0
    var opened = 0
    var exploded: Int?
    init(_ difficulty: Difficulty = .easy) {
        self.difficulty = difficulty
        cells = Array(repeating: Cell(), count: difficulty.rows * difficulty.columns)
        adjacency = (0..<(difficulty.rows * difficulty.columns)).map { index in
            let row = index / difficulty.columns, col = index % difficulty.columns
            return (-1...1).flatMap { dr in (-1...1).compactMap { dc -> Int? in
                let r = row + dr, c = col + dc
                guard dr != 0 || dc != 0, r >= 0, r < difficulty.rows, c >= 0, c < difficulty.columns else { return nil }
                return r * difficulty.columns + c
            } }
        }
    }
    var ended: Bool { phase == .won || phase == .lost }
    func neighbors(_ index: Int) -> [Int] { adjacency[index] }
    mutating func plant<R: RandomNumberGenerator>(at first: Int, using random: inout R) {
        let safe = Set([first] + neighbors(first))
        let locations = cells.indices.filter { !safe.contains($0) }.shuffled(using: &random)
        for i in locations.prefix(difficulty.mines) { cells[i].mine = true }
        for i in cells.indices { cells[i].number = neighbors(i).filter { cells[$0].mine }.count }
        phase = .playing
    }
    mutating func flag(_ index: Int) {
        guard cells.indices.contains(index), !ended, !cells[index].open else { return }
        switch cells[index].mark {
        case .none:
            if flags < difficulty.mines { cells[index].mark = .flag; flags += 1 }
            else { cells[index].mark = .question }
        case .flag:
            cells[index].mark = .question; flags -= 1
        case .question:
            cells[index].mark = .none
        }
    }
    mutating func reveal(_ index: Int) {
        var random = SystemRandomNumberGenerator()
        reveal(index, using: &random)
    }
    mutating func reveal<R: RandomNumberGenerator>(_ index: Int, using random: inout R) {
        guard cells.indices.contains(index), !ended, !cells[index].flagged else { return }
        if phase == .ready { plant(at: index, using: &random) }
        if cells[index].open {
            let nearby = neighbors(index)
            guard cells[index].number > 0, nearby.filter({ cells[$0].flagged }).count == cells[index].number else { return }
            open(nearby.filter { !cells[$0].flagged && !cells[$0].open })
        } else { open([index]) }
    }
    private mutating func open(_ indices: [Int]) {
        var queue = indices
        while let i = queue.popLast(), phase == .playing {
            guard !cells[i].open, !cells[i].flagged else { continue }
            cells[i].mark = .none
            cells[i].open = true
            if cells[i].mine { exploded = i; phase = .lost; return }
            opened += 1
            if cells[i].number == 0 { queue.append(contentsOf: neighbors(i)) }
        }
        if opened == cells.count - difficulty.mines {
            phase = .won
            for i in cells.indices where cells[i].mine { cells[i].flagged = true }
            flags = difficulty.mines
        }
    }
}

@MainActor @Observable final class GameModel {
    private(set) var firstMove: Int?
    private(set) var mode: GameMode = .classic
    private(set) var field = Minefield()
    private(set) var seconds = 0
    var best: Int? { library.best(for: difficulty, mode: mode) }
    var history: [GameRecord] { library.history }
    var sessionRecord: GameRecord? { history.first { $0.id == sessionID } }
    private let library: GameLibrary
    private(set) var isPaused = false
    private(set) var isGenerating = false
    private(set) var hint: Int?
    var flagMode = false
    var showingHelp = false
    private var timer: Timer?
    private var startedAt: TimeInterval?
    private var accumulated: TimeInterval = 0
    private var generationID = UUID()
    private var worker: Task<Minefield?, Never>?
    private let storage: UserDefaults
    private let clock: () -> TimeInterval
    private let date: () -> Date
    private var sessionID: UUID?
    private var sessionStartedAt: Date?
    private var recordedSession = false
    init(storage: UserDefaults = .standard, library: GameLibrary? = nil, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, date: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.library = library ?? (storage === UserDefaults.standard ? .shared : GameLibrary(storage: storage))
        self.mode = GameMode(rawValue: storage.string(forKey: "game-mode") ?? "") ?? .classic
        self.clock = clock
        self.date = date
        let level = Difficulty(rawValue: storage.string(forKey: "difficulty") ?? "") ?? .easy
        field = Minefield(level)
        loadBest()
    }
    var difficulty: Difficulty { field.difficulty }
    var canPause: Bool { field.phase == .playing && !isGenerating }
    var status: String {
        if isGenerating { return mode == .classic ? "正在准备雷区" : "正在准备可推理的雷区" }
        if isPaused { return "已暂停" }
        if let hint { return field.cells[hint].flagged ? "这个标记可以取消，方格是安全的" : "描边的方格可以安全翻开" }
        switch field.phase {
        case .ready: return mode == .classic ? "首步安全 · 经典随机可能需要猜测" : "首步安全 · 每一局都可纯推理解开"
        case .playing: return "已翻开 \(field.opened) / \(field.cells.count - difficulty.mines)"
        case .won: return "完成，漂亮的推理"
        case .lost: return "踩到雷了，重新开始吧"
        }
    }
    func restart(_ level: Difficulty? = nil) {
        finishSession()
        sessionID = nil; sessionStartedAt = nil; recordedSession = false
        worker?.cancel(); worker = nil; generationID = UUID()
        stopClock(); accumulated = 0; seconds = 0; isPaused = false; isGenerating = false; hint = nil; flagMode = false
        firstMove = nil
        field = Minefield(level ?? difficulty)
        storage.set(difficulty.rawValue, forKey: "difficulty")
        loadBest()
    }
    var shareID: String? {
        guard let firstMove, field.phase != .ready, !isGenerating else { return nil }
        return GameSharing.id(field: field, mode: mode, first: firstMove)
    }
    func shareCode(progress: Bool) throws -> String {
        updateTime()
        return try GameSharing.encode(field: field, mode: mode, first: firstMove, seconds: seconds, progress: progress)
    }
    func importGame(_ shared: SharedGame, continueProgress: Bool) throws {
        guard !continueProgress || shared.hasProgress else { throw SharingError.noProgress }
        restart(shared.field.difficulty)
        mode = shared.mode; firstMove = shared.first
        storage.set(mode.rawValue, forKey: "game-mode")
        field = shared.restored(continueProgress: continueProgress)
        seconds = continueProgress ? shared.seconds : 0; accumulated = TimeInterval(seconds)
        sessionID = UUID(); sessionStartedAt = date(); recordedSession = false
        isPaused = field.phase == .playing
        loadBest(); finishIfNeeded()
    }
    func chooseMode(_ next: GameMode) {
        guard next != mode else { return }
        restart()
        mode = next
        storage.set(next.rawValue, forKey: "game-mode")
        loadBest()
    }
    func choose(_ level: Difficulty) { guard level != difficulty else { return }; restart(level) }
    func flag(_ index: Int) {
        guard !isPaused, !isGenerating else { return }
        hint = nil; field.flag(index)
    }
    func click(_ index: Int) {
        guard field.cells.indices.contains(index), !field.ended, !isPaused, !isGenerating else { return }
        hint = nil
        if flagMode && !field.cells[index].open { flag(index); return }
        guard !field.cells[index].flagged else { return }
        if field.phase == .ready { prepare(first: index); return }
        field.reveal(index)
        finishIfNeeded()
    }
    private func prepare(first: Int) {
        isGenerating = true
        let id = UUID(); generationID = id
        let level = difficulty, selectedMode = mode
        let existingMarks = field.cells.map(\.mark)
        let task = Task.detached(priority: .userInitiated) { () -> Minefield? in
            var random = SystemRandomNumberGenerator()
            return NoGuessGenerator.generate(difficulty: level, first: first, mode: selectedMode, using: &random, cancelled: { Task.isCancelled })?.field
        }
        worker = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.generationID == id, let result else { return }
            self.field = result
            self.firstMove = first
            for i in self.field.cells.indices { self.field.cells[i].mark = existingMarks[i] }
            self.field.flags = existingMarks.filter { $0 == .flag }.count
            self.isGenerating = false; self.worker = nil
            self.sessionID = UUID(); self.sessionStartedAt = self.date(); self.recordedSession = false
            self.field.reveal(first)
            if self.field.phase == .playing {
                if self.isPaused { return }
                self.startClock()
            } else { self.finishIfNeeded() }
        }
    }
    func togglePause() { if isPaused { resume() } else { pause() } }
    func pause() {
        guard field.phase == .playing || isGenerating, !isPaused else { return }
        stopClock(); isPaused = true
    }
    func resume() {
        guard isPaused else { return }
        isPaused = false
        if field.phase == .playing && !isGenerating { startClock() }
    }
    func showHint() {
        guard field.phase == .playing, !isPaused, !isGenerating else { return }
        hint = LogicalSolver.safeMove(in: field)
    }
    private func finishIfNeeded() {
        guard field.ended else { return }
        stopClock(); isPaused = false
        saveSession(result: field.phase == .won ? .won : .lost)
    }
    func finishSession() {
        guard sessionID != nil, !recordedSession else { return }
        stopClock()
        saveSession(result: field.phase == .won ? .won : field.phase == .lost ? .lost : .abandoned)
    }
    func resetRecords() { library.clear() }
    func savedBest(for level: Difficulty, mode selectedMode: GameMode? = nil) -> Int? {
        library.best(for: level, mode: selectedMode ?? mode)
    }
    func closeWindow() {
        finishSession(); stopClock(); worker?.cancel(); worker = nil; generationID = UUID(); isGenerating = false
    }
    private func saveSession(result: GameResult) {
        guard let id = sessionID, let startedAt = sessionStartedAt, !recordedSession else { return }
        recordedSession = true
        library.append(GameRecord(id: id, difficulty: difficulty, startedAt: startedAt, endedAt: date(), seconds: seconds, result: result, mode: mode))
    }
    private func startClock() {
        guard startedAt == nil else { return }
        startedAt = clock()
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTime() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func stopClock() {
        if let startedAt { accumulated += clock() - startedAt }
        startedAt = nil; timer?.invalidate(); timer = nil
        updateTime()
    }
    private func updateTime() {
        let running = startedAt.map { clock() - $0 } ?? 0
        let value = Int(accumulated + running)
        if value != seconds { seconds = value }
    }
    private func loadBest() { library.reload() }
}
