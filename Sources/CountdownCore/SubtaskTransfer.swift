import Foundation

public enum SubtaskTransferError: LocalizedError {
    case completedSubtask, sameEvent, destinationChanged, destinationRequired, destinationContainsSubtask

    public var errorDescription: String? {
        switch self {
        case .completedSubtask: return AppText.string("transfer.error.completed")
        case .sameEvent: return AppText.string("transfer.error.sameEvent")
        case .destinationChanged: return AppText.string("transfer.error.dateChanged")
        case .destinationRequired: return AppText.string("transfer.error.destinationRequired")
        case .destinationContainsSubtask: return AppText.string("transfer.error.duplicateSubtask")
        }
    }
}

extension CountdownData {
    /// Builds one snapshot so rejection cannot remove a task or leave a partially created destination.
    public mutating func transferSubtask(
        from sourceEventID: UUID,
        subtaskID: UUID,
        to targetEventID: UUID?,
        on targetDay: Day,
        today: Day
    ) throws -> Countdown {
        guard targetDay >= today else { throw CountdownError.date }
        guard let sourceIndex = items.firstIndex(where: { $0.id == sourceEventID && $0.isAvailable(on: today) }) else {
            throw CountdownError.eventNotFound
        }
        guard let subtaskIndex = items[sourceIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw CountdownError.subtaskNotFound
        }
        let subtask = items[sourceIndex].subtasks[subtaskIndex]
        guard !subtask.isCompleted else { throw SubtaskTransferError.completedSubtask }
        var updated = self
        let destination: Countdown
        if let targetEventID {
            guard targetEventID != sourceEventID else { throw SubtaskTransferError.sameEvent }
            guard let targetIndex = items.firstIndex(where: { $0.id == targetEventID && $0.isAvailable(on: today) }) else {
                throw CountdownError.eventNotFound
            }
            guard items[targetIndex].date == targetDay else { throw SubtaskTransferError.destinationChanged }
            guard items[targetIndex].subtasks.count < Subtask.maximumCount else { throw CountdownError.subtaskCount }
            guard !items[targetIndex].subtasks.contains(where: { $0.id == subtaskID }) else {
                throw SubtaskTransferError.destinationContainsSubtask
            }
            updated.items[targetIndex].subtasks.append(subtask)
            destination = updated.items[targetIndex]
        } else {
            guard !containsEvent(on: targetDay) else { throw SubtaskTransferError.destinationRequired }
            let day = Countdown(title: automaticEventTitle(for: targetDay), date: targetDay, emoji: "",
                                subtasks: [subtask], showsWeather: true, usesAutomaticTitle: true, isDay: true)
            updated.items.append(day)
            destination = day
        }
        updated.items[sourceIndex].subtasks.remove(at: subtaskIndex)
        updated.normalize(today: today)
        self = updated
        return destination
    }
}
