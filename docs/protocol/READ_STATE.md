# Read state and Inbox

[Protocol index](../PROTOCOL_BASELINE.md)

## Owners and checks

[AccountReadStateModel](../../App/Sources/SakuraCord/Models/AccountReadStateModel.swift)
owns acknowledgement state; [InboxState](../../App/Sources/SakuraCord/Models/InboxState.swift)
owns Inbox presentation. Network operations live in
[DiscordRESTInbox.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTInbox.swift) and
[DiscordRESTInboxEvents.swift](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTInboxEvents.swift).
Relevant checks are [AccountReadStateModelTests.swift](../../App/Tests/SakuraCordAppTests/AccountReadStateModelTests.swift),
[InboxTests.swift](../../App/Tests/SakuraCordAppTests/InboxTests.swift) and
[InboxContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/InboxContractTests.swift).

## Acknowledgement authority

READY read state and versioned Gateway acknowledgements are authoritative across
launches. Do not persist a second local read boundary. Ordinary viewing ACKs require
the actual visible conversation/read geometry, not row construction or a temporary
pre-position viewport. The UI's visit boundary can remain stable while provider
acknowledgements advance in the background.

A visit acknowledges when the bottom edge of the newest message enters the
viewport, even if the first unread row of a long backlog is not loaded (a
lower-bound `N+` count). Opening such a backlog directly at its newest message
shows only its tail, so, as in Discord, that visit stays unread until the reader
scrolls toward the newest message again or chooses Mark as Read. Opening above
the newest message needs no extra gesture, and a fully visible unread run with
a loaded divider acknowledges on open. A conversation without a usable
acknowledged boundary, including a READY `last_message_id` that is not a
snowflake (such as the number `-11`), is not held: no scroll can reach its
unread start. Wheel or scrollbar movement toward newer messages releases the
hold; resizing and app-owned positioning do not. A window detached from the
newest message never acknowledges automatically, and a debounced acknowledgement
is dropped if the reader moved away from the newest message while the
conversation stayed open; leaving after reaching it still counts. A remote
ACK or failed Mark Unread rollback that releases the hold resumes ordinary
viewing acknowledgements without requiring another geometry callback.

A channel ACK posts to `/channels/{channel}/messages/{message}/ack` with applicable
flags, `last_viewed` and the latest server-issued token. Serialize account requests
and coalesce per channel; retain each optimistic intent's rollback boundary. A
debounced intent replaced before it is sent is rolled back first, so only
queued or in-flight intents remain as predecessors.
Definite failure reverts that intent without undoing an earlier accepted ACK
or discarding subsequent live messages and mentions.
Reconnects overlay pending intent rather than cancelling it. No automatic replay
follows an ambiguous failure.

Explicit Mark Unread uses the preceding message boundary with `manual:true` and
recomputed mention count. **Inbox Undo is different:** it sends an ordinary ACK
to the captured old boundary, preserving `last_viewed` and omitting `manual` and
`mention_count`. A strictly newer account read-state version can therefore move
the boundary backwards without `manual`. Older versions are ignored; equal-version
ordinary updates do not gain that authority. A pending Undo's exact target must
survive a preceding read ACK arriving late. Do not impose unconditional monotonicity.

## Unread groups and bulk actions

Opening/refreshing Unread freezes group order and message boundaries. New messages
do not append to that frozen range; edits/deletions reconcile existing entries.
Groups page history forward from the captured old boundary. Forum groups use post
IDs and the live thread catalogue. A normal Mark Read targets the captured newest
boundary, except that a forum group, like every forum acknowledgement, targets the
current time; bulk operations capture targets before batching `/read-states/ack-bulk`.
Do not recompute targets from a later rerender or restore obsolete mention counts
on Undo. Fully loaded expanded empty groups may acknowledge and disappear without
Undo; incomplete loads do not establish emptiness.

The optional server-rail Read All action and a server's own Mark as Read (as in
web build 649389) use the same bulk route with type 0 entries for accessible
current server channels and active joined threads, including muted
conversations. They exclude DMs, departed/archived threads, resource channels
and scheduled events. Targets are captured only after native confirmation; new
messages beyond those boundaries stay unread. Accepted batches remain read if a
later batch fails; failed targets roll back without automatic replay.

