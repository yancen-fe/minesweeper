import SwiftUI
import AppKit
import Observation

@main struct MinesweeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("扫雷", id: "game") { GameWindowRoot() }
            .windowStyle(.titleBar).windowResizability(.contentMinSize)
            .defaultSize(width: 360, height: 500).defaultPosition(.center)
            .commands { GameWindowCommands() }
    }
}
@MainActor @Observable final class GameWindowContext {
    let game = GameModel()
    let presentation = GamePresentation()
    let menus = ClassicDropdownState()
    let motion = WindowMotion()
    weak var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    func attach(_ window: NSWindow?) {
        guard let window else { return }
        self.window = window; window.tabbingMode = .disallowed
        guard closeObserver == nil else { return }
        GameWindowRegistry.register(self)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.game.closeWindow(); GameWindowRegistry.unregister(self)
                if let observer = self.closeObserver { NotificationCenter.default.removeObserver(observer); self.closeObserver = nil }
            }
        }
    }
}
struct GameWindowFocusKey: FocusedValueKey { typealias Value = GameWindowContext }
extension FocusedValues {
    var gameWindow: GameWindowContext? {
        get { self[GameWindowFocusKey.self] }
        set { self[GameWindowFocusKey.self] = newValue }
    }
}
struct GameWindowRoot: View {
    @State private var context = GameWindowContext()
    var body: some View {
        GameView(game: context.game, presentation: context.presentation)
            .environment(context).environment(context.menus).environment(context.motion)
            .focusedSceneValue(\.gameWindow, context).preferredColorScheme(.light)
            .onAppear {
                GameWindowRegistry.register(context)
                CustomIcons.shared.applyApplicationIcon()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { event in
                if let window = event.object as? NSWindow, window === context.window {
                    context.game.pause(); context.menus.dismiss()
                }
            }

    }
}
struct GameWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.gameWindow) private var focused
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新一局") { focused?.game.restart() }.keyboardShortcut("n")
                .disabled(focused == nil || focused?.presentation.dialog != nil)
            Button("新建窗口") { openWindow(id: "game") }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("游戏") {
            ForEach(Array(Difficulty.allCases.enumerated()), id: \.element.id) { index, level in
                Button(level.classicTitle) {
                    if let focused { GameWindowTransitions.choose(level, game: focused.game) }
                }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(focused == nil || focused?.presentation.dialog != nil)
            }
            Divider()
            Button(focused?.game.isPaused == true ? "继续游戏" : "暂停游戏") { focused?.game.togglePause() }
                .keyboardShortcut("p").disabled(focused == nil || focused?.presentation.dialog != nil || !(focused!.game.canPause || focused!.game.isPaused))
            Button("历史记录") { show(.history) }.keyboardShortcut("y").disabled(focused == nil)
            Divider()
            Button("分享本局") { show(.share) }.disabled(focused == nil)
            Button("导入对局") { show(.importGame) }.disabled(focused == nil)
        }
        CommandGroup(replacing: .appSettings) { Button("设置…") { show(.settings) }.keyboardShortcut(",").disabled(focused == nil) }
        CommandGroup(replacing: .help) { }
    }
    private func show(_ dialog: GamePresentation.Dialog) {
        if let focused { focused.presentation.show(dialog, game: focused.game) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationWillTerminate(_ notification: Notification) { GameWindowRegistry.finishAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct GameView: View {
    @Bindable var game: GameModel
    let presentation: GamePresentation
    @Environment(GameWindowContext.self) private var context
    @Environment(ClassicDropdownState.self) private var menus
    @Environment(WindowMotion.self) private var motion
    @Environment(\.openWindow) private var openWindow
    @AppStorage("show-game-result") private var showGameResult = true
    private var minimumSize: CGSize {
        motion.isTransitioning ? CGSize(width: 300, height: 338) : GameWindowLayout.minimumContentSize(for: game.difficulty)
    }
    var body: some View {
        VStack(spacing: 10) {
            header
            instruments
            BoardViewport(game: game, inputBlocked: presentation.dialog != nil || menus.owner != nil).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12).font(AppTypography.rounded(12)).fontDesign(.rounded).frame(minWidth: minimumSize.width,
                                 minHeight: minimumSize.height)
        .background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.blue)
        .background(WindowLayoutReader(difficulty: game.difficulty, context: context))
        .overlay {
            if let dialog = presentation.dialog {
                GeometryReader { proxy in
                    ZStack {
                        Color.black.opacity(0.22).contentShape(.rect).onTapGesture { }
                        Group {
                            switch dialog {
                            case .history: HistoryView(game: game, close: presentation.close)
                            case .settings: GameSettingsView(close: presentation.close)
                            case .share: GameShareView(game: game, close: presentation.close)
                            case .importGame: GameImportView(game: game, close: presentation.close)
                            case .result:
                                if let completion = presentation.completion {
                                    GameResultView(completion: completion, close: presentation.close, restart: {
                                        presentation.close(); game.restart()
                                    })
                                }
                            }
                        }
                        .frame(width: min(dialog == .history ? 440 : dialog == .settings ? 340 : dialog == .result ? 320 : dialog == .share || dialog == .importGame ? 360 : 280, proxy.size.width - 24),
                               height: min(dialog == .history ? 550 : dialog == .settings ? 352 : dialog == .result ? 280 : dialog == .share || dialog == .importGame ? 360 : 200, proxy.size.height - 24))
                        .classicDialogSurface()
                    }.frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .overlay { ClassicDropdownLayer() }
        .coordinateSpace(name: "game-window")
        .onChange(of: presentation.dialog) { menus.dismiss() }
        .transaction { transaction in transaction.animation = nil; transaction.disablesAnimations = true }
        .onChange(of: game.field.phase) {
            if showGameResult { presentation.showCompletion(game: game) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in game.pause() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in game.pause() }
    }
    private var header: some View {
        HStack(spacing: 8) {
            ClassicDropdown(title: "难度", selection: Binding(get: { game.difficulty.rawValue }, set: { if let level = Difficulty(rawValue: $0) { GameWindowTransitions.choose(level, game: game) } }), choices: Difficulty.allCases.map { .init(id: $0.rawValue, title: $0.classicTitle) })
                .frame(width: 88).disabled(presentation.dialog != nil)
            ClassicDropdown(title: "玩法", selection: Binding(get: { game.mode.rawValue }, set: { if let mode = GameMode(rawValue: $0) { game.chooseMode(mode) } }), choices: GameMode.allCases.map { .init(id: $0.rawValue, title: $0.title) })
                .frame(width: 96).disabled(presentation.dialog != nil)
                .accessibilityHint("经典随机可能需要猜测，切换玩法会重开对局")
            Spacer(minLength: 0)
            Button { game.togglePause() } label: { Label(game.isPaused ? "继续" : "暂停", systemImage: game.isPaused ? "play.fill" : "pause.fill") }
                .buttonStyle(ClassicButtonStyle(selected: game.isPaused)).disabled((!game.canPause && !game.isPaused) || presentation.dialog != nil)
                .accessibilityLabel(game.isPaused ? "继续游戏" : "暂停游戏")
            ClassicTopMenu { action in
                switch action {
                case "new": game.restart()
                case "window": openWindow(id: "game")
                case "history": presentation.show(.history, game: game)
                case "settings": presentation.show(.settings, game: game)
                case "share": presentation.show(.share, game: game)
                case "import": presentation.show(.importGame, game: game)
                default: break
                }
            }

        }
    }
    private var instruments: some View {
        HStack {
            DigitalCounter(value: game.difficulty.mines - game.field.flags, title: "剩余雷数")
            Spacer(minLength: 45)
            GameClock(game: game)
        }.padding(6).classicPanel(inset: true)
        .overlay {
            Button { game.restart() } label: { ClassicFace(phase: game.field.phase, paused: game.isPaused).frame(width: 29, height: 29) }
                .buttonStyle(ClassicButtonStyle(horizontal: 5, height: 40)).accessibilityLabel("新一局")
        }
    }
}

extension Difficulty {
    var classicTitle: String { switch self { case .easy: "初级"; case .medium: "中级"; case .hard: "专家" } }
}
struct BoardViewport: View {
    @Environment(WindowMotion.self) private var motion
    let game: GameModel
    var inputBlocked = false
    @AppStorage("reveal-on-press") private var revealOnPress = true
    @AppStorage("rounded-numbers") private var roundedNumbers = true
    @AppStorage("triangle-flags") private var triangleFlags = true
    @AppStorage("small-flags") private var smallFlags = true
    @AppStorage("pause-overlay") private var pauseOverlay = true
    var body: some View {
        GeometryReader { proxy in
            let layout = BoardLayout(difficulty: game.difficulty, viewport: proxy.size)
            NativeBoard(field: game.field, tileSize: layout.tile, blocked: inputBlocked || game.isPaused || game.isGenerating || motion.isTransitioning, animateChanges: motion.isTransitioning, revealOnPress: revealOnPress, roundedNumbers: roundedNumbers, triangleFlags: triangleFlags, smallFlags: smallFlags, flagImage: CustomIcons.shared.images[.flag], mineImage: CustomIcons.shared.images[.mine], hint: nil,
                        reveal: { index in
                            game.click(index)
                            return BoardRenderState(field: game.field, blocked: inputBlocked || game.isPaused || game.isGenerating || motion.isTransitioning)
                        }, flag: { index in
                            game.flag(index)
                            return BoardRenderState(field: game.field, blocked: inputBlocked || game.isPaused || game.isGenerating || motion.isTransitioning)
                        }, pause: { if !inputBlocked { game.togglePause() } })
                .frame(width: layout.size.width, height: layout.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(Palette.bed)
                .overlay(ClassicBevel(inset: true))
                .overlay {
                    if game.isPaused && !inputBlocked && pauseOverlay {
                        PauseOverlay(resume: game.resume)
                    }
                }

        }
    }
}
struct PauseOverlay: View {
    let resume: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(.rect).onTapGesture { }
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Button(action: resume) {
                    Label("继续游戏", systemImage: "play.fill")
                }.buttonStyle(ClassicButtonStyle(horizontal: 14, height: 32))
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .background(Palette.paper.opacity(0.97))
            .overlay(ClassicBevel())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("游戏已暂停")
    }
}
struct GameClock: View {
    let game: GameModel
    var body: some View { DigitalCounter(value: game.seconds, title: "用时") }
}
struct ClassicBevel: View {
    var inset = false
    var thickness: CGFloat = 2
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, t = thickness
            var light = Path()
            light.addLines([.zero, CGPoint(x: w, y: 0), CGPoint(x: w-t, y: t), CGPoint(x: t, y: t), CGPoint(x: t, y: h-t), CGPoint(x: 0, y: h)]); light.closeSubpath()
            var dark = Path()
            dark.addLines([CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h), CGPoint(x: t, y: h-t), CGPoint(x: w-t, y: h-t), CGPoint(x: w-t, y: t)]); dark.closeSubpath()
            context.fill(light, with: .color(inset ? Palette.line : .white))
            context.fill(dark, with: .color(inset ? .white : Palette.line))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
extension View {
    func classicPanel(inset: Bool = false) -> some View { background(Palette.paper).overlay(ClassicBevel(inset: inset)) }
}
struct ClassicButtonStyle: ButtonStyle {
    var selected = false
    var horizontal: CGFloat = 10
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(AppTypography.rounded(12, weight: .medium))
            .foregroundStyle(enabled ? Palette.ink : Palette.muted.opacity(0.6))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .padding(.horizontal, horizontal).frame(height: height)
            .background(selected ? Color(white: 0.70) : Palette.paper)
            .overlay(ClassicBevel(inset: configuration.isPressed || selected))
            .contentShape(.rect)
            .focusEffectDisabled()
    }
}
struct ClassicDialogHeader: View {
    let title: String
    let close: () -> Void
    var canClose = true
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(AppTypography.rounded(13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            DialogCloseButton(close: close).disabled(!canClose)
        }
        .padding(.horizontal, 4).frame(height: 28).background(Palette.blue)
        .padding(.horizontal, -9).padding(.top, -9)
    }
}
struct ClassicDialogFrame: View {
    var body: some View {
        Canvas { context, size in
            let pairs: [(Double, Double)] = [(0.91, 0.28), (1, 0.5), (0.82, 0.64)]
            for (i, pair) in pairs.enumerated() {
                let d = CGFloat(i), w = size.width - d, h = size.height - d
                var light = Path()
                light.addLines([CGPoint(x: d, y: h), CGPoint(x: d, y: d), CGPoint(x: w, y: d), CGPoint(x: w-1, y: d+1), CGPoint(x: d+1, y: d+1), CGPoint(x: d+1, y: h-1)]); light.closeSubpath()
                var dark = Path()
                dark.addLines([CGPoint(x: w, y: d), CGPoint(x: w, y: h), CGPoint(x: d, y: h), CGPoint(x: d+1, y: h-1), CGPoint(x: w-1, y: h-1), CGPoint(x: w-1, y: d+1)]); dark.closeSubpath()
                context.fill(light, with: .color(Color(white: pair.0)))
                context.fill(dark, with: .color(Color(white: pair.1)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
extension View {
    func classicDialogSurface() -> some View {
        background(Palette.paper).overlay(ClassicDialogFrame()).compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 0, x: 3, y: 3)
    }
}
struct ClassicFace: View {
    let phase: GamePhase
    let paused: Bool
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 28
            context.scaleBy(x: scale, y: scale)
            let circle = Path(ellipseIn: CGRect(x: 1, y: 1, width: 26, height: 26))
            context.fill(circle, with: .color(Color(red: 1, green: 0.85, blue: 0)))
            context.stroke(circle, with: .color(.black), lineWidth: 1.4)
            if phase == .lost {
                for x: CGFloat in [8, 18] {
                    var eye = Path(); eye.addLines([CGPoint(x: x-2, y: 8), CGPoint(x: x+2, y: 12)])
                    eye.move(to: CGPoint(x: x-2, y: 12)); eye.addLine(to: CGPoint(x: x+2, y: 8))
                    context.stroke(eye, with: .color(.black), lineWidth: 1.7)
                }
            } else if phase == .won {
                context.fill(Path(CGRect(x: 5, y: 8, width: 8, height: 6)), with: .color(.black))
                context.fill(Path(CGRect(x: 15, y: 8, width: 8, height: 6)), with: .color(.black))
                context.fill(Path(CGRect(x: 12, y: 9, width: 4, height: 2)), with: .color(.black))
            } else {
                for x: CGFloat in [9, 19] {
                    context.fill(Path(CGRect(x: x-1, y: paused ? 10 : 9, width: paused ? 4 : 2, height: paused ? 1.5 : 3)), with: .color(.black))
                }
            }
            var mouth = Path(); mouth.move(to: CGPoint(x: 7, y: phase == .lost ? 23 : 18))
            if paused { mouth.addLine(to: CGPoint(x: 21, y: 18)) }
            else { mouth.addQuadCurve(to: CGPoint(x: 21, y: phase == .lost ? 23 : 18), control: CGPoint(x: 14, y: phase == .lost ? 12 : 27)) }
            context.stroke(mouth, with: .color(.black), lineWidth: 1.6)
        }.accessibilityHidden(true)
    }
}
struct DigitalCounter: View {
    let value: Int
    let title: String
    var body: some View {
        NativeCounter(value: value, title: title).frame(width: CounterSurface.displaySize(for: value).width, height: 34)
            .padding(2).background(.black).overlay(ClassicBevel(inset: true))
    }
}
struct WindowLayoutReader: NSViewRepresentable {
    let difficulty: Difficulty
    let context: GameWindowContext
    func makeNSView(context: Context) -> LayoutHost {
        let view = LayoutHost(); view.owner = self.context; view.requested = difficulty; return view
    }
    func updateNSView(_ view: LayoutHost, context: Context) { view.owner = self.context; view.requested = difficulty; view.scheduleFit() }
    final class LayoutHost: NSView {
        var requested: Difficulty = .easy
        var owner: GameWindowContext?
        private var applied: Difficulty?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); owner?.attach(window); scheduleFit() }
        func scheduleFit() {
            guard let owner, window != nil, requested != applied else { return }
            if owner.motion.isTransitioning { applied = requested; return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let owner = self.owner, let window = self.window,
                      self.applied != self.requested, !owner.motion.isTransitioning,
                      let screen = window.screen ?? NSScreen.main else { return }
                self.applied = self.requested
                let frame = GameWindowLayout.frame(difficulty: self.requested, current: window.frame, visible: screen.visibleFrame)
                FixedWindowSizing.unlock(window); window.contentMinSize = GameWindowLayout.minimumContentSize(for: self.requested)
                if window.frame != frame { window.setFrame(frame, display: true, animate: false) }
                FixedWindowSizing.lock(window, frame: frame)
            }
        }
    }
}
@MainActor enum GameWindowRegistry {
    private static var contexts: [ObjectIdentifier: GameWindowContext] = [:]
    static func register(_ context: GameWindowContext) { contexts[ObjectIdentifier(context.game)] = context }
    static func unregister(_ context: GameWindowContext) { contexts.removeValue(forKey: ObjectIdentifier(context.game)) }
    static func context(for game: GameModel) -> GameWindowContext? { contexts[ObjectIdentifier(game)] }
    static func finishAll() { for context in contexts.values { context.game.closeWindow() } }
}
@MainActor @Observable final class WindowMotion {
    var isTransitioning = false
    var token = UUID()
}
@MainActor enum GameWindowTransitions {
    static func choose(_ difficulty: Difficulty, game: GameModel) {
        guard difficulty != game.difficulty else { return }
        guard let owner = GameWindowRegistry.context(for: game) else { game.choose(difficulty); return }
        let motion = owner.motion, token = UUID()
        motion.token = token
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        motion.isTransitioning = animated
        guard let window = owner.window, let screen = window.screen ?? NSScreen.main else {
            game.choose(difficulty); motion.isTransitioning = false; return
        }
        let target = GameWindowLayout.frame(difficulty: difficulty, current: window.frame, visible: screen.visibleFrame)
        FixedWindowSizing.unlock(window)
        window.contentMinSize = CGSize(width: 300, height: 338)
        game.choose(difficulty)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.20 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = animated
            if animated { window.animator().setFrame(target, display: true) }
            else { window.setFrame(target, display: true, animate: false) }
        } completionHandler: {
            MainActor.assumeIsolated {
                guard motion.token == token else { return }
                motion.isTransitioning = false
                FixedWindowSizing.lock(window, frame: target)
            }
        }
    }
}


struct DialogCloseButton: View {
    let close: () -> Void
    var body: some View {
        Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22) }
            .buttonStyle(ClassicButtonStyle(horizontal: 0, height: 22)).keyboardShortcut(.cancelAction).accessibilityLabel("关闭弹窗")
    }
}

// Native Chinese rounded face, with a system rounded fallback on installations without Yuanti.
enum AppTypography {
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold || weight == .bold ? "STYuanti-SC-Bold" : "STYuanti-SC-Regular"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight, design: .rounded)
    }
}
