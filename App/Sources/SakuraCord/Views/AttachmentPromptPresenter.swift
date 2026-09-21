import SwiftUI

struct AttachmentPromptPresenter: View {
    @Bindable var model: AppModel

    var body: some View {
        let prompt = model.oversizedAttachmentPrompt
        let compacting = prompt?.stage == .compaction
        Color.clear
            .frame(width: 0, height: 0)
            .alert(
                compacting ? "Compress This File?" : "File Too Large",
                isPresented: Binding(
                    get: { model.oversizedAttachmentPrompt != nil },
                    set: { presented in
                        if !presented, let prompt {
                            model.dismissOversizedAttachmentPrompt(id: prompt.id)
                        }
                    }
                ),
                presenting: prompt
            ) { prompt in
                if prompt.stage == .compaction {
                    Button("Compress") { model.compactOversizedAttachment(prompt) }
                    Button("Skip", role: .cancel) { model.skipAttachmentCompaction(prompt) }
                } else {
                    if prompt.availableServices.contains(.catbox) {
                        Button("Upload to Catbox (Permanent)") {
                            model.uploadOversizedAttachment(prompt, using: .catbox)
                        }
                    }
                    if prompt.availableServices.contains(.litterbox) {
                        Button("Upload to Litterbox (24 Hours)") {
                            model.uploadOversizedAttachment(prompt, using: .litterbox)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        model.dismissOversizedAttachmentPrompt(id: prompt.id)
                    }
                }
            } message: { prompt in
                if prompt.stage == .compaction {
                    Text("\(prompt.fileURL.lastPathComponent) exceeds your Discord upload limit. Compress a copy to reduce its size and quality?")
                } else {
                    Text(model.oversizedAttachmentMessage(prompt))
                }
            }
            .dialogSuppressionToggle("Don’t ask again (skip this step)", isSuppressed: Binding(
                get: {
                    (compacting ? model.attachmentSettings.compactionPolicy : model.attachmentSettings.externalUploadPolicy) == .never
                },
                set: { suppressed in
                    var settings = model.attachmentSettings
                    if compacting { settings.compactionPolicy = suppressed ? .never : .ask } else { settings.externalUploadPolicy = suppressed ? .never : .ask }
                    model.applyAttachmentSettings(settings)
                }
            ))
    }
}
