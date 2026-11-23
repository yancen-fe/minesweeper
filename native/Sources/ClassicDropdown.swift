import SwiftUI
import AppKit
import Observation

struct ClassicChoice: Identifiable {
    let id: String
    let title: String
    var separatorAfter = false
}
@MainActor @Observable final class ClassicDropdownState {
    var owner: String?
    var anchor = CGRect.zero
    var choices: [ClassicChoice] = []
    var selected: String?
    var highlighted = 0
    var label = ""
    var width: CGFloat = 144
    private var choose: ((String) -> Void)?
    private var restoreFocus: (() -> Void)?
    func show(id: String, anchor: CGRect, choices: [ClassicChoice], selected: String?, label: String, width: CGFloat, restore: @escaping () -> Void = {}, choose: @escaping (String) -> Void) {
        self.owner = id; self.anchor = anchor; self.choices = choices; self.selected = selected
        self.label = label; self.width = width; self.choose = choose; self.restoreFocus = restore
        highlighted = choices.firstIndex { $0.id == selected } ?? 0
    }
    func dismiss(restore: Bool = false) {
        let focus = restoreFocus
        owner = nil; choices = []; choose = nil; restoreFocus = nil
        if restore { focus?() }
    }
    func commit(_ index: Int) {
        guard choices.indices.contains(index) else { return }
        let action = choose, value = choices[index].id
        dismiss(restore: true); action?(value)
    }
    func step(_ direction: Int) {
        guard !choices.isEmpty else { return }
        highlighted = (highlighted + direction + choices.count) % choices.count
    }
}
struct ClassicDropdown: View {
    let title: String
    @Binding var selection: String
    let choices: [ClassicChoice]
    @State private var id = UUID().uuidString
    @State private var anchor = CGRect.zero
    @FocusState private var focused: Bool
    @Environment(ClassicDropdownState.self) private var menus
    private var value: String { choices.first { $0.id == selection }?.title ?? "" }
    private func open() {
        if menus.owner == id { menus.dismiss(restore: true); return }
        menus.show(id: id, anchor: anchor, choices: choices, selected: selection, label: title, width: max(124, anchor.width), restore: { focused = true }) { selection = $0 }
    }
    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text(value).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ClassicDownArrow().frame(width: 8, height: 5)
            }.padding(.horizontal, 7).frame(maxWidth: .infinity)
        }
        .buttonStyle(ClassicButtonStyle(selected: menus.owner == id, horizontal: 0, height: 27))
        .focusEffectDisabled().focused($focused).accessibilityLabel(title).accessibilityValue(value)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("game-window")) } action: { rect in
            anchor = rect; if menus.owner == id { menus.anchor = rect }
        }
        .onKeyPress(.downArrow) { open(); return .handled }
        .onKeyPress(.upArrow) { open(); return .handled }
        .onDisappear { if menus.owner == id { menus.dismiss() } }
    }
}
struct ClassicDownArrow: View {
    var body: some View {
        Canvas { context, size in
            var path = Path(); path.addLines([.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width/2, y: size.height)]); path.closeSubpath()
            context.fill(path, with: .foreground)
        }.accessibilityHidden(true)
    }
}
struct ClassicDropdownLayer: View {
    @Environment(ClassicDropdownState.self) private var menus
    @FocusState private var focused: Bool
    var body: some View {
        GeometryReader { proxy in
            if menus.owner != nil {
                let width = min(menus.width, proxy.size.width - 16)
                let height = CGFloat(menus.choices.count) * 28 + CGFloat(menus.choices.filter(\.separatorAfter).count) * 6 + 8
                let x = max(8, min(menus.anchor.minX, proxy.size.width - width - 8))
                let below = menus.anchor.maxY + 3
                let y = max(8, min(below + height <= proxy.size.height - 8 ? below : menus.anchor.minY - height - 3, proxy.size.height - height - 8))
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001).contentShape(.rect).onTapGesture { menus.dismiss() }.accessibilityHidden(true)
                    VStack(spacing: 0) {
                        ForEach(Array(menus.choices.enumerated()), id: \.element.id) { index, choice in
                            Button { menus.commit(index) } label: {
                                HStack(spacing: 6) {
                                    Text(menus.selected == choice.id ? "✓" : "").frame(width: 14)
                                    Text(choice.title).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(AppTypography.rounded(12)).padding(.horizontal, 5).frame(height: 28)
                                .foregroundStyle(menus.highlighted == index ? .white : Palette.ink)
                                .background(menus.highlighted == index ? Palette.blue : Palette.paper)
                                .contentShape(.rect)
                            }.buttonStyle(.plain)
                            .onHover { hovering in if hovering { menus.highlighted = index } }
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(menus.selected == choice.id ? .isSelected : [])
                            if choice.separatorAfter {
                                Rectangle().fill(Palette.line).frame(height: 1).overlay(alignment: .bottom) { Color.white.frame(height: 1).offset(y: 1) }.padding(.vertical, 2.5).padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(4).frame(width: width).classicDialogSurface()
                    .focusable().focusEffectDisabled().focused($focused)
                    .accessibilityElement(children: .contain).accessibilityLabel(menus.label)
                    .onKeyPress(.downArrow) { menus.step(1); return .handled }
                    .onKeyPress(.upArrow) { menus.step(-1); return .handled }
                    .onKeyPress(.return) { menus.commit(menus.highlighted); return .handled }
                    .onKeyPress(.space) { menus.commit(menus.highlighted); return .handled }
                    .onKeyPress(.escape) { menus.dismiss(restore: true); return .handled }
                    .onKeyPress(.tab) { menus.dismiss(restore: true); return .ignored }
                    .onAppear { focused = true }
                    .offset(x: x, y: y)
                }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in menus.dismiss() }
    }
}
struct ClassicTopMenu: View {
    let choose: (String) -> Void
    @State private var anchor = CGRect.zero
    @FocusState private var focused: Bool
    private let id = "main-menu"
    @Environment(ClassicDropdownState.self) private var menus
    private func open() {
        if menus.owner == id { menus.dismiss(restore: true); return }
        menus.show(id: id, anchor: anchor, choices: [
            .init(id: "new", title: "新一局"), .init(id: "window", title: "新建窗口", separatorAfter: true),
            .init(id: "share", title: "分享本局"), .init(id: "import", title: "导入对局", separatorAfter: true), .init(id: "history", title: "历史记录"),
            .init(id: "settings", title: "设置")
        ], selected: nil, label: "菜单", width: 150, restore: { focused = true }, choose: choose)
    }
    var body: some View {
        Button(action: open) { Image(systemName: "ellipsis").frame(width: 28) }
            .buttonStyle(ClassicButtonStyle(selected: menus.owner == id, horizontal: 0)).focusEffectDisabled().focused($focused).accessibilityLabel("菜单")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("game-window")) } action: { rect in anchor = rect; if menus.owner == id { menus.anchor = rect } }
            .onKeyPress(.downArrow) { open(); return .handled }
    }
}
struct ClassicTabs: View {
    @Environment(ClassicDropdownState.self) private var menus
    let title: String
    @Binding var selection: String
    let choices: [ClassicChoice]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices) { choice in
                Button { menus.dismiss(); selection = choice.id } label: { Text(choice.title).frame(maxWidth: .infinity) }
                    .buttonStyle(ClassicButtonStyle(selected: choice.id == selection, horizontal: 0, height: 26))
                    .accessibilityAddTraits(choice.id == selection ? .isSelected : [])
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
struct ClassicCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                Text(isOn ? "✓" : "").font(AppTypography.rounded(12, weight: .bold)).frame(width: 16, height: 16).background(Color(white: 0.86)).overlay(ClassicBevel(inset: true, thickness: 1))
                Text(title)
                Spacer(minLength: 0)
            }.frame(height: 27).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(isOn ? "开启" : "关闭")
    }
}

private struct ClassicContextClick: NSViewRepresentable {
    let open: (NSPoint) -> Void
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.open = open }
    final class Surface: NSView {
        var open: ((NSPoint) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
                  bounds.contains(convert(point, from: superview)) else { return nil }
            return self
        }
        override func rightMouseDown(with event: NSEvent) { open?(convert(event.locationInWindow, from: nil)) }
        override func mouseDown(with event: NSEvent) { open?(convert(event.locationInWindow, from: nil)) }
    }
}
struct ClassicContextMenu: ViewModifier {
    @Environment(ClassicDropdownState.self) private var menus
    let choices: [ClassicChoice]
    let choose: (String) -> Void
    @State private var id = UUID().uuidString
    @State private var anchor = CGRect.zero
    func body(content: Content) -> some View {
        content.overlay {
            ClassicContextClick { point in
                menus.show(id: id, anchor: CGRect(x: anchor.minX + point.x, y: anchor.minY + point.y, width: 0, height: 0), choices: choices, selected: nil, label: "记录菜单", width: 172, choose: choose)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("game-window")) } action: { anchor = $0 }
        .onDisappear { if menus.owner == id { menus.dismiss() } }
    }
}
