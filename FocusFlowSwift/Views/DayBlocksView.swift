import SwiftUI
import SwiftData

// MARK: - Main View

struct DayBlocksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayBlock.date, order: .reverse) private var allBlocks: [DayBlock]

    @State private var filterDays: Int = 30
    @State private var blockForEnemyPick: DayBlock? = nil

    private var filterStart: Date {
        guard filterDays > 0 else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -filterDays, to: Date().startOfDay)!
    }

    private var filteredMetrics: BattleMetrics {
        let relevant = filterDays == 0 ? allBlocks : allBlocks.filter { $0.date >= filterStart }
        return BattleMetrics.compute(from: relevant)
    }

    // Groups blocks by day, sorted newest-first. O(n) dict grouping is fast for this dataset.
    private var groupedDays: [(date: Date, blocks: [DayBlock])] {
        let grouped = Dictionary(grouping: allBlocks, by: \.date)
        return grouped.keys
            .sorted(by: >)
            .map { date in
                (date: date, blocks: grouped[date]!.sorted { $0.blockType.sortOrder < $1.blockType.sortOrder })
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                BattleMetricsBanner(metrics: filteredMetrics, filterDays: $filterDays)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Divider().padding(.horizontal)

                ForEach(groupedDays, id: \.date) { group in
                    DayCard(date: group.date, blocks: group.blocks) { block in
                        blockForEnemyPick = block
                    }
                    .padding(.horizontal)
                }

                Color.clear.frame(height: 40)
            }
        }
        .navigationTitle("Battles")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $blockForEnemyPick) { block in
            EnemyPickerSheet(block: block) { enemy in
                block.controllerRaw = BlockController.enemy.rawValue
                block.enemyTypeRaw = enemy.rawValue
                try? modelContext.save()
            }
        }
        .onAppear { ensureTodayBlocks() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            ensureTodayBlocks()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            ensureTodayBlocks()
        }
    }

    private func ensureTodayBlocks() {
        let today = Date().startOfDay
        let descriptor = FetchDescriptor<DayBlock>(predicate: #Predicate { $0.date == today })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingTypes = Set(existing.map { $0.blockTypeRaw })
        var inserted = false
        for blockType in DayBlockType.allCases where !existingTypes.contains(blockType.rawValue) {
            modelContext.insert(DayBlock(date: today, blockType: blockType))
            inserted = true
        }
        if inserted { try? modelContext.save() }
    }
}

// MARK: - Metrics Banner

struct BattleMetricsBanner: View {
    let metrics: BattleMetrics
    @Binding var filterDays: Int

    private let presets: [(label: String, days: Int)] = [
        ("7d", 7), ("30d", 30), ("90d", 90), ("All", 0)
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.days) { preset in
                    Button { filterDays = preset.days } label: {
                        Text(preset.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(filterDays == preset.days ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(filterDays == preset.days ? Color.blue : Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if metrics.decided > 0 {
                    Text("\(metrics.decided + metrics.unset) blocks tracked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                BattleStatCard(value: metrics.wins,   label: "Won",  color: .green,  rate: metrics.winRate)
                BattleStatCard(value: metrics.ties,   label: "Tied", color: .orange, rate: metrics.tieRate)
                BattleStatCard(value: metrics.losses, label: "Lost", color: .red,    rate: metrics.lossRate)
            }

            if metrics.decided > 0 {
                BattleProgressBar(metrics: metrics)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}

struct BattleStatCard: View {
    let value: Int
    let label: String
    let color: Color
    let rate: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
            Text(rate > 0 ? String(format: "%.0f%%", rate * 100) : "—")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(color.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.08)))
    }
}

struct BattleProgressBar: View {
    let metrics: BattleMetrics

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let winW  = w * Double(metrics.wins)   / Double(metrics.decided)
            let tieW  = w * Double(metrics.ties)   / Double(metrics.decided)
            let lossW = max(w - winW - tieW, 0)

            HStack(spacing: 2) {
                if winW  > 2 { RoundedRectangle(cornerRadius: 3).fill(Color.green) .frame(width: winW) }
                if tieW  > 2 { RoundedRectangle(cornerRadius: 3).fill(Color.orange).frame(width: tieW) }
                if lossW > 2 { RoundedRectangle(cornerRadius: 3).fill(Color.red)   .frame(width: lossW) }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

// MARK: - Day Card

struct DayCard: View {
    let date: Date
    let blocks: [DayBlock]
    let onEnemyTap: (DayBlock) -> Void

    private var dayMetrics: BattleMetrics { BattleMetrics.compute(from: blocks) }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            Divider()
            blockList
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(date.isToday ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.3), lineWidth: date.isToday ? 1.5 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private var dayHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if date.isToday {
                        Text("TODAY")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue))
                    }
                    Text(date.weekdayName)
                        .font(.subheadline).fontWeight(.semibold)
                }
                Text(date.monthDayYearDisplay)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                if dayMetrics.wins   > 0 { DayMiniPill(count: dayMetrics.wins,   color: .green)  }
                if dayMetrics.ties   > 0 { DayMiniPill(count: dayMetrics.ties,   color: .orange) }
                if dayMetrics.losses > 0 { DayMiniPill(count: dayMetrics.losses, color: .red)    }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(date.isToday ? Color.blue.opacity(0.07) : Color(.secondarySystemBackground))
    }

    private var blockList: some View {
        VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                BlockRow(block: block) { onEnemyTap(block) }
                if idx < blocks.count - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

struct DayMiniPill: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Block Row

struct BlockRow: View {
    let block: DayBlock
    let onEnemyTap: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: block.blockType.icon)
                .font(.callout)
                .foregroundColor(block.blockType.blockColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(block.blockType.displayName)
                    .font(.subheadline).fontWeight(.medium)
                Text(block.blockType.timeRange)
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                BlockControlBtn(label: "Me", color: .green, isSelected: block.controller == .me) {
                    toggleController(.me)
                }
                BlockControlBtn(label: "Tie", color: .orange, isSelected: block.controller == .tie) {
                    toggleController(.tie)
                }
                EnemyControlBtn(isSelected: block.controller == .enemy, enemyType: block.enemyType, onTap: onEnemyTap)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func toggleController(_ c: BlockController) {
        block.controllerRaw = (block.controller == c) ? BlockController.unset.rawValue : c.rawValue
        block.enemyTypeRaw = nil
        try? modelContext.save()
    }
}

struct BlockControlBtn: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? color : color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct EnemyControlBtn: View {
    let isSelected: Bool
    let enemyType: EnemyType?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if isSelected, let enemy = enemyType {
                    Text(enemy.emoji).font(.caption)
                } else {
                    Image(systemName: "bolt.fill").font(.caption)
                }
                Text(isSelected ? (enemyType?.displayName ?? "Enemy") : "Enemy")
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .red)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.red : Color.red.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enemy Picker Sheet

struct EnemyPickerSheet: View {
    let block: DayBlock
    let onSelect: (EnemyType) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Which enemy controlled this block?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(EnemyType.allCases) { enemy in
                            EnemyCard(enemy: enemy, isSelected: block.enemyType == enemy) {
                                onSelect(enemy)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Pick Your Enemy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct EnemyCard: View {
    let enemy: EnemyType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(enemy.emoji).font(.title2)
                Text(enemy.displayName)
                    .font(.caption).fontWeight(.semibold)
                Text(enemy.tagline)
                    .font(.caption2).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? enemy.enemyColor.opacity(0.18) : Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? enemy.enemyColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
