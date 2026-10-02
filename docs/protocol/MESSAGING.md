# Messages and uploads

[Protocol index](../PROTOCOL_BASELINE.md)

## Owners and checks

[DiscordRESTProvider](../../Packages/DiscordProtocol/Sources/DiscordProtocol/DiscordRESTProvider.swift)
and its neighbouring feature files own network requests. App's
[composer state](../../App/Sources/SakuraCord/Models/MessageComposerState.swift) owns drafts
and the outbox; MediaPipeline owns local media transformations.

| Contract | Representative checks |
| --- | --- |
| DM/history/send budgets | [DirectMessageProviderContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/DirectMessageProviderContractTests.swift); [ProviderRequestContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/ProviderRequestContractTests.swift) |
| Search, forwarding and pins | [MessageSearchContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/MessageSearchContractTests.swift); [MessageForwardingContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/MessageForwardingContractTests.swift); [PinnedMessagesContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/PinnedMessagesContractTests.swift) |
| Polls and threads | [PollContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/PollContractTests.swift); [ForumProviderContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/ForumProviderContractTests.swift) |
| Uploads | [UploadPrivacyContractTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/UploadPrivacyContractTests.swift); [AttachmentUploadURLValidationTests.swift](../../Packages/DiscordProtocol/Tests/DiscordProtocolTests/AttachmentUploadURLValidationTests.swift); [UploadPrivacyPreparationTests.swift](../../App/Tests/SakuraCordAppTests/UploadPrivacyPreparationTests.swift) |

## Sends and history

Opening/selecting a conversation, fetching history and sending are distinct
operations. An ordinary message POST carries content, nonce, TTS/flags and
`mobile_network_type`, with attachments/reply reference when present and
`chat_input` context. SakuraCord adds `enforce_nonce:true` for ordinary messages
as a deliberate idempotency safeguard. Concurrent same-channel/same-nonce sends
share one mutation. Preserve that nonce for explicit retries; an ambiguous result
must not cause automatic resend. [Poll creation](#polls) has a distinct body.

A reply includes reference type 0, message ID and channel ID. To disable the reply
ping, include `allowed_mentions` with normal users/roles/everyone parsing and
`replied_user:false`; do not suppress unrelated content mentions accidentally.
Current permissions, membership gates and slowmode are checked before consuming
a draft or dispatching any send entry point. REST/Gateway confirmations reconcile
the same optimistic message rather than creating duplicates.

History uses permission-checked channel message reads. A cold newest page loads
10 messages once per channel per uninterrupted Gateway connection. Warm
newest-backed pages are session-cached; a Gateway gap invalidates completeness
and refreshes a reopened/selected channel once. Distant navigation replaces the
window with `around` history; older/newer edges paginate independently. It must
not masquerade as a newest-backed cache. A superseded selection may still finish
its dispatched read and populate the account cache without changing selection.

Search uses guild search or read-only DM search. Pagination and indexing follow
server cursors and the [shared budgets](../PROTOCOL_BASELINE.md#attempt-budgets).
Rendering a result, reply, embed or thread card does not trigger detail fetching.
Sparse edits, deletions and author updates must reach retained presentation even
when the provider's bounded working set has evicted the underlying message.

## Reactions, pins and forwarding

Reaction intent is serialized per message/emoji with one coalesced follow-up.
If the target is absent from the working set, read `around={message}&limit=1`
before deciding whether PUT/DELETE is needed. Missing/failed reads prevent the
mutation; an already satisfied intent sends nothing.

Pin/unpin uses the dedicated `PIN_MESSAGES` permission and the message-pins
route. One mutation per message runs at a time. Definite rejection rolls back;
ambiguous failure is reconciled without automatic replay. Pin pages and Gateway
pin/message updates share the same authoritative state.

Forwarding sends one explicit message per selected destination with a type-1
reference, first-party forwarding context and permission checks. Destinations
are independent outcomes; a partial failure must not replay successful sends.
Forwarded snapshots render locally and do not authorize reads of the source.

## Polls

Creation is an ordinary message POST with `poll_creation` context, empty content,
nonce and poll data, but **without `enforce_nonce`**. Question/answer limits and
duration choices live with the validation model and contract tests. Answers use
`poll_media`; Discord assigns answer IDs. Guild creation requires `SEND_POLLS`.

Vote PUT replaces the entire selection using **string** `answer_ids`, including
an empty array to remove votes. Voter GETs use `limit=100&type=2` and an exclusive
`after` cursor; known zero counts need no request. Only the author explicitly
ends an active poll, through an empty-body expire POST. Poll messages are not
editable through ordinary message editing.

Vote events patch retained projections in order. Missing historical results are
unknown, not zero. Final counts cannot be replaced by stale REST results or
omitted fields; non-personalized final `me_voted:false` values must not erase a
known personal selection. Natural expiry and rendering send no expiry request.
An explicit results read can repeat once if overlapping votes make its unversioned
tally ambiguous; a second overlap reports failure rather than starting polling.
Expected route-scoped poll errors stay local, while account restrictions retain
the shared safety circuit.

## Forums, threads and commands

Forum browsing uses `threads/search` and preview `post-data` batches of at most
ten. Publish the catalogue independently of starter previews. Advance pagination
by raw server records, retain valid siblings and cancel obsolete searches.
Creating a forum post uses one thread mutation after any attachment uploads.
Composer Create Thread uses one thread POST followed by a message send to the new
thread, with the current public/private-thread permission rules. An unknown
thread link may first require one Get Channel; a known one does not.

Thread lifecycle events advance the parent forum boundary before unread
projection. Metadata, archive, lock, pin and delete are explicit, permission-gated
mutations. Message-created thread cards use cached thread/message data.

A cold slash-command picker loads one context index and one user index, coalesced
per target. Search, option editing and cached entity resolution are local.
Autocomplete sends type 4 per settled distinct query; execution sends type 2,
with attachment uploads completed first. Pending nonce state reconciles through
Gateway events. Invocation `guild_id` and command-registration `data.guild_id`
have different meanings; the latter appears only for guild-scoped commands.

## Attachments

Privacy preparation precedes reservation and external multipart construction.
Use the prepared byte count for caps and reservations. Enabled-by-default metadata
removal makes local copies of supported images/videos, preserving orientation and
colour profiles. It does not modify the original. Documents, archives and
standalone audio are outside this policy. Unsupported/corrupt media require
explicit approval to upload unchanged; approval covers exact bytes and is
invalidated by file changes or account reset. Upload from a stable private copy.

Compaction is separate and attempted only for oversized media according to its
policy. A prepared or compacted file fitting the account cap is accepted,
including equality at the boundary. The provider repeats the cap check before
reservation. Discord-issued upload URLs are validated and receive only the
headers needed for storage, not account credentials.

Compression and external-host preferences live in **Settings → Features**;
unavailable dependent controls remain visible but disabled. Both policies default
to Ask. A named host selection or saved Automatically policy authorizes external
upload. Never skips that path. The uploader receives no Discord token, cookie,
client metadata or message body. It accepts only the configured host's validated
HTTPS result and inserts the URL into the originating draft; it never sends the
message. Account limits and host caps are maintained by their implementation,
not a second documentation constant table.

See [external-host checks](../../App/Tests/SakuraCordAppTests/ExternalAttachmentUploaderTests.swift)
and [metadata fixtures](../../Packages/MediaPipeline/Tests/MediaPipelineTests/UploadMetadataTests.swift)
for failure/privacy boundaries. Detailed container algorithms belong beside that
code, not in the transport-wide baseline.
