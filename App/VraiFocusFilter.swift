import AppIntents
import VraiUI

struct VraiFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Vrai notifications"
    static let description: IntentDescription? = IntentDescription("Choose which Vrai notifications reach you during this Focus.")

    @Parameter(title: "Only failures and requests", default: false)
    var alertsOnly: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: alertsOnly ? "Only failures and requests" : "Everything")
    }

    func perform() async throws -> some IntentResult {
        NotificationFocus.alertsOnly = alertsOnly
        return .result()
    }
}
