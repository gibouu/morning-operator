import Foundation
import MorningCore

/// The remote model proposes the same values as the local model. Citation and
/// preference validation remains in LearningBatchRunner and the app-owned assembler.
enum OpenAIRoutineSchema {
    static func make(citationIDs: [String]? = nil) -> ComposioJSONValue {
        func string(_ values: [String]? = nil, description: String? = nil) -> ComposioJSONValue {
            var properties: [String: ComposioJSONValue] = ["type": .string("string")]
            if let values { properties["enum"] = .array(values.map { .string($0) }) }
            if let description { properties["description"] = .string(description) }
            return .object(properties)
        }
        func object(_ properties: [String: ComposioJSONValue]) -> ComposioJSONValue {
            .object(["type": .string("object"), "properties": .object(properties),
                     "required": .array(properties.keys.sorted().map { .string($0) }),
                     "additionalProperties": .bool(false)])
        }
        var step: [String: ComposioJSONValue] = [
            "title": string(), "kind": string(StepKind.allCases.map(\.rawValue)),
            "durationMinutes": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(60)])
        ]
        if let citationIDs {
            let abstention = object([
                "outcome": string(["insufficientEvidence"]),
                "steps": .object(["type": .string("array"), "minItems": .number(0), "maxItems": .number(0),
                    "items": string()])
            ])
            if citationIDs.isEmpty {
                return object(["selection": abstention])
            }
            step["citationIDs"] = .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(1),
                "items": string(citationIDs)])
            step["kind"] = string(StepKind.allCases.map(\.rawValue), description: EvidenceRoutineFieldGuidance.kind)
            step["title"] = string(description: EvidenceRoutineFieldGuidance.title)
            step["durationMinutes"] = .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(60),
                "description": .string(EvidenceRoutineFieldGuidance.duration)])
            let supported = object([
                "outcome": string(["supportedActivities"]),
                "steps": .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(4),
                    "items": object(step)])
            ])
            return object(["selection": .object(["anyOf": .array([abstention, supported]),
                "description": .string(EvidenceRoutineFieldGuidance.selection)])])
        } else {
            step["detail"] = string()
            step["evidenceQuote"] = string()
            step["evidenceKind"] = string(["userReportedActivity", "visibleTaskContent"])
        }
        return object([
            "outcome": string(["insufficientEvidence", "supportedActivities"]),
            "steps": .object(["type": .string("array"), "maxItems": .number(4), "items": object(step)])
        ])
    }
}
