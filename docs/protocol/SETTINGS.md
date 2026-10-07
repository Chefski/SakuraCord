# Profiles and synchronized settings

[Protocol index](../PROTOCOL_BASELINE.md)

## Owners and checks

| Contract | Source | Representative checks |
| --- | --- | --- |
| Profile saves and widgets | [DiscordRESTProfileSaving.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTProfileSaving.swift); [DiscordProfileWidgetEligibility.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordProfileWidgetEligibility.swift) | [ProfileEditingContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/ProfileEditingContractTests.swift); [ProfileEditorStateTests.swift](../../App/Tests/SakuraCordAppTests/ProfileEditorStateTests.swift) |
| Status | [DiscordProfileSettingsProto.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordProfileSettingsProto.swift); [DiscordRESTProfileCustomStatus.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTProfileCustomStatus.swift) | [StatusPickContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/StatusPickContractTests.swift) |
| Server folders | [DiscordSettingsProtoMerging.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordSettingsProtoMerging.swift) | [GuildFolderSettingsContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/GuildFolderSettingsContractTests.swift) |
| Emoji usage and shared saves | [AppModelEmojiFrecency.swift](../../App/Sources/SakuraCord/Models/AppModelEmojiFrecency.swift); [DiscordRESTEmojiFrecency.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTEmojiFrecency.swift) | [EmojiFrecencyTests.swift](../../App/Tests/SakuraCordAppTests/EmojiFrecencyTests.swift); [GIFProviderContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/GIFProviderContractTests.swift) |
| Favourites/frecency | [DiscordSettingsProtoStickers.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordSettingsProtoStickers.swift); [DiscordSettingsProtoSoundboard.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordSettingsProtoSoundboard.swift); [DiscordSettingsProtoCommandFrecency.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordSettingsProtoCommandFrecency.swift) | [ProviderRequestContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/ProviderRequestContractTests.swift); [GIFProviderContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/GIFProviderContractTests.swift); [ApplicationCommandFrecencyCodecTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/ApplicationCommandFrecencyCodecTests.swift) |

## Profile edits and private account data

The provider owns current eligibility and validation; the editor owns a draft.
Apply account/guild scope and permission checks at submission, not only while
showing controls. Profile saving is staged: keep failed or newer edits without
repeating acknowledged writes. File selection/cropping does not save a profile.
Widget assets use their allocated upload path before references enter the draft.

Personal widgets require their entitlement and rollout assignment. **Game widgets
do not inherit the personal-widget Nitro requirement.** Use the eligibility model
and widget type; do not apply one blanket gate to all widgets. Owned collectibles,
guild permissions and product-specific restrictions remain independent checks.

Account contact/device details are private session-only values. Do not add email,
phone or session hashes to public User values or saved-account labels. Profile
and own-user updates invalidate/reconcile the appropriate caches; late work from
a replaced account cannot publish into the new editor.

## Protobuf preservation

User-settings type 1 and Frecency type 2 are binary protocols. Preserve unknown
fields and untouched siblings when applying an edit. A partial update has different
meaning from a complete replacement. Apply data versions before overwriting newer
local/provider state. Do not replace the whole proto with only a decoded feature.

The relevant feature codec defines whether a request sends a complete updated
proto or only changed fields; this varies between settings. Decode the merged
server response and Gateway settings updates through the same owner. Wire-level
emptiness can require an explicit empty field rather than omission.

## Status and custom status

The provider retains one pending account status pick, its settings data version
and account identity. It overlays received status while pending and survives
connection loss locally until saved, superseded or rejected. READY applies it
before publishing self-member state/presence. READY or RESUMED schedules one
silent save after 5–10 seconds when needed; losing app focus can flush once per
edit until the next connection cycle. Termination itself does not flush.

Status and custom-status writes share a save slot. An edit made during a PATCH
must remain pending after the earlier response. User-initiated saves may retry
one `429` when the server delay is at most 30 seconds; automatic saves do not.
`400 / 50105` reloads settings instead of opening the account safety circuit.
A stale/out-of-date result must not silently replace a newer user pick.

Explicit status and custom status have different expiry support: timed presence
picks are not implemented; custom-status expiry is supported. Custom-status saves
preserve surrounding settings and start relative expiry at submission. A failed
profile-stage status write keeps its draft without replaying prior profile stages.

## Server folders and DM pins

Rail edits PATCH type-1 settings field 14 (`GuildFolders`). Encode one top-level
entry per server or folder, drop emptied folders, and preserve untouched/unknown
bytes and stored servers missing from the current catalogue. Do not rewrite
`guild_positions` as a side effect. Serialize saves and retain the latest desired
layout; definite failure restores the confirmed layout. Merely drawing or expanding
a folder adds no request.

