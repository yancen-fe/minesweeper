import SwiftUI
import AppKit

struct GameShareView: View {
    let game: GameModel
    let close: () -> Void
    @State private var code = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClassicDialogHeader(title: "分享本局", close: close)
            if let id = game.shareID {
                Text(id).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).accessibilityLabel("本局 ID \(id)")
                Text("分享码可在 Mac 和 Windows 离线导入").foregroundStyle(Palette.muted)
                Button("复制本局挑战") { copy(progress: false) }
                    .buttonStyle(ClassicButtonStyle(height: 30))
                Text("相同雷区和首步位置，用时从零开始").foregroundStyle(Palette.muted)
                Button("复制当前进度") { copy(progress: true) }
                    .buttonStyle(ClassicButtonStyle(height: 30)).disabled(game.field.phase != .playing)
                Text("保留翻格、旗子、问号和用时").foregroundStyle(Palette.muted)
                if !code.isEmpty {
                    ScrollView { Text(code).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                        .classicScrollbars().frame(height: 54).classicPanel(inset: true).accessibilityLabel("分享码")
                }
                Text(message).foregroundStyle(Palette.muted).accessibilityAddTraits(.updatesFrequently)
            } else {
                Spacer()
                Text("翻开第一格后即可分享本局").foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }.padding(14).font(AppTypography.rounded(12)).foregroundStyle(Palette.ink)
    }
    private func copy(progress: Bool) {
        do {
            code = try game.shareCode(progress: progress)
            NSPasteboard.general.clearContents()
            message = NSPasteboard.general.setString(code, forType: .string) ? (progress ? "已复制进度码" : "已复制挑战码") : "未能写入剪贴板，可选中分享码复制"
        } catch { message = error.localizedDescription }
    }
}

struct GameImportView: View {
    let game: GameModel
    let close: () -> Void
    @State private var code = ""
    @State private var preview: SharedGame?
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClassicDialogHeader(title: "导入对局", close: close)
            Text("粘贴挑战码或进度码").foregroundStyle(Palette.muted)
            TextEditor(text: $code).font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden).classicScrollbars().padding(5).frame(height: 70).classicPanel(inset: true)
                .focusEffectDisabled().accessibilityLabel("分享码")
                .onChange(of: code) { preview = nil; message = "" }
            HStack {
                Button("粘贴") { code = NSPasteboard.general.string(forType: .string) ?? "" }
                Button("读取分享码", action: inspect).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(ClassicButtonStyle(height: 28))
            if let preview {
                Text(preview.id).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text("\(preview.field.difficulty.classicTitle) · \(preview.mode.title)").foregroundStyle(Palette.muted)
                if preview.hasProgress {
                    Text("已翻开 \(preview.field.opened) 格 · \(GameDuration.text(preview.seconds))").foregroundStyle(Palette.muted)
                } else { Text("这份分享码只包含雷区").foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
                HStack {
                    Button("从头挑战") { apply(preview, continueProgress: false) }
                    if preview.hasProgress { Button("继续进度") { apply(preview, continueProgress: true) } }
                }.buttonStyle(ClassicButtonStyle(height: 30))
            } else {
                Text(message).foregroundStyle(Palette.muted).accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
            }
        }.padding(14).font(AppTypography.rounded(12)).foregroundStyle(Palette.ink)
    }
    private func inspect() {
        do { preview = try GameSharing.decode(code); message = "" }
        catch { preview = nil; message = error.localizedDescription }
    }
    private func apply(_ shared: SharedGame, continueProgress: Bool) {
        do {
            GameWindowTransitions.choose(shared.field.difficulty, game: game)
            try game.importGame(shared, continueProgress: continueProgress)
            close(); game.resume()
        } catch { message = error.localizedDescription }
    }
}