This scope follows Vencord’s
[ReadAllNotificationsButton](https://github.com/Vendicated/Vencord/blob/32c90633ce6a95d7e56c95479efbb431bacf1eac/src/plugins/readAllNotificationsButton/index.tsx),
which dispatches Discord’s `BULK_ACK` with channel IDs, last-message IDs and type 0.
The [production web client](https://discord.com/assets/web.4d4b2f75fdea5470.js)
(stable build 641004, inspected 18 October 2026) maps that action to
`POST /read-states/ack-bulk` with `read_states` containing `channel_id`,
`message_id` and `read_state_type`, in batches of at most 100 with a one-second
pause after each successful batch. SakuraCord follows that pacing between
batches, in addition to server-provided rate-limit cooldowns. The web client's
bulk queue retries a failed batch up to three total attempts; SakuraCord retains
its one-attempt mutation policy and partial-batch reconciliation rather than
replaying an ambiguous write. Read All errors include the underlying failure.

Restricted groups require the applicable account eligibility and local server
consent before exposing their contents. Mentions also gate restricted accessories.
Bookmark and Reminder surfaces are outside this Inbox implementation.

## Recent mentions

`GET /users/@me/mentions` uses `limit=25`, role/everyone filters, optional guild
scope and an exclusive `before` cursor from the last **raw** response entry.
Filtered presentation must not change cursor advancement.

`DELETE /users/@me/mentions/{message}` and `RECENT_MENTION_DELETE` remove recent
mentions. They do not ACK a channel or clear its badge. Conversely, a channel ACK
does not remove recent mentions. Local filter choices are not server settings.

## Scheduled events

READY read-state type 1 uses a guild resource ID, last acknowledged event ID and
badge count. Individual event-group ACK is `POST /guilds/{guild}/ack/1/{event}`
with `{}`, reconciled through `GUILD_FEATURE_ACK`. Undo after fully acknowledging
an event group restores its card locally; it sends no reverse ACK.

Interest reads use `/users/@me/scheduled-events?guild_ids={guild}`. RSVP uses
PUT/DELETE `/guilds/{guild}/scheduled-events/{event}/users/@me`, with
`{"response":1}` for PUT. Event creation/update/deletion and user RSVP dispatches
update provider state; these are implemented consumers, not ignored families.

## Settings and notifications

A thread without a saved acknowledgement, or with READY's `0`, is read up to
Discord's fallback boundary (`ReadStateStore`, build 649389): the later of
joining it less five seconds and its archive time less a millisecond, else its
creation less a millisecond, and for a text thread never before the account
joined the server. A reopened thread with no newer message is therefore read,
and a never-opened forum post's starter is unread. The boundary is computed
once, when the thread is first known, and is not a tracked acknowledgement.

Server unread indicators and the Dock's unread-conversation count use current
channels and active joined threads with accessible current parents. As in
Discord's thread row and `GuildReadStateStore`, a joined thread's unread row
ignores its parent's mute and unread setting, and it lights the server unless
the thread or the server is muted. Retained
thread read state is not evidence of membership: archived, left or orphaned
threads keep their read history without contributing to those aggregates.
Thread membership changes refresh both indicators. A forum contributes unseen
posts, not its raw message boundary, while active joined posts retain their own
conversation unread state. Mention totals remain a separate projection with
the same membership rule as Discord's `ReadState.canHaveMentions`: a thread's
mention count reaches its row, the server badge and every total only while the
account has joined the active thread. The count is still tracked, so it appears
if a starter, user or role mention later adds the account to the post. Do not
roll such counts up onto the parent forum row: the official client has no
aggregate forum badge (observed in web build 641803, 20 October 2026, live and
from READY), and a counted mention must always have a visible row.

A forum post is "New" only while its forum is open, when the post is active,
was never opened, its ID is above the forum's acknowledgement captured at
channel select, and it was created after the guild's `joined_at` (official
`isNewForumThread`, build 649389). A never-acknowledged forum captures the join
time as its boundary, and the capture survives the visit's own acknowledgement.
The forum row's "N New" count (`ActiveJoinedThreadsStore.getNewThreadCount`)
counts active posts the user has neither joined nor opened: in the open forum
by the same rule, elsewhere by post ID above the forum's tracked
acknowledgement, or above the join time when there is none, with no separate
join check. Only a server or local acknowledgement is tracked; the boundary
seeded for a read state READY omits is not, so a never-read forum counts every
post since joining. An unknown `joined_at` counts as now. The count stays on
the selected row during a visit and is hidden behind a mention badge, on a
muted forum, and unless the forum's unread setting resolves to All Messages. A
recently created, never-acknowledged channel shows Discord's separate "NEW" channel pill instead,
which SakuraCord does not implement. Server and Read All acknowledgements
include every forum, read or not, as Discord's bulk acknowledgement does
(observed 26 October 2026); a category acknowledgement includes a forum with
counted posts even when its own boundary is seeded. Both clear a never-read
forum's count, and a completed local
acknowledgement is tracked before its Gateway echo; a still-pending earlier
intent that later fails cannot roll back behind it. A forum's own Mark as Read
is enabled only by Discord's forum unread count: active posts newer than the
forum's tracked acknowledgement that are unread, where a joined post must be
unmuted unless mentioned. It is therefore unavailable on a never-read forum
whatever its new-post count. A forum card is emphasized while its active post
is unread, joined or not, so closed posts are dimmed. That state alone enables
the post's own Mark as Read (`isForumPostUnread`), which acknowledges its newest
message. A message arriving in a post never opened leaves it unopened. Its
footer shows "(N New)" only for an unread post with a tracked acknowledgement
(Discord's "opened"), which a post created while running gains only from an
acknowledgement or the next READY, with N its unread count capped at the
reply count, so an unread starter alone shows "(0 New)", and at 25+ (module
435470). Every acknowledgement of a forum, from a visit, its row, the server, a
category, Read All or the Inbox, targets the current time. Labels, counts and server
Mark as Read were compared live in web build 649389 and SakuraCord on 25 and
26 October 2026, with the official client's acknowledgements blocked so both
read the same server state.

Inbox tab/collapse settings use the shared type-1 protobuf writer and preserve
unknown fields. A `400 / 50105` invalid-data rejection reloads settings and reports
the failed write. Event collapse uses Discord's reserved channel key inside a
**guild-scoped** map; that key must not merge unrelated guilds. Rapid tab and
collapse changes are coalesced and only values that differ from saved settings
are written, one request at a time. An open Inbox keeps its local choices over
settings echoes; a failed collapse write restores the saved state.

Notification decisions use decoded mention IDs, roles and reply metadata, not
text parsing. Resolve channel/category/guild settings, mute expiry and account
preferences together with current access and foreground state. Native notification
delivery and Dock/sidebar presentation consume account read state; they must not
become independent read-state stores. Clear related native notifications when
confirmed read state requires it. OS delivery/audio verification is described in
[Development](../DEVELOPMENT.md#verifying-native-notification-audio).
