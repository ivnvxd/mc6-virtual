/// The words for Dry Run, Live and Error in the window, so a new user sees whether MIDI goes out.
public enum ModeText {
    /// The mode next to the activity light in compact mode, in the panel's print style.
    public static func label(_ mode: Session.Mode) -> String {
        switch mode {
        case .dryRun: "DRY RUN"
        case .live: "LIVE"
        case .error: "ERROR"
        }
    }

    /// The tooltip of the Arm buttons. V22: Arm is a power-on.
    public static let armHelp = "Go Live. The app starts again at bank 1, page 1, with every preset at Position 1, "
        + "and sends the On Enter Bank messages of bank 1."

    /// The Sent strip header (V12). `total` counts the whole group, also outputs that the strip leaves out.
    /// A group of only Dry Run outputs says that nothing reached the ports.
    public static func sentHeader(_ outputs: [LogEntry], total: Int) -> String {
        guard total > 0 else { return "Sent" }
        let dry = outputs.allSatisfy {
            if case .output(_, _, _, let live) = $0.event { !live } else { true }
        }
        return dry ? "Dry Run: \(total) message\(total == 1 ? "" : "s"), nothing went to the MIDI ports" : "Sent (\(total))"
    }

    /// The fault banner: where the press stopped, why, and that the receiving app may have part of it.
    public static func fault(_ fault: EngineFault, in backup: Backup?) -> String {
        let why = switch fault {
        case .depthLimit: "this Engage goes deeper than \(Engine.maxDepth) nested presets."
        case .budgetLimit: "one press ran more than \(Engine.maxMessagesPerTrigger) messages."
        case .sendFailed(_, let reason): "the message could not be sent: \(reason)."
        }
        return "Stopped at \(ImportText.place(of: fault.pointer, in: backup)): \(why) Messages sent before it cannot be taken back."
    }
}
