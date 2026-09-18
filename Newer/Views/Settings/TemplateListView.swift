import SwiftUI

struct TemplateListView: View {
    let items: [TemplateItem]
    let onUpdate: (TemplateItem) -> Void
    let onSetEnabled: (Bool, TemplateEntry) -> Void
    let onMove: (String, IndexSet, Int) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var isDragging = false
    @State private var expandedDirectories: Set<String> = []
    @State private var drag: TemplateDragState?
    @State private var dragCancelled = false
    @State private var rowFrames: [TemplateEntry.EntryID: CGRect] = [:]

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                TemplateHierarchyRows(
                    entries: displayedHierarchy,
                    expandedDirectories: expandedDirectories,
                    row: hierarchyRow
                )
                .animation(
                    .smooth(duration: 0.18),
                    value: displayedHierarchy.flatMap(\.flattenedEntryIDs)
                )

                draggedRow
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onPreferenceChange(TemplateRowFramePreferenceKey.self) { rowFrames = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "settings.templates.empty.title",
                    systemImage: "doc.badge.plus"
                )
            }
        }
        .onChange(of: isDragging) { _, active in
            if !active {
                if drag?.isSettling == false {
                    cancelDrag()
                }
                dragCancelled = false
            }
        }
        .onChange(of: items.map(\.relativePath)) { _, _ in
            guard let drag, !drag.isSettling else { return }
            if siblingEntries(within: drag.parentRelativePath).map(\.id) != drag.initialEntries.map(\.id) {
                cancelDrag()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelDrag()
            }
        }
        .onExitCommand(perform: cancelDrag)
        .onDisappear(perform: cancelDrag)
    }

    private static let fileRowHeight: CGFloat = 54
    private static let directoryRowHeight: CGFloat = 46
    private static let coordinateSpaceName = "template-hierarchy"
}

private extension TemplateListView {
    private var hierarchy: [TemplateEntry] {
        TemplateEntry.make(from: items)
    }

    private var displayedHierarchy: [TemplateEntry] {
        guard let drag else { return hierarchy }
        var result = hierarchy
        guard TemplateEntry.replaceEntries(
            in: &result,
            parentRelativePath: drag.parentRelativePath,
            with: drag.displayedEntries
        ) else { return hierarchy }
        return result
    }

    @ViewBuilder
    private var draggedRow: some View {
        if let drag, let frame = drag.rowFrames[drag.entry.id] {
            entryContent(
                drag.entry,
                depth: 0,
                parentRelativePath: drag.parentRelativePath,
                showsIndentation: false,
                isInteractive: false
            )
            .frame(width: frame.width, height: frame.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            .offset(
                x: frame.minX + drag.translation.width,
                y: frame.minY + drag.translation.height
            )
            .allowsHitTesting(false)
            .zIndex(1)
        }
    }

    private func hierarchyRow(
        _ entry: TemplateEntry,
        depth: Int,
        parentRelativePath: String
    ) -> some View {
        entryContent(
            entry,
            depth: depth,
            parentRelativePath: parentRelativePath,
            showsIndentation: true,
            isInteractive: true
        )
        .opacity(drag?.entry.id == entry.id ? 0 : 1)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TemplateRowFramePreferenceKey.self,
                    value: [
                        entry.id: geometry.frame(in: .named(Self.coordinateSpaceName))
                    ]
                )
            }
        }
    }

    @ViewBuilder
    private func entryContent(
        _ entry: TemplateEntry,
        depth: Int,
        parentRelativePath: String,
        showsIndentation: Bool,
        isInteractive: Bool
    ) -> some View {
        switch entry {
        case let .directory(path, name, _):
            directoryRow(
                path: path,
                name: name,
                entry: entry,
                depth: depth,
                parentRelativePath: parentRelativePath,
                showsIndentation: showsIndentation,
                isInteractive: isInteractive
            )
        case let .template(item):
            templateRow(
                item,
                entry: entry,
                depth: depth,
                parentRelativePath: parentRelativePath,
                showsIndentation: showsIndentation
            )
        }
    }

    private func templateRow(
        _ item: TemplateItem,
        entry: TemplateEntry,
        depth: Int,
        parentRelativePath: String,
        showsIndentation: Bool
    ) -> some View {
        TemplateRow(item: item, onUpdate: onUpdate) {
            dragHandle(for: entry, parentRelativePath: parentRelativePath)
        }
        .padding(.leading, leadingPadding(depth: depth, showsIndentation: showsIndentation))
        .padding(.trailing, 10)
        .frame(height: Self.fileRowHeight)
    }

    private func directoryRow(
        path: String,
        name: String,
        entry: TemplateEntry,
        depth: Int,
        parentRelativePath: String,
        showsIndentation: Bool,
        isInteractive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            dragHandle(for: entry, parentRelativePath: parentRelativePath)

            TemplateSelectionCheckbox(
                state: entry.selectionState
            ) {
                onSetEnabled(entry.selectionState != .enabled, entry)
            }
            .frame(width: 20, height: 20)

            Button {
                guard isInteractive else { return }
                withAnimation(.smooth(duration: 0.16)) {
                    if expandedDirectories.contains(path) {
                        expandedDirectories.remove(path)
                    } else {
                        expandedDirectories.insert(path)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expandedDirectories.contains(path)
                        ? "folder.fill"
                        : "folder")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)

                    Text(name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, leadingPadding(depth: depth, showsIndentation: showsIndentation))
        .padding(.trailing, 10)
        .frame(height: Self.directoryRowHeight)
    }
}

