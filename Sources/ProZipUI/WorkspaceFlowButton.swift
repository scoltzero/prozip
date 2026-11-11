import SwiftUI
import ProZipCore
import ProZipShared

struct WorkspaceFlowButton: View {
    let recommendation: FlowActionRecommendation
    let selection: [ArchiveEntry]
    @ObservedObject var session: ArchiveBrowsingSession
    let primaryAction: () -> Void
    @EnvironmentObject private var appViewModel: ProZipAppViewModel
    @State private var isExpanded = false

    private var hasAlternative: Bool {
        recommendation.actionID == .openFile && selection.count == 1 && !selection[0].isDirectory
    }

    var body: some View {
        Group {
            if hasAlternative {
                controls
                    .accessibilityAction(named: Text(isExpanded ? "收起备选 Flow" : "展开备选 Flow")) {
                        setExpanded(!isExpanded)
                    }
            } else { controls }
        }
        .onChange(of: session.selectedEntryIDs) { _, _ in setExpanded(false) }
    }

    private var controls: some View {
        ZStack(alignment: .bottom) {
            if hasAlternative && !isExpanded {
                Capsule()
                    .fill(ProZipTheme.accent.opacity(0.65))
                    .frame(width: 110, height: 40)
                    .offset(y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                if hasAlternative && isExpanded {
                    ProZipFlowOrbitButton(title: "解压", icon: "bolt.fill", shortcut: nil, minimumSize: CGSize(width: 116, height: 40)) {
                        setExpanded(false)
                        appViewModel.extractSelection(selection, in: session)
                    }
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                }
                ProZipFlowOrbitButton(title: recommendation.title, icon: "bolt.fill", shortcut: nil, isEnabled: recommendation.isEnabled, minimumSize: CGSize(width: 116, height: 40)) {
                    setExpanded(false)
                    primaryAction()
                }
                .help(hasAlternative ? "另有 1 个备选 Flow" : recommendation.unavailableReason ?? recommendation.title)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flow")
        .onHover { setExpanded(hasAlternative && $0) }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { isExpanded = expanded }
    }
}
