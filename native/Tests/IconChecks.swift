import AppKit

@main struct IconChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MinesweeperIconChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func png(_ w: Int, _ h: Int) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            return rep.representation(using: .png, properties: [:])!
        }
        let icons = CustomIcons(directory: root, changesApplicationIcon: false)
        try icons.install(png(900, 450), for: .flag)
        let normalized = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent("flag.png")))!
        precondition(normalized.pixelsWide == 128 && normalized.pixelsHigh == 64)
        try icons.install(png(10, 20), for: .mine)
        try icons.install(png(1024, 1024), for: .app)
        let reloaded = CustomIcons(directory: root, changesApplicationIcon: false)
        precondition(IconKind.allCases.allSatisfy { reloaded.images[$0] != nil })
        for invalid in [Data(), Data("<svg/>".utf8), Data(repeating: 0, count: 8*1024*1024+1), png(4097, 1)] {
            do { try icons.install(invalid, for: .flag); fatalError("Invalid import was accepted") } catch { }
        }
        precondition(icons.images[.flag] != nil)
        reloaded.reset(.flag)
        let final = CustomIcons(directory: root, changesApplicationIcon: false)
        precondition(final.images[.flag] == nil && final.images[.mine] != nil && final.images[.app] != nil)
        final.reset(.app); final.reset(.mine)
        precondition(CustomIcons(directory: root, changesApplicationIcon: false).images.isEmpty)
        print("图标检查通过：比例、透明格式、尺寸限制、错误保留、独立恢复和重启持久化")
    }
}
