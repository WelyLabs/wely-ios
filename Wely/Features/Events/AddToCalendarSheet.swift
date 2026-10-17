import EventKit
import EventKitUI
import SwiftUI

/// The system's « new event » editor, filled in with a Wely event. Since iOS 17 it runs out of
/// process and needs no calendar access: the user picks the calendar and adds the event there.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let event: FeedEvent
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = CalendarExport.calendarEvent(event, eventURL: CalendarExport.eventURL(event), store: store)
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ editor: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
