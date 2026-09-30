import Foundation
import SakuraCordModels
import Testing
@testable import DiscordProtocol

@Test func `mobile platform classification survives member decoding and caching without exposing hidden presence`() throws {
    for (platforms, mobileOnly) in [
        (["mobile": "online"], true),
        (["mobile": "idle"], true),
        (["mobile": "dnd"], true),
        (["mobile": "offline"], false),
        (["mobile": "invisible"], false),
        (["mobile": "unknown"], false),
        (["mobile": "idle", "desktop": "online"], false),
        (["mobile": "dnd", "web": "idle"], false),
        ([:], false),
    ] {
        let clientStatus = try JSONDecoder().decode(
            ClientStatusDTO.self,
            from: JSONEncoder().encode(platforms)
        )
        #expect(clientStatus.isMobileOnly == mobileOnly)
        for status in PresenceStatus.allCases {
            let dto = try JSONValueDecoder().decode(GuildMemberDTO.self, from: .object([
                "user": .object(["id": .string("2"), "username": .string("mobile")]),
                "roles": .array([]),
                "presence": .object([
                    "status": .string(status.rawValue),
                    "client_status": .object(platforms.mapValues { .string($0) }),
                ]),
            ]))
            let member = try dto.domain(currentUserID: nil, currentStatus: .online)
            let cached = try JSONDecoder().decode(Member.self, from: JSONEncoder().encode(member))
            #expect(cached.isMobileOnly == mobileOnly)
            #expect(cached.showsMobileIndicator == (mobileOnly && status.isVisibleOnline))
        }
    }
}

func verifyMobilePresenceTransitions(provider: DiscordRESTProvider) async throws {
    // Platform-only transitions must update cached DM presence even when
    // aggregate status does not change. Empty client_status clears mobile.
    for (status, platforms, showsPhone) in [
        ("idle", ["mobile": "idle"], true),
        ("dnd", ["mobile": "dnd"], true),
        ("dnd", ["mobile": "dnd", "web": "online"], false),
        ("dnd", ["mobile": "dnd"], true),
        ("dnd", [:], false),
        ("offline", ["mobile": "online"], false),
        ("invisible", ["mobile": "dnd"], false),
    ] {
        await provider.receiveGatewayDispatchForTesting(
            name: "PRESENCE_UPDATE",
            data: .object([
                "user": .object(["id": .string("2")]),
                "status": .string(status),
                "client_status": .object(platforms.mapValues { .string($0) }),
            ])
        )
        let member = try #require(await provider.members(in: nil).first)
        #expect(member.status.rawValue == status)
        #expect(member.showsMobileIndicator == showsPhone)
    }
}
