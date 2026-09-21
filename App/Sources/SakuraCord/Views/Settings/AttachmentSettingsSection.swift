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
            if value.compactionPolicy != .never {
                Picker("Compression quality", selection: $value.compaction.quality) {
                    Text("Higher quality").tag(AttachmentCompactionOptions.Quality.high)
                    Text("Balanced").tag(AttachmentCompactionOptions.Quality.balanced)
                    Text("Smaller files").tag(AttachmentCompactionOptions.Quality.small)
                }
                .settingsControlAnchor(.attachmentCompactionQuality, state: state)
            }
            Picker(selection: $value.externalUploadPolicy) {
                ForEach(AttachmentHandlingPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload files that still exceed Discord’s limit")
                    Text("Uploads to a third-party host and adds a link to your draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsControlAnchor(.attachmentExternalUploadPrompt, state: state)
            if value.externalUploadPolicy == .always {
                Picker("File host", selection: $value.externalProvider) {
                    Text("Litterbox · 24 hours").tag(ExternalAttachmentHostingService.litterbox)
                    Text("Catbox · Permanent").tag(ExternalAttachmentHostingService.catbox)
                }
                .settingsControlAnchor(.attachmentExternalProvider, state: state)
            }
        } header: {
            Text("Attachments", bundle: #bundle)
        }
    }
}
