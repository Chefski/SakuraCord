import SwiftUI

struct ProfileMembershipSection: View {
    let createdAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceScale.metric(8)) {
            Text("Member Since", bundle: #bundle).font(.interfaceSystem(size: 12, weight: .medium))
            Text(createdAt, format: .dateTime.day().month(.abbreviated).year()).font(.interfaceSystem(size: 14))
        }
        .padding(.horizontal, InterfaceScale.metric(16)).padding(.vertical, InterfaceScale.metric(12))
    }
}
