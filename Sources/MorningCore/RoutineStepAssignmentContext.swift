import Foundation

/// A volatile UI edit pin, never imported authority or a persisted operation.
public struct RoutineStepAssignmentContext: Equatable, Sendable {
    public let routineVersionID: UUID
    public let stepID: UUID
    public let privacyGeneration: UUID
    public init(routineVersionID: UUID, stepID: UUID, privacyGeneration: UUID) {
        self.routineVersionID = routineVersionID; self.stepID = stepID; self.privacyGeneration = privacyGeneration
    }
    public func validate(routine: RoutineVersion?, generation: UUID) throws {
        guard let routine, routine.id == routineVersionID, generation == privacyGeneration,
              routine.steps.filter({ $0.id == stepID }).count == 1 else { throw AssignmentError.changed }
    }
    public func assigning(_ target: RoutineStepTarget, to edited: RoutineStep,
                          routine: RoutineVersion?, generation: UUID, sourceLabel: RoutineStepSourceLabel? = nil) throws -> RoutineStep {
        try validate(routine: routine, generation: generation)
        guard edited.id == stepID else { throw AssignmentError.changed }
        try target.validateIntegration()
        var result = edited
        result.target = target; result.automation = nil; result.webBehavior = nil; result.webLikesAllowed = nil
        result.sourceLabel = sourceLabel
        return result
    }
    public func replacing(_ edited: RoutineStep, in routine: RoutineVersion?, generation: UUID) throws -> [RoutineStep] {
        try validate(routine: routine, generation: generation)
        guard edited.id == stepID, var steps = routine?.steps,
              let index = steps.firstIndex(where: { $0.id == stepID }) else { throw AssignmentError.changed }
        steps[index] = edited
        return steps
    }
    public enum AssignmentError: LocalizedError {
        case changed
        public var errorDescription: String? {
            AppLanguage.isFrench ? "Ce moment ou votre routine a changé. Fermez l’éditeur et choisissez à nouveau. Rien n’a été ajouté."
                : "This moment or your routine changed. Close the editor and choose again. Nothing was added."
        }
    }
}
