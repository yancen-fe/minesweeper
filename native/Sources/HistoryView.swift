import SwiftUI

struct HistoryView: View {
    let game: GameModel
    var close: () -> Void = { }
    @State private var filter = HistoryFilter()
    @State private var confirmReset = false
    private var records: [GameRecord] { filter.apply(game.history) }
    private var statistics: HistoryStatistics { HistoryStatistics(records: records) }
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 470
            VStack(spacing: 12) {
                ClassicDialogHeader(title: "历史记录", close: { if confirmReset { confirmReset = false } else { close() } })

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ClassicDropdown(title: "难度筛选", selection: Binding(get: { filter.difficulty?.rawValue ?? "all" }, set: { filter.difficulty = Difficulty(rawValue: $0) }), choices: [.init(id: "all", title: "全部难度")] + Difficulty.allCases.map { .init(id: $0.rawValue, title: $0.classicTitle) })
                        ClassicDropdown(title: "玩法筛选", selection: Binding(get: { filter.mode?.rawValue ?? "all" }, set: { filter.mode = GameMode(rawValue: $0) }), choices: [.init(id: "all", title: "全部玩法")] + GameMode.allCases.map { .init(id: $0.rawValue, title: $0.title) })
                    }
                    HStack(spacing: 8) {
                        ClassicDropdown(title: "结果筛选", selection: Binding(get: { filter.result?.rawValue ?? "all" }, set: { filter.result = GameResult(rawValue: $0) }), choices: [.init(id: "all", title: "全部结果")] + [GameResult.won, .lost, .abandoned].map { .init(id: $0.rawValue, title: $0.title) })
                        ClassicDropdown(title: "日期筛选", selection: Binding(get: { filter.range.rawValue }, set: { filter.range = HistoryRange(rawValue: $0) ?? .all }), choices: HistoryRange.allCases.map { .init(id: $0.rawValue, title: $0.title) })
                    }
                    HStack(spacing: 8) {
                        ClassicDropdown(title: "排序", selection: Binding(get: { filter.order.rawValue }, set: { filter.order = HistoryOrder(rawValue: $0) ?? .newest }), choices: HistoryOrder.allCases.map { .init(id: $0.rawValue, title: $0.title) })
                        Button("重置筛选") { filter = HistoryFilter() }.buttonStyle(ClassicButtonStyle()).frame(maxWidth: .infinity).disabled(filter.isDefault)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: compact ? 2 : 4), spacing: 8) {
                    metric("总局数", String(statistics.count))
                    metric("获胜", String(statistics.wins))
                    metric("胜率", statistics.completed == 0 ? "—" : "\(Int((statistics.winRate * 100).rounded()))%")
                    metric("最佳用时", statistics.best.map { GameDuration.text($0) } ?? "—")
                }
                if records.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 24, weight: .light))
                        Text(game.history.isEmpty ? "暂无记录" : "没有符合条件的记录")
                        if !game.history.isEmpty { Text("试试调整或重置筛选").font(AppTypography.rounded(11)) }
                    }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity, maxHeight: .infinity).classicPanel(inset: true)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(records) { record in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(record.endedAt, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(Palette.muted)
                                        Spacer(minLength: 4)
                                        Text(record.result.title).foregroundStyle(record.result == .won ? Palette.success : record.result == .lost ? Palette.danger : Palette.muted)
                                    }
                                    HStack {
                                        Text("\(record.difficulty.classicTitle) · \(record.gameMode.title)")
                                        Spacer()
                                        Text(GameDuration.text(record.seconds)).monospacedDigit()
                                    }
                                }.padding(10)
                                Divider()
                            }
                        }
                    }.classicScrollbars().background(Palette.paper.opacity(0.8)).classicPanel(inset: true)
                }
                HStack {
                    Text("显示 \(records.count) / \(game.history.count) 局").foregroundStyle(Palette.muted)
                    Spacer()
                    Button("清空记录") { confirmReset = true }.buttonStyle(ClassicButtonStyle()).disabled(game.history.isEmpty)
                }
            }.padding(14).disabled(confirmReset).accessibilityHidden(confirmReset)
        }
        .font(AppTypography.rounded(12)).foregroundStyle(Palette.ink)
        .overlay {
            if confirmReset {
                ZStack {
                    Color.black.opacity(0.20).contentShape(.rect).onTapGesture { }
                    VStack(alignment: .leading, spacing: 10) {
                        ClassicDialogHeader(title: "清空记录？", close: { confirmReset = false })
                        Text("将清空所有难度的记录和最佳用时，无法恢复").fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("取消") { confirmReset = false }.buttonStyle(ClassicButtonStyle()).keyboardShortcut(.cancelAction)
                            Button("确认清空", role: .destructive) { game.resetRecords(); confirmReset = false }.buttonStyle(ClassicButtonStyle())
                        }
                    }.padding(14).frame(maxWidth: 280).classicDialogSurface().padding(14)
                }
            }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).font(AppTypography.rounded(10)).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
            Text(value).font(AppTypography.rounded(17, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(8).classicPanel()
    }
}
