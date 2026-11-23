import Foundation

struct SharedGame: Sendable {
    let field: Minefield
    let mode: GameMode
    let first: Int
    let seconds: Int
    let hasProgress: Bool
    var id: String { GameSharing.id(field: field, mode: mode, first: first) }
    func restored(continueProgress: Bool) -> Minefield {
        if continueProgress && hasProgress { return field }
        var result = field
        for i in result.cells.indices { result.cells[i].open = false; result.cells[i].mark = .none }
        result.opened = 0; result.flags = 0; result.phase = .playing; result.exploded = nil
        result.reveal(first)
        return result
    }
}
enum SharingError: LocalizedError {
    case invalid, unavailable, noProgress, notLogical
    var errorDescription: String? {
        switch self {
        case .invalid: "分享码无效或不完整"
        case .unavailable: "翻开第一格后即可分享本局"
        case .noProgress: "当前没有可继续的进度"
        case .notLogical: "分享码中的雷区不符合无猜玩法"
        }
    }
}
enum GameSharing {
    private static let levels: [Difficulty] = [.easy, .medium, .hard]
    private static let modes: [GameMode] = [.classic, .logical]
    private static func crc(_ bytes: [UInt8]) -> String {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
        }
        return String(format: "%08X", value ^ 0xffffffff)
    }
    private static func base64(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func payload(field: Minefield, mode: GameMode, first: Int, seconds: Int, progress: Bool) -> [UInt8] {
        let n = field.cells.count, mineBytes = (n + 7) / 8
        var bytes = [UInt8](repeating: 0, count: 9 + mineBytes + (progress ? (n + 3) / 4 : 0))
        bytes[0] = progress ? 1 : 0; bytes[1] = UInt8(levels.firstIndex(of: field.difficulty)!); bytes[2] = UInt8(modes.firstIndex(of: mode)!)
        bytes[3] = UInt8(first >> 8); bytes[4] = UInt8(first & 255)
        let elapsed = progress ? seconds : 0
        for i in 0..<4 { bytes[5+i] = UInt8((elapsed >> ((3-i)*8)) & 255) }
        for i in field.cells.indices {
            if field.cells[i].mine { bytes[9+i/8] |= 1 << (i%8) }
            if progress {
                let c = field.cells[i], state: UInt8 = c.open ? 1 : c.mark == .flag ? 2 : c.mark == .question ? 3 : 0
                bytes[9+mineBytes+i/4] |= state << ((i%4)*2)
            }
        }
        return bytes
    }
    static func id(field: Minefield, mode: GameMode, first: Int) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in payload(field: field, mode: mode, first: first, seconds: 0, progress: false) { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return "MS-" + String(format: "%016llX", hash)
    }
    static func encode(field: Minefield, mode: GameMode, first: Int?, seconds: Int, progress: Bool) throws -> String {
        guard let first, field.cells.indices.contains(first), field.phase != .ready else { throw SharingError.unavailable }
        guard !progress || field.phase == .playing else { throw SharingError.noProgress }
        guard seconds >= 0, seconds <= Int(UInt32.max) else { throw SharingError.invalid }
        let bytes = payload(field: field, mode: mode, first: first, seconds: seconds, progress: progress)
        return "MS1.\(base64(bytes)).\(crc(bytes))"
    }
    static func decode(_ input: String) throws -> SharedGame {
        guard input.utf8.count <= 2048 else { throw SharingError.invalid }
        let code = input.filter { !$0.isWhitespace }, parts = code.split(separator: ".", omittingEmptySubsequences: false)
        guard code.utf8.count <= 300, parts.count == 3, parts[0] == "MS1", parts[2].count == 8,
              parts[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw SharingError.invalid }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text) else { throw SharingError.invalid }
        let bytes = [UInt8](data)
        guard bytes.count >= 9, base64(bytes) == parts[1], crc(bytes) == parts[2].uppercased(), bytes[0] <= 1, bytes[1] <= 2, bytes[2] <= 1 else { throw SharingError.invalid }
        var field = Minefield(levels[Int(bytes[1])])
        let mode = modes[Int(bytes[2])], progress = bytes[0] == 1, first = Int(bytes[3])*256 + Int(bytes[4])
        let seconds = bytes[5..<9].reduce(0) { ($0 << 8) | Int($1) }, n = field.cells.count, mineBytes = (n+7)/8, stateBytes = (n+3)/4
        guard bytes.count == 9+mineBytes+(progress ? stateBytes : 0), first < n, progress || seconds == 0 else { throw SharingError.invalid }
        for i in n..<(mineBytes*8) where bytes[9+i/8] & (1 << (i%8)) != 0 { throw SharingError.invalid }
        if progress { for i in n..<(stateBytes*4) where (bytes[9+mineBytes+i/4] >> ((i%4)*2)) & 3 != 0 { throw SharingError.invalid } }
        for i in field.cells.indices {
            field.cells[i].mine = bytes[9+i/8] & (1 << (i%8)) != 0
            if progress {
                let state = (bytes[9+mineBytes+i/4] >> ((i%4)*2)) & 3
                field.cells[i].open = state == 1; field.cells[i].mark = state == 2 ? .flag : state == 3 ? .question : .none
            }
        }
        guard field.cells.filter(\.mine).count == field.difficulty.mines,
              ([first] + field.neighbors(first)).allSatisfy({ !field.cells[$0].mine }),
              !field.cells.contains(where: { $0.open && $0.mine }) else { throw SharingError.invalid }
        for i in field.cells.indices { field.cells[i].number = field.neighbors(i).filter { field.cells[$0].mine }.count }
        field.flags = field.cells.filter(\.flagged).count; field.opened = field.cells.filter(\.open).count; field.phase = .playing
        guard !progress || (field.cells[first].open && field.opened < n-field.difficulty.mines && field.flags <= field.difficulty.mines) else { throw SharingError.invalid }
        guard mode != .logical || LogicalSolver.isSolvable(field, first: first) else { throw SharingError.notLogical }
        return SharedGame(field: field, mode: mode, first: first, seconds: seconds, hasProgress: progress)
    }
}
