import SwiftUI

struct ProfileMembershipSection: View {
    let createdAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Member Since", bundle: #bundle).font(.system(size: 12, weight: .medium))
            Text(createdAt, format: .dateTime.day().month(.abbreviated).year()).font(.system(size: 14))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
