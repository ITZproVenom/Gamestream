import SwiftUI

struct GlassTabBar: View {
    @Binding var selected: AppTab
    @Binding var dragOffset: CGFloat

    private var tabCount: CGFloat { CGFloat(AppTab.allCases.count) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let slot = width / tabCount
            let baseX = CGFloat(selected.index) * slot
            let maxLeft = -baseX
            let maxRight = width - slot - baseX
            let clamped = min(max(dragOffset, maxLeft), maxRight)
            let pillX = baseX + clamped

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: Capsule())

                Capsule()
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .frame(width: max(slot - 4, 0), height: 52)
                    .offset(x: pillX + 2)
                    .animation(
                        dragOffset == 0
                            ? .spring(response: 0.32, dampingFraction: 0.82)
                            : .interactiveSpring,
                        value: selected
                    )

                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selected == tab ? .primary : .secondary)
                        .frame(width: slot, height: 52)
                        .contentShape(Rectangle())
                        .onTapGesture { select(tab) }
                    }
                }
            }
            .padding(5)
            .contentShape(Capsule())
            .gesture(drag(slot: slot))
        }
        .frame(height: 62)
    }

    private func select(_ tab: AppTab) {
        guard tab != selected else { return }
        HapticManager.tap()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selected = tab
        }
    }

    private func drag(slot: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                let delta = Int((predicted / max(slot, 1)).rounded())
                let all = AppTab.allCases
                let current = selected.index
                let next = min(max(current + delta, 0), all.count - 1)
                dragOffset = 0
                if next != current {
                    select(all[next])
                }
            }
    }
}