private extension TemplateListView {
    private func dragHandle(
        for entry: TemplateEntry,
        parentRelativePath: String
    ) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(width: 22, height: rowHeight(for: entry))
            .contentShape(Rectangle())
            .gesture(dragGesture(for: entry, parentRelativePath: parentRelativePath))
    }

    private func dragGesture(
        for entry: TemplateEntry,
        parentRelativePath: String
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpaceName))
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { value in
                guard !dragCancelled else { return }
                if drag == nil {
                    drag = TemplateDragState(
                        entryID: entry.id,
                        entries: siblingEntries(within: parentRelativePath),
                        parentRelativePath: parentRelativePath,
                        rowFrames: rowFrames
                    )
                }
                guard var current = drag, !current.isSettling,
                      current.entry.id == entry.id,
                      let originFrame = current.rowFrames[entry.id] else { return }
                current.translation = value.translation
                let draggedCenterY = originFrame.midY + value.translation.height
                if let targetID = closestSiblingID(
                    to: draggedCenterY,
                    in: current
                ) {
                    current.updateTarget(entryID: targetID)
                }
                drag = current
            }
            .onEnded { _ in finishDrag() }
    }

    private func closestSiblingID(
        to yPosition: CGFloat,
        in drag: TemplateDragState
    ) -> TemplateEntry.EntryID? {
        drag.initialEntries.compactMap { entry -> (TemplateEntry.EntryID, CGFloat)? in
            guard let frame = drag.rowFrames[entry.id] else { return nil }
            return (entry.id, abs(frame.midY - yPosition))
        }.min { $0.1 < $1.1 }?.0
    }

    private func finishDrag() {
        guard var current = drag, !current.isSettling,
              siblingEntries(within: current.parentRelativePath).map(\.id) == current.initialEntries.map(\.id) else {
            cancelDrag()
            return
        }

        current.isSettling = true
        drag = current
        onMove(current.parentRelativePath, IndexSet(integer: current.originIndex), current.destinationOffset)

        let targetFrame = current.rowFrames[current.initialEntries[current.targetIndex].id]
        let originFrame = current.rowFrames[current.entry.id]
        withAnimation(.smooth(duration: 0.14), completionCriteria: .logicallyComplete) {
            drag?.translation = CGSize(
                width: (targetFrame?.minX ?? 0) - (originFrame?.minX ?? 0),
                height: (targetFrame?.minY ?? 0) - (originFrame?.minY ?? 0)
            )
        } completion: {
            guard drag?.id == current.id else { return }
            cancelDrag()
        }
    }

    private func cancelDrag() {
        dragCancelled = isDragging
        drag = nil
    }

    private func siblingEntries(within parentRelativePath: String) -> [TemplateEntry] {
        TemplateEntry.entries(
            in: hierarchy,
            parentRelativePath: parentRelativePath
        ) ?? []
    }

    private func leadingPadding(depth: Int, showsIndentation: Bool) -> CGFloat {
        showsIndentation ? CGFloat(depth) * 22 + 10 : 10
    }

    private func rowHeight(for entry: TemplateEntry) -> CGFloat {
        switch entry {
        case .directory:
            Self.directoryRowHeight
        case .template:
            Self.fileRowHeight
        }
    }
}
