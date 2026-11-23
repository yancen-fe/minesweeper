import Foundation

/// A proof uses only revealed clues and the total mine count, never hidden mine locations.
struct LogicalSolver {
    struct Constraint: Hashable {
        var cells: Set<Int>
        var mines: Int
    }
    struct Moves {
        var safe = Set<Int>()
        var mines = Set<Int>()
    }
    static func deductions(cells: [Cell], neighbors: [[Int]], totalMines: Int, knownMines: Set<Int>) -> Moves {
        var result = Moves()
        var constraints = Set<Constraint>()
        var unknown = Set<Int>()
        for i in cells.indices where !cells[i].open && !knownMines.contains(i) { unknown.insert(i) }
        for i in cells.indices where cells[i].open && cells[i].number > 0 {
            let remaining = Set(neighbors[i].filter { !cells[$0].open && !knownMines.contains($0) })
            let count = cells[i].number - neighbors[i].filter { knownMines.contains($0) }.count
            guard count >= 0, count <= remaining.count else { return Moves() }
            if !remaining.isEmpty { constraints.insert(Constraint(cells: remaining, mines: count)) }
        }
        let remainingMines = totalMines - knownMines.count
        if remainingMines == 0 { result.safe.formUnion(unknown); return result }
        if remainingMines == unknown.count { result.mines.formUnion(unknown); return result }
        // The global equation can directly complement frontier equations without enumerating unknown layouts.
        for constraint in constraints {
            if constraint.mines == remainingMines { result.safe.formUnion(unknown.subtracting(constraint.cells)) }
            if unknown.count - constraint.cells.count == remainingMines - constraint.mines {
                result.mines.formUnion(unknown.subtracting(constraint.cells))
            }
        }
        var equations = Array(constraints)
        var cursor = 0
        while cursor < equations.count {
            let a = equations[cursor]
            if a.mines == 0 { result.safe.formUnion(a.cells) }
            else if a.mines == a.cells.count { result.mines.formUnion(a.cells) }
            if !result.safe.isEmpty || !result.mines.isEmpty { return result }
            // Only strict subset subtraction is valid; overlapping equations alone do not imply a move.
            for b in equations.prefix(cursor) {
                let small: Constraint, large: Constraint
                if a.cells.count < b.cells.count { small = a; large = b }
                else if b.cells.count < a.cells.count { small = b; large = a }
                else { continue }
                guard small.cells.isSubset(of: large.cells) else { continue }
                let difference = Constraint(cells: large.cells.subtracting(small.cells), mines: large.mines - small.mines)
                guard difference.mines >= 0, difference.mines <= difference.cells.count else { continue }
                if difference.mines == 0 { result.safe.formUnion(difference.cells) }
                else if difference.mines == difference.cells.count { result.mines.formUnion(difference.cells) }
                if !result.safe.isEmpty || !result.mines.isEmpty { return result }
                if equations.count < 1200, constraints.insert(difference).inserted { equations.append(difference) }
            }
            cursor += 1
        }
        return result
    }
    static func isSolvable(_ field: Minefield, first: Int) -> Bool {
        var visible = field.cells.map { _ in Cell() }
        var knownMines = Set<Int>()
        var safe = Set([first])
        var opened = 0
        while !safe.isEmpty {
            var queue = Array(safe)
            safe.removeAll(keepingCapacity: true)
            while let index = queue.popLast() {
                if visible[index].open { continue }
                // Verification of a claimed safe reveal, never an input to the deduction rules.
                guard !field.cells[index].mine else { return false }
                visible[index].open = true
                visible[index].number = field.cells[index].number
                opened += 1
                if visible[index].number == 0 {
                    queue.append(contentsOf: field.adjacency[index].filter { !visible[$0].open })
                }
            }
            if opened == field.cells.count - field.difficulty.mines { return true }
            while true {
                let moves = deductions(cells: visible, neighbors: field.adjacency, totalMines: field.difficulty.mines, knownMines: knownMines)
                safe.formUnion(moves.safe)
                let newMines = moves.mines.subtracting(knownMines)
                knownMines.formUnion(newMines)
                if !safe.isEmpty || newMines.isEmpty { break }
            }
        }
        return false
    }
    /// Player flags are deliberately ignored: an incorrect flag must never make a hint unsafe.
    static func safeMove(in field: Minefield) -> Int? {
        var mines = Set<Int>()
        while true {
            let moves = deductions(cells: field.cells, neighbors: field.adjacency, totalMines: field.difficulty.mines, knownMines: mines)
            if let first = moves.safe.min() { return first }
            let additions = moves.mines.subtracting(mines)
            if additions.isEmpty { return nil }
            mines.formUnion(additions)
        }
    }
}
struct NoGuessGenerator {
    static func generate<R: RandomNumberGenerator>(difficulty: Difficulty, first: Int, mode: GameMode, using random: inout R, cancelled: () -> Bool = { false }) -> (field: Minefield, attempts: Int)? {
        guard !cancelled() else { return nil }
        if mode == .classic {
            var field = Minefield(difficulty)
            field.plant(at: first, using: &random)
            return (field, 1)
        }
        return generate(difficulty: difficulty, first: first, using: &random, cancelled: cancelled)
    }

    static func generate<R: RandomNumberGenerator>(difficulty: Difficulty, first: Int, using random: inout R, cancelled: () -> Bool = { false }) -> (field: Minefield, attempts: Int)? {
        var attempts = 0
        while !cancelled() {
            var field = Minefield(difficulty)
            field.plant(at: first, using: &random)
            attempts += 1
            if LogicalSolver.isSolvable(field, first: first) { return (field, attempts) }
        }
        return nil
    }
}
