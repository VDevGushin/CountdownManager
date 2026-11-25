import AppKit
import CountdownCore
import SwiftUI

let subtaskLiftOutset: CGFloat = 6

/// Stable row positions used for hit testing. The moving row's visual offset never feeds back into measurement.
package func subtaskRowFrames(_ tasks: [Subtask], sizes: [UUID: CGSize], spacing: CGFloat) -> [UUID: CGRect] {
    var top: CGFloat = 0
    var frames: [UUID: CGRect] = [:]
    for task in tasks {
        guard let size = sizes[task.id], size.height > 0 else { return [:] }
        frames[task.id] = CGRect(origin: CGPoint(x: 0, y: top), size: size)
        top += size.height + spacing
    }
    return frames
}

package func subtaskDropIndex(
    move: SubtaskReorder, displayed: [Subtask], frames: [UUID: CGRect], pointer: CGPoint
) -> Int? {
    let group = displayed.filter { $0.isCompleted == move.group[move.originalIndex].isCompleted }
    guard let first = group.first.flatMap({ frames[$0.id] }),
          let last = group.last.flatMap({ frames[$0.id] }),
          first.union(last).contains(pointer) else { return nil }
    return group.filter { task in
        task.id != move.subtaskID && (frames[task.id]?.midY ?? .infinity) <= pointer.y
    }.count
}

package func subtaskLiftOffset(_ verticalTranslation: CGFloat, origin: CGRect, groupBounds: CGRect) -> CGFloat {
    min(max(verticalTranslation, groupBounds.minY - origin.minY), groupBounds.maxY - origin.maxY)
}

private struct SubtaskRowSizes: PreferenceKey {
    static let defaultValue: [UUID: CGSize] = [:]

