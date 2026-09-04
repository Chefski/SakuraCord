import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayDispatch(name: String, body: JSONValue) async {
        let data: Data
        if name == "READY" || name == "RESUMED" {
            data = Data()
        } else {
            let serialization = discordPerformanceSignposter.beginInterval(
                "GatewayDispatchJSONSerialization",
                id: discordPerformanceSignposter.makeSignpostID()
            )
            guard let encoded = try? JSONEncoder().encode(body) else {
                discordPerformanceSignposter.endInterval(
                    "GatewayDispatchJSONSerialization", serialization
                )
                return
            }
            discordPerformanceSignposter.endInterval(
                "GatewayDispatchJSONSerialization", serialization
            )
            data = encoded
        }
        if await handleGatewayBootstrapEvent(name: name, body: body, data: data) { return }
        if await handleGatewayGuildEvent(name: name, body: body, data: data) { return }
        if await handleGatewayThreadEvent(name: name, body: body, data: data) { return }
        if await handleGatewayChannelAndInteractionEvent(name: name, body: body, data: data) {
            return
        }
        if await handleGatewayMessageEvent(name: name, body: body, data: data) { return }
        if await handleGatewayMemberEvent(name: name, body: body, data: data) { return }
        _ = await handleGatewayVoiceEvent(name: name, body: body, data: data)
    }
}
