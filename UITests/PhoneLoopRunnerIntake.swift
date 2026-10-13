import Foundation
import MorningCore

/// The runner's first step for a command of the tethered phone loop (#7): read it off the wire
/// with the shared types and ask the shared gate whether it may be carried out.
///
/// This proves that the UI-test target links MorningCore. Nothing calls it yet and no
/// XCUIApplication action is wired to it: the runner that acts on an admitted command is
/// separate work, and it stays in this target.
enum PhoneLoopRunnerIntake {
    enum Decision {
        /// The command may be carried out, once.
        case admitted(PhoneCommandMessage)
        /// The gate refused it; the reason is one the runner may report in its answer.
        case refused(PhoneCommandMessage, PhoneRunnerRefusal)
    }

    /// Throws if the bytes are not a command of a wire version this build reads.
    static func decide(_ data: Data, gate: inout PhoneCommandGate) throws -> Decision {
        let command = try JSONDecoder().decode(PhoneCommandMessage.self, from: data)
        if let refusal = gate.admit(command) { return .refused(command, PhoneRunnerRefusal(refusal)) }
        return .admitted(command)
    }
}
