import SwiftUI

struct GameSettingsView: View {
    var close: () -> Void = { }
    @State private var tab = "game"
    @Bindable private var icons = CustomIcons.shared
    @AppStorage("reveal-on-press") private var revealOnPress = true
    @AppStorage("rounded-numbers") private var roundedNumbers = true
    @AppStorage("triangle-flags") private var triangleFlags = true
    @AppStorage("small-flags") private var smallFlags = true
    @AppStorage("pause-overlay") private var pauseOverlay = true
    @AppStorage("show-game-result") private var showGameResult = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClassicDialogHeader(title: "设置", close: close, canClose: !icons.choosing)
            ClassicTabs(title: "设置分类", selection: $tab, choices: [.init(id: "game", title: "游戏"), .init(id: "icons", title: "图标")])
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if tab == "game" {
                        setting("翻格时机", selection: $revealOnPress, yes: "按下时", no: "松开时")
                        setting("棋盘数字", selection: $roundedNumbers, yes: "圆润", no: "经典")
                        setting("旗子形状", selection: $triangleFlags, yes: "三角旗", no: "方旗").disabled(icons.images[.flag] != nil)
                        setting("旗子大小", selection: $smallFlags, yes: "小巧", no: "标准")
                        ClassicCheckbox(title: "暂停遮罩", isOn: $pauseOverlay)
                        ClassicCheckbox(title: "完成后显示结果", isOn: $showGameResult)
                    } else {
                        iconRow(.app, title: "应用")
                        iconRow(.flag, title: "旗子")
                        iconRow(.mine, title: "地雷")
                        Text("应用图标用于 Dock").font(AppTypography.rounded(11)).foregroundStyle(Palette.muted)
                        if !icons.message.isEmpty {
                            Text(icons.message).font(AppTypography.rounded(11)).foregroundStyle(Palette.danger).accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                }.padding(.bottom, 4)
            }.classicScrollbars()
        }.padding(14).font(AppTypography.rounded(12)).foregroundStyle(Palette.ink)
    }
    private func setting(_ title: String, selection: Binding<Bool>, yes: String, no: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            ClassicDropdown(title: title, selection: Binding(get: { String(selection.wrappedValue) }, set: { selection.wrappedValue = $0 == "true" }), choices: [.init(id: "true", title: yes), .init(id: "false", title: no)]).frame(width: 152)
        }.frame(minHeight: 27)
    }
    private func iconRow(_ kind: IconKind, title: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = icons.images[kind] { Image(nsImage: image).resizable().scaledToFit().frame(width: kind == .app ? 34 : 26, height: kind == .app ? 34 : 26) }
                else if kind == .app, let image = NSImage(named: NSImage.applicationIconName) { Image(nsImage: image).resizable().scaledToFit() }
                else { BoardIconPreview(kind: kind, triangle: triangleFlags).frame(width: 26, height: 26).allowsHitTesting(false) }
            }.frame(width: 34, height: 34).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 0)
            Button("更换") { icons.choose(kind) }.buttonStyle(ClassicButtonStyle(horizontal: 8)).accessibilityLabel("更换\(title)图标")
            Button("恢复") { icons.reset(kind) }.buttonStyle(ClassicButtonStyle(horizontal: 8)).disabled(icons.images[kind] == nil).accessibilityLabel("恢复\(title)图标")
        }.frame(minHeight: 45).disabled(icons.choosing)
    }
}

// Settings show only the icon, without constructing a game field or drawing tiles.
private struct BoardIconPreview: View {
    let kind: IconKind
    let triangle: Bool
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 16, y: size.height / 16)
            if kind == .flag {
                for rect in [CGRect(x: 9, y: 1, width: 2, height: 12), CGRect(x: 6, y: 12, width: 7, height: 2), CGRect(x: 3, y: 14, width: 12, height: 2)] {
                    context.fill(Path(rect), with: .color(.black))
                }
                var flag = Path()
                flag.addLines(triangle ? [CGPoint(x: 9, y: 1), CGPoint(x: 2, y: 5), CGPoint(x: 9, y: 9)] : [CGPoint(x: 9, y: 1), CGPoint(x: 2, y: 3), CGPoint(x: 2, y: 8), CGPoint(x: 9, y: 6)])
                flag.closeSubpath(); context.fill(flag, with: .color(.red))
            } else {
                var rays = Path()
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4
                    rays.move(to: CGPoint(x: 8 + cos(angle) * 3.2, y: 8 + sin(angle) * 3.2))
                    rays.addLine(to: CGPoint(x: 8 + cos(angle) * 5.5, y: 8 + sin(angle) * 5.5))
                }
                context.stroke(rays, with: .color(.black), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 4, y: 4, width: 8, height: 8)), with: .color(.black))
                context.fill(Path(ellipseIn: CGRect(x: 5.3, y: 5, width: 1.8, height: 1.4)), with: .color(.white))
            }
        }
    }
}