DM pins use flags in the account's `@me` channel notification overrides, preserving
unrelated flags/settings. The app projects pinned ordering without mutating the
provider's channel catalogue or persisting a workspace snapshot. See
[pin contracts](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/DirectMessagePinSettingsTests.swift).

## Emoji, GIFs, stickers and sounds

Favourites and usage history share Frecency type 2 but have different encodings
and presentation order. Do not generalize one feature's ordering to the others.

| Feature | Durable distinction |
| --- | --- |
| Emoji | Ordered favourites in field 5. Message usage is field 6, reaction usage field 13. Both usage maps are saved together, each capped at 100 entries by its latest sample; the merged response and full Gateway echo update every session. |
| GIFs | URL-keyed map with format, source URL, dimensions and monotonic order; presentation is descending order, including extensionless sources. |
| Stickers | Field 3 favourites; clearing requires the explicit empty container. Changed-field patches preserve siblings and consume the merged response. Field 4 usage updates preserve unrelated map entries and unknown bytes. |
| Sounds | Field 8 favourite IDs; stored insertion order differs from picker availability/numeric-ID ordering. Field 11 is played-sound history. |
| Slash commands | Field 7 maps command keys to total uses, up to ten packed recent-use timestamps, frecency and rounded score. A save includes field 7 and any pending emoji usage; it keeps the 500 most recently used entries; the Gateway echoes the full stored proto to every session. |

Usage recording and delayed frecency persistence must not turn every send/play
into an unrelated synchronous settings write. A failed explicit favourite edit
rolls back to provider-authoritative state. Ready/Gateway guild catalogue updates
reconcile the same caches without invented REST fallbacks. Detailed ranking and
codec algorithms belong to the linked implementation and its tests.

The official Fresh desktop client captured on 2026-10-07 (host 0.0.411,
web build 630444, `web.90d3ab34abfe98da.js`) records message emoji only after a
successful send, retaining duplicate occurrences and excluding code. Inserting
or discarding a draft and editing a message do not record uses. Adding a reaction
optimistically records both reaction and message usage; removing it does not
undo either use. Unicode keys retain tone variants; custom keys are snowflakes.
The same build’s command submission source (`545152`, `onMessageSuccess`)
records parsed Unicode/custom emoji from successful command options; this path
is source-corroborated, not part of the live message/reaction capture.

Emoji ranking uses the shared scorer in
[DiscordFrecencyStore](../../App/Sources/SakuraCord/Models/DiscordFrecencyStore.swift),
with distinct message and reaction formulas. Resolve known, role-eligible emoji, take the first
42, then fold tone variants and apply picker availability; do not refill slots
removed at those later stages. Stable ties retain JavaScript object enumeration
order. Empty histories seed Discord's defaults without marking them pending.
Resolve Unicode identities through the key catalogue and actual shortcodes;
search keywords are not identity aliases (for example, `bug` must not resolve
to snail, nor `heart` to love letter). The follow-up live comparison with
`web.b5e982817c690727.js` confirmed the same scoring and persistence modules.
Custom lookup retains the [emoji role restrictions](https://docs.discord.com/developers/resources/emoji#emoji-object).
The official EmojiStore admits unrestricted emoji, or a known member whose roles
intersect the restrictions. It also resolves purchasable subscription emoji in
guilds with `ROLE_SUBSCRIPTIONS_ENABLED`; this is lookup eligibility for locked
previews, not permission to send. Subscription roles require a non-null
`subscription_listing_id` and presence of the `available_for_purchase` tag
(including null). This edge case is source-corroborated and covered by deterministic
tests; the live comparison account had no restricted emoji in its usage history.

Pending uses persist per account and replay over received histories. A successful
save acknowledges only the submitted prefix, so a use made while the request is
in flight survives exactly once. Defer incoming histories during a save and reject
older data versions. Flush shortly after connection/resume (10 ms plus up to 10 s),
every two hours plus up to ten minutes, on connection close, and alongside any other type-2 settings save. Desktop focus changes are not the mobile inactive trigger.
The provider gathers the account owner’s pending emoji batch immediately before
a type-2 write and acknowledges it from that same request’s merged response;
favourite saves do not require a second usage PATCH.
Partial fields 6/13 preserve unrelated settings and unknown nested fields; never
send an old complete settings blob to update usage.

Local preference export/import is a separate
[architecture boundary](../ARCHITECTURE.md#settings-and-presentation-boundaries);
it never transfers Discord-synchronized settings.
