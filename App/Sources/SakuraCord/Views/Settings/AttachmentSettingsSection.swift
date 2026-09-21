import MediaPipeline
import SwiftUI

struct AttachmentSettingsSection: View {
    @Binding var value: AttachmentSettingsSnapshot
    let state: SettingsViewState

    var body: some View {
        Section {
            Picker("Compress oversized images and videos", selection: $value.compactionPolicy) {
                ForEach(AttachmentHandlingPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .settingsControlAnchor(.attachmentCompactionPrompt, state: state)
            Picker("Compression quality", selection: $value.compaction.quality) {
                Text("Higher quality").tag(AttachmentCompactionOptions.Quality.high)
                Text("Balanced").tag(AttachmentCompactionOptions.Quality.balanced)
                Text("Smaller files").tag(AttachmentCompactionOptions.Quality.small)
            }
            .disabled(value.compactionPolicy == .never)
            .settingsControlAnchor(.attachmentCompactionQuality, state: state)
            Picker("Upload files that still exceed Discord’s limit", selection: $value.externalUploadPolicy) {
                ForEach(AttachmentHandlingPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .settingsControlAnchor(.attachmentExternalUploadPrompt, state: state)
            Picker("File host", selection: $value.externalProvider) {
                Text("Litterbox · 24 hours").tag(ExternalAttachmentHostingService.litterbox)
                Text("Catbox · Permanent").tag(ExternalAttachmentHostingService.catbox)
            }
            .disabled(value.externalUploadPolicy != .always)
            .settingsControlAnchor(.attachmentExternalProvider, state: state)
        } header: {
            Text("Attachments", bundle: #bundle)
        }
    }
}
