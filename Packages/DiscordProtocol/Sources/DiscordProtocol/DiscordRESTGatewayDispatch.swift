import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayDispatch(name: String, body: JSONValue) async {
        if await handleGatewayBootstrapEvent(name: name, body: body) { return }
        if await handleGatewayGuildEvent(name: name, body: body) { return }
        if await handleGatewayThreadEvent(name: name, body: body) { return }
        if await handleGatewayChannelEvent(name: name, body: body) { return }
        if await handleGatewayInteractionEvent(name: name, body: body) { return }
        if await handleGatewayMessageEvent(name: name, body: body) { return }
        if await handleGatewayMemberEvent(name: name, body: body) { return }
        _ = await handleGatewayVoiceEvent(name: name, body: body)
    }
}