    static func reduce(value: inout [UUID: CGSize], nextValue: () -> [UUID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct SubtaskReorderInteraction: ViewModifier {
    static let disabled = SubtaskReorderInteraction(drag: nil, moveUp: nil, moveDown: nil)

    let drag: AnyGesture<DragGesture.Value>?
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    func body(content: Content) -> some View {
        // Rows without a drag still need the native checkbox's own click gesture.
        content.highPriorityGesture(drag, including: drag == nil ? .subviews : .all)
            .accessibilityActions {
                if let moveUp { Button(AppText.string("subtask.reorderUp"), action: moveUp) }
                if let moveDown { Button(AppText.string("subtask.reorderDown"), action: moveDown) }
            }
    }
}

struct SubtaskReorderRows<Row: View>: View {
    private struct Drag {
        let move: SubtaskReorder
        let origin: CGRect
        let groupBounds: CGRect
        var translationY: CGFloat = 0
        var destination: Int
        var settling = false
    }

    let subtasks: [Subtask]
    let spacing: CGFloat
    let isEnabled: Bool
    let save: (SubtaskReorder, Int) async -> Bool
    @ViewBuilder let row: (Subtask, SubtaskReorderInteraction?) -> Row

    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var gestureIsActive = false
    @State private var coordinateSpace = UUID()
    @State private var sizes: [UUID: CGSize] = [:]
    @State private var drag: Drag?
    @State private var cancelledGesture = false

    private var motion: Animation? {
        accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.15)
    }

    var body: some View {
        let original = checklistDisplayOrder(drag?.move.original ?? subtasks)
        let preview = checklistDisplayOrder(drag.flatMap { $0.move.reordered(to: $0.destination) } ?? subtasks)
        let frames = subtaskRowFrames(original, sizes: sizes, spacing: spacing)
        let proposedFrames = subtaskRowFrames(preview, sizes: sizes, spacing: spacing)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(original) { task in
                positionedRow(task, frames: frames, proposedFrames: proposedFrames)
            }
        }
        .coordinateSpace(name: coordinateSpace)
        .onPreferenceChange(SubtaskRowSizes.self) { sizes = $0 }
        .onChange(of: gestureIsActive) { active in
            if !active {
                cancelDrag()
                cancelledGesture = false
            }
        }
        .onChange(of: isEnabled) { enabled in
            if !enabled { cancelDrag() }
        }
        .onChange(of: subtasks) { _ in cancelDrag() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            cancelDrag()
        }
        .onExitCommand(perform: drag?.settling == false ? cancelDrag : nil)
    }

    private func positionedRow(_ task: Subtask, frames: [UUID: CGRect], proposedFrames: [UUID: CGRect]) -> some View {
        let moving = drag?.move.subtaskID == task.id
        let offset = rowOffset(task.id, original: frames, preview: proposedFrames)
        return row(task, interaction(for: task, frames: frames))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SubtaskRowSizes.self, value: [task.id: proxy.size])
                }
            }
            .background {
                if moving {
                    RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                        .fill(AuroraInstrument.surface(
                            for: colorScheme, elevated: false, highContrast: accessibilitySettings.prefersHighContrast
                        ))
                        .overlay {
                            RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                                .fill(AuroraInstrument.ink(for: colorScheme).opacity(
                                    accessibilitySettings.prefersHighContrast ? 0.10 : 0.035
                                ))
                        }
                        .padding(.leading, -subtaskLiftOutset)
                        // The visible transfer symbol sits about eight points inside its hit target.
                        .padding(.trailing, task.isCompleted ? -subtaskLiftOutset : 2)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: offset)
            .animation(moving && drag?.settling == false ? nil : motion, value: offset)
            .zIndex(moving ? 1 : 0)
    }

    private func rowOffset(_ id: UUID, original: [UUID: CGRect], preview: [UUID: CGRect]) -> CGFloat {
        if let drag, drag.move.subtaskID == id { return drag.translationY }
        guard let before = original[id], let after = preview[id] else { return 0 }
        return after.minY - before.minY
    }

    private func interaction(for task: Subtask, frames: [UUID: CGRect]) -> SubtaskReorderInteraction? {
        guard isEnabled || drag?.move.subtaskID == task.id,
              let move = SubtaskReorder(subtasks: subtasks, subtaskID: task.id), move.group.count > 1 else { return nil }
        let gesture = DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateSpace))
            .updating($gestureIsActive) { _, active, _ in active = true }
            .onChanged { updateDrag($0, move: move, frames: frames) }
            .onEnded(finishDrag)
        return SubtaskReorderInteraction(
            drag: AnyGesture(gesture),
            moveUp: keyboardAction(move, to: move.originalIndex - 1),
            moveDown: keyboardAction(move, to: move.originalIndex + 1)
        )
    }

    private func keyboardAction(_ move: SubtaskReorder, to index: Int) -> (() -> Void)? {
        guard isEnabled, drag == nil, move.group.indices.contains(index) else { return nil }
        return { Task { _ = await save(move, index) } }
    }

    private func updateDrag(_ value: DragGesture.Value, move: SubtaskReorder, frames: [UUID: CGRect]) {
        guard !cancelledGesture, drag?.settling != true else { return }
        if drag == nil, isEnabled,
           let origin = frames[move.subtaskID],
           let first = move.group.first.flatMap({ frames[$0.id] }),
           let last = move.group.last.flatMap({ frames[$0.id] }) {
            drag = Drag(move: move, origin: origin, groupBounds: first.union(last), destination: move.originalIndex)
        }
        guard var current = drag, current.move.subtaskID == move.subtaskID else { return }
        current.translationY = subtaskLiftOffset(value.translation.height, origin: current.origin, groupBounds: current.groupBounds)
        if let index = dropIndex(value, drag: current) { current.destination = index }
        drag = current
    }

    private func dropIndex(_ value: DragGesture.Value, drag: Drag) -> Int? {
        guard let preview = drag.move.reordered(to: drag.destination) else { return nil }
        let ordered = checklistDisplayOrder(preview)
        return subtaskDropIndex(move: drag.move, displayed: ordered,
                                frames: subtaskRowFrames(ordered, sizes: sizes, spacing: spacing),
                                pointer: value.location)
    }

    private func finishDrag(_ value: DragGesture.Value) {
        defer { cancelledGesture = false }
        guard var current = drag, !current.settling else { return }
        guard isEnabled, let index = dropIndex(value, drag: current), index != current.move.originalIndex,
              let tasks = current.move.reordered(to: index),
              let target = subtaskRowFrames(checklistDisplayOrder(tasks), sizes: sizes, spacing: spacing)[current.move.subtaskID] else {
            cancelDrag()
            return
        }
        current.destination = index
        current.settling = true
        current.translationY = target.minY - current.origin.minY
        drag = current
        Task {
            let saved = await save(current.move, index)
            if saved, motion != nil { try? await Task.sleep(nanoseconds: 150_000_000) }
            var transaction = Transaction(animation: saved ? nil : motion)
            transaction.disablesAnimations = saved
            withTransaction(transaction) { drag = nil }
        }
    }

    private func cancelDrag() {
        guard drag?.settling == false else { return }
        cancelledGesture = gestureIsActive
        withAnimation(motion) { drag = nil }
    }
}
