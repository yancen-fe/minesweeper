import AppKit
import ImageIO
import UniformTypeIdentifiers
import Observation

enum IconKind: String, CaseIterable { case app, flag, mine }
enum IconImportError: LocalizedError {
    case invalid
    var errorDescription: String? { "请选择 8 MB 以内的 PNG、JPG 或 ICO 图片" }
}

/// Store normalized copies, so moving the original image or updating the app keeps the selection.
@MainActor @Observable final class CustomIcons {
    static let shared = CustomIcons()
    private let directory: URL
    private let changesApplicationIcon: Bool
    private let originalAppIcon: NSImage?
    private(set) var images: [IconKind: NSImage] = [:]
    var message = ""
    var choosing = false
    init(directory: URL? = nil, changesApplicationIcon: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "com.yancen.minesweeper")/Icons", isDirectory: true)
        self.changesApplicationIcon = changesApplicationIcon
        originalAppIcon = changesApplicationIcon ? NSApp.applicationIconImage : nil
        for kind in IconKind.allCases {
            if let data = try? Data(contentsOf: file(kind)), let png = try? Self.normalize(data, kind: kind) {
                images[kind] = NSImage(data: png)
            }
        }
    }
    private func file(_ kind: IconKind) -> URL { directory.appendingPathComponent("\(kind.rawValue).png") }
    static func normalize(_ data: Data, kind: IconKind) throws -> Data {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.ico.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: kind == .app ? 512 : 128,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw IconImportError.invalid }
        return png
    }
    func install(_ data: Data, for kind: IconKind) throws {
        let png = try Self.normalize(data, kind: kind)
        guard let image = NSImage(data: png) else { throw IconImportError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: file(kind), options: .atomic)
        images[kind] = image
        if kind == .app { applyApplicationIcon() }
        message = ""
    }
    func reset(_ kind: IconKind) {
        do {
            if FileManager.default.fileExists(atPath: file(kind).path) { try FileManager.default.removeItem(at: file(kind)) }
            images[kind] = nil
            if kind == .app { applyApplicationIcon() }
            message = ""
        } catch { message = "暂时无法恢复图标" }
    }
    func applyApplicationIcon() {
        if changesApplicationIcon { NSApp.applicationIconImage = images[.app] ?? originalAppIcon }
    }
    func choose(_ kind: IconKind) {
        guard !choosing, let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        message = ""; choosing = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .ico]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.prompt = "选择"; panel.title = "选择图标"
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.choosing = false
                guard response == .OK, let url = panel.url else { return }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= 8 * 1024 * 1024 else { throw IconImportError.invalid }
                    try self.install(Data(contentsOf: url), for: kind)
                } catch { self.message = error is IconImportError ? error.localizedDescription : "暂时无法读取这张图片" }
            }
        }
    }
}
