import SwiftUI
import Charts

/// Insights: what the activity log actually adds up to.
///
/// New in 2.0. 1.x recorded sessions and never showed them anywhere, so the
/// data existed purely to be forgotten.
struct StatsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: Catalog

    @State private var showingActivity = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if library.activity.isEmpty {
                        EmptyNotice(systemImage: "chart.bar",
                                    title: "Nothing to chart yet",
                                    message: "Play a game for more than fifteen seconds and it "
                                        + "will start showing up here.")
                    } else {
                        totals
                        weekChart
                        performanceChart
                        topGames
                        if let longest = library.longestSession {
                            longestCard(longest)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 36)
                // The page is exactly as wide as the screen, whatever a
                // child would prefer. Without this one greedy row drags
                // every other row off the right edge with it.
                .containerRelativeFrame(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AuroraBackground() }
            .navigationTitle("Insights")
            .toolbar {
                if !library.activity.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingActivity = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("All sessions")
                    }
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .sheet(isPresented: $showingActivity) { ActivityView() }
        }
    }

    private var totals: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatChip(value: Format.duration(library.totalPlaytime),
                         caption: "Total playtime", systemImage: "hourglass")
                StatChip(value: Format.duration(library.playtimeThisWeek),
                         caption: "Last 7 days", systemImage: "calendar")
            }
            HStack(spacing: 12) {
                StatChip(value: "\(library.activity.count)",
                         caption: "Sessions", systemImage: "play.rectangle.fill")
                StatChip(value: "\(library.streakDays)",
                         caption: "Day streak", systemImage: "flame.fill")
            }
        }
        .padding(.horizontal, Theme.pageInset)
    }

    /// How recent sessions actually ran.
    ///
    /// Playtime says what was played; this says whether it was worth playing.
    /// A run of sessions at 90 ms is a connection problem the player can act
    /// on, and it is invisible in any total.
    @ViewBuilder
    private var performanceChart: some View {
        let measured = library.activity.filter(\.hasPerformance).prefix(20).reversed()
        if measured.count >= 2 {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Stream quality")
                    Text("Average frame rate and latency across your last "
                         + "\(measured.count) measured sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart(Array(measured)) { record in
                        LineMark(
                            x: .value("Session", record.startedAt),
                            y: .value("Frames per second", record.averageFPS)
                        )
                        .foregroundStyle(by: .value("Measure", "FPS"))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Session", record.startedAt),
                            y: .value("Latency", record.averageLatencyMs)
                        )
                        .foregroundStyle(by: .value("Measure", "Latency (ms)"))
                        .interpolationMethod(.monotone)
                    }
                    .chartLegend(position: .bottom, spacing: 8)
                    .frame(height: 170)

                    HStack(spacing: 10) {
                        StatChip(value: "\(averageOf(measured, \.averageFPS))",
                                 caption: "Average FPS", systemImage: "speedometer")
                        StatChip(value: "\(averageOf(measured, \.averageLatencyMs)) ms",
                                 caption: "Average latency", systemImage: "timer")
                    }
                }
            }
            .padding(.horizontal, Theme.pageInset)
        }
    }

    private func averageOf(_ records: some Collection<PlayRecord>,
                           _ path: KeyPath<PlayRecord, Int>) -> Int {
        guard !records.isEmpty else { return 0 }
        return records.reduce(0) { $0 + $1[keyPath: path] } / records.count
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "This week", subtitle: "Minutes played per day")
            Chart(library.dailyTotals(days: 7)) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Minutes", day.seconds / 60)
                )
                .foregroundStyle(.tint)
                .cornerRadius(7)
            }
            .chartXAxis {
                // Plotted against the date, labelled with the initial.
                // Plotting *by* the initial merged Tuesday into Thursday and
                // Saturday into Sunday, so a week showed five bars.
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(DayTotal(day: date, seconds: 0).weekdayInitial)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 170)
        }
        .padding(18)
        .glassEffect(.regular, in: Theme.cardShape)
        .padding(.horizontal, Theme.pageInset)
    }

    private var topGames: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Most played")

            VStack(spacing: 14) {
                ForEach(Array(library.topGames(limit: 5).enumerated()), id: \.element.id) { index, total in
                    HStack(spacing: 13) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        if let game = resolve(total) {
                            NavigationLink(value: game) {
                                row(total, game: game)
                            }
                            .buttonStyle(.plain)
                        } else {
                            row(total, game: nil)
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: Theme.cardShape)
        .padding(.horizontal, Theme.pageInset)
    }

    private func row(_ total: GameTotal, game: Game?) -> some View {
        HStack(spacing: 12) {
            GameArtwork(url: game?.posterURL, cornerRadius: 8)
                .frame(width: 38, height: 51)
            VStack(alignment: .leading, spacing: 3) {
                Text(total.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(total.sessions) session\(total.sessions == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(Format.duration(total.seconds))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
        }
    }

    private func longestCard(_ record: PlayRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Longest session").font(.headline)
            Text(record.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
            Text("\(Format.duration(record.seconds)) on "
                 + record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: Theme.cardShape)
        .padding(.horizontal, Theme.pageInset)
    }

    private func resolve(_ total: GameTotal) -> Game? {
        catalog.game(id: total.gameID)
            ?? library.recents.first { $0.matches(id: total.gameID) }
            ?? library.favorites.first { $0.matches(id: total.gameID) }
    }
}
