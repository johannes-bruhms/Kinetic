import Foundation

/// Groups related gestures into families for ambiguity resolution and semantic organization.
/// A family defines which gestures are easily confused with each other (confusion set),
/// which families should be suppressed when this one is active, and the preferred
/// recognition lane for disambiguation.
nonisolated struct GestureFamily: Identifiable, Codable, Sendable {
    let id: String
    var name: String

    /// UUIDs of gestures belonging to this family.
    var members: [UUID]

    /// Names of gestures commonly confused with members of this family.
    /// Used by EventFusionEngine to detect ambiguity windows.
    var confusionSet: [String]

    /// Family IDs that should be suppressed when this family is active.
    var suppressesFamilies: [String]

    /// If set, the fusion engine prefers events from this lane for family members.
    var preferredLane: EventLane?

    /// Free-form notes for the performer (e.g., "sharp wrist flick, not arm swing").
    var notes: String

    init(
        id: String = UUID().uuidString,
        name: String,
        members: [UUID] = [],
        confusionSet: [String] = [],
        suppressesFamilies: [String] = [],
        preferredLane: EventLane? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.confusionSet = confusionSet
        self.suppressesFamilies = suppressesFamilies
        self.preferredLane = preferredLane
        self.notes = notes
    }
}
