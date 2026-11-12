import SwiftUI
import ProZipCore
import ProZipShared

struct WorkspaceFlowButton: View {
    let recommendation: FlowActionRecommendation
    let selection: [ArchiveEntry]
    @ObservedObject var session: ArchiveBrowsingSession
    var compact: Bool = false
    let primaryAction: () -> Void
    @EnvironmentObject private var appViewModel: ProZipAppViewModel
    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?

    private var hasAlternative: Bool {
        recommendation.actionID == .openFile && selection.count == 1 && !selection[0].isDirectory
    }

    private var primaryMinSize: CGSize {
        compact ? CGSize(width: 112, height: 33) : CGSize(width: 120, height: 40)
    }

    private var secondaryMinSize: CGSize {
        compact ? CGSize(width: 108, height: 32) : CGSize(width: 116, height: 38)
    }

    private var peekSize: CGSize {
        compact ? CGSize(width: 98, height: 33) : CGSize(width: 106, height: 40)
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
        .onChange(of: session.selectedEntryIDs) { _, _ in
            collapseTask?.cancel()
            setExpanded(false)
        }
        .onDisappear { collapseTask?.cancel() }
    }

    private var controls: some View {
        ZStack(alignment: .bottom) {
            if hasAlternative && !isExpanded {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(ProZipTheme.accent.opacity(0.52))
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), Color.white.opacity(0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.9
                        )
                }
                .frame(width: peekSize.width, height: peekSize.height)
                .offset(y: compact ? -5.0 : -5.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            VStack(spacing: compact ? 6 : 8) {
                if hasAlternative && isExpanded {
                    ProZipFlowOrbitButton(title: "解压", icon: "bolt.fill", shortcut: nil, minimumSize: secondaryMinSize) {
                        collapseTask?.cancel()
                        setExpanded(false)
                        appViewModel.extractSelection(selection, in: session)
                    }
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                }
                ProZipFlowOrbitButton(title: recommendation.title, icon: "bolt.fill", shortcut: nil, isEnabled: recommendation.isEnabled, minimumSize: primaryMinSize) {
                    collapseTask?.cancel()
                    setExpanded(false)
                    primaryAction()
                }
                .help(hasAlternative ? "另有 1 个备选 Flow" : recommendation.unavailableReason ?? recommendation.title)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flow")
        .onHover { hovering in
            collapseTask?.cancel()
            if hovering {
                setExpanded(hasAlternative)
            } else {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    setExpanded(false)
                }
            }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { isExpanded = expanded }
    }
}
