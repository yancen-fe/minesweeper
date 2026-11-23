import SwiftUI

struct GameResultView: View {
    let completion: GameCompletion
    let close: () -> Void
    let restart: () -> Void
    private var won: Bool { completion.record.result == .won }
    var body: some View {
        VStack(spacing: 8) {
            ClassicDialogHeader(title: won ? "获胜" : "踩雷", close: close)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text(GameDuration.text(completion.record.seconds))
                    .font(AppTypography.rounded(30, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .accessibilityLabel("本局用时 \(GameDuration.text(completion.record.seconds))")
                Text("\(completion.record.difficulty.classicTitle) · \(completion.record.gameMode.title)")
                    .foregroundStyle(Palette.muted)
            }
            if let best = completion.best {
                Text("最佳 \(GameDuration.text(best))").foregroundStyle(Palette.muted).monospacedDigit()
            }
            HStack(spacing: 8) {
                metric("总局数", String(completion.statistics.count))
                metric("获胜", String(completion.statistics.wins))
                metric("胜率", completion.statistics.completed == 0 ? "—" : "\(Int((completion.statistics.winRate * 100).rounded()))%")
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("返回", action: close).buttonStyle(ClassicButtonStyle(height: 32))
                Button("再来一局", action: restart).buttonStyle(ClassicButtonStyle(height: 32))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).font(AppTypography.rounded(13)).foregroundStyle(Palette.ink)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppTypography.rounded(10)).foregroundStyle(Palette.muted)
            Text(value).font(AppTypography.rounded(20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8).classicPanel()
    }
}
