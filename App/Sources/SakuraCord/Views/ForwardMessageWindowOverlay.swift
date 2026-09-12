import SwiftUI

/// Presents Forward through the shared window modal lifecycle.
struct ForwardMessageWindowOverlay: View {
    let model: AppModel

    var body: some View {
        WindowModalOverlay(
            presentation: model.forwardingMessage,
            dismiss: model.dismissForwarding
        ) { message, animationState in
            ForwardMessageOverlay(
                model: model,
                message: message,
                animationState: animationState,
                dismiss: {
                    animationState.dismiss(committingPresentation: true)
                }
            )
        }
        // Destination discovery depends only on already-loaded local stores.
        // Warm its revisioned index after workspace changes settle so the first
        // explicit Forward action normally attaches an immediately populated
        // picker instead of starting permission and fuzzy-index work on open.
        .task(id: model.forwardSearchSourceRevision) {
            guard model.snapshot != nil else { return }
            ForwardDestinationSearchIndexCache.shared.schedulePrewarm(
                for: model
            )
        }
    }
}
