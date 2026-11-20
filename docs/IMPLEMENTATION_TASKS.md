# ULO implementation and research handoff

Source: the owner's “Research same-zone laying limits” orchestration side chat,
read November 16, 2026. Implementation stays in the main development chat.

## Current build

- [x] Replace the fixed eight-layer grid with a scrollable layer/request list.
- [x] Normalize zone/subzone IDs on Forever and TBC; expire peer zone claims and
  distinguish verified same-zone eligibility from unknown or stale metadata.
- [x] Advertise versioned ULO zone/capability data without modifying legacy
  Forever AutoLayer requests; use the shipped AL2 zone format on TBC.
- [x] Require an actual different-layer observation and verified helper zone;
  use bounded, owned-group post-join checks for compatible legacy requests.
- [x] Use Overlord 2.5.3's native LayerJumper:Join boundary and native lifecycle.
  Preserve volunteer preferences and OnRequest; never write its shard state or
  use GroupFinder/directory contacts as consent to help.
- [x] Treat NWB layer observations as intelligence, not helper opt-in.
- [x] Align AutoLayer's static/three daily channels with the server calendar,
  retaining one public request and respecting reserved chat slots.
- [x] Extend permanent regressions in the existing standard-gate suites.
- [x] Guard secret channel message/sender values before comparisons and parsing;
  apply the same boundary checks to guild chat, whispers and ULO addon messages.
- [x] Deploy the tested development tree to all local clients and verify hashes.

## Additional tasks from the side chat

- [ ] Add independent allowed-sender controls for guildmates, in-game friends,
  other players and/or an allowlist. Apply real character/realm identities to
  text and addon requests, preserving self-invite and cross-realm safeguards.
- [ ] Separate outgoing requests, incoming auto-help consent, and data sharing.
  The current source checkboxes and global Auto-Invite switch are not audience
  controls. Enabling an integration must not change another addon's volunteer
  preference.
- [ ] Decide Battle.net support. The present ordinary-whisper option is not a
  Battle.net friends feature. Do not invite display names; any future BN path
  must resolve an eligible in-game character/realm.
- [ ] Validate actual NWB version/data structures and native capabilities.
- [ ] Validate current TresLayerSwap and LayerHopper vendor formats, consent,
  and lifecycle. Generic parser branches and headless tests are not native
  interoperability evidence; keep unsupported capabilities explicit.
- [ ] Add audience, helper-consent, mixed-route and persistence tests with the
  corresponding implementation; retain client-only acceptance separately.
- [ ] Validate external AutoLayer multi-target/range messages and remaining
  vendor data contracts beyond the single-target/exclusion flows covered here.

## Evidence and limits

Forever's same-zone rule is a practical default based on reports/testing, not
a universal Blizzard contract: [AutoLayer #143](https://github.com/iraizo/AutoLayer/issues/143),
[unmerged #145](https://github.com/iraizo/AutoLayer/pull/145).
TBC's AL2 support shipped in [#134](https://github.com/iraizo/AutoLayer/pull/134).
Legacy Forever requests must not acquire numeric zone fields that older clients
can misread as layers. [Protocol discussion](https://github.com/iraizo/AutoLayer/issues/143#issuecomment-6841377186).
Overlord native boundary: [LayerJumper 2.5.3](https://github.com/leliondoc/overlord-forever-addon/blob/2b5c711191c35b1f127f97e616b247e62eb20a5a/LayerJumper.lua).
AutoLayer reviewed at `123ec2d650490711643e6864d431e9dcb8f545c3`
(1.9.15): [channel generation](https://github.com/iraizo/AutoLayer/blob/123ec2d650490711643e6864d431e9dcb8f545c3/Modules/Layering.lua).
Respect the native world-refresh prompt when offered; a formed party is not
proof of transfer.

ULO's `S2` status and `R2` requests carry normalized zone IDs. Legacy `S`/`R`
messages remain supported. Status heartbeats currently use the ULO guild addon
channel; ULO does not assume non-guild external peers have adopted this schema.
Unknown/stale scope is shown as unverified. Known cross-zone peers are excluded;
legacy volunteers can be checked after joining with a six-second read window.
Unreadable leaders are cancelled, not marked successful.

Overlord's native Join can choose subsequent candidates on the requested raw
shard. ULO preserves that native algorithm and checks the actual joined leader;
it cannot promise every native fallback candidate was filtered before invitation.
Specific ULO layer numbers require a fresh mapping to a native raw shard ID;
ULO never substitutes an ordinal layer number for Overlord's shard ID.
This build retains ULO's existing detection/NWB hooks; its displayed numbers do
not establish canonical Blizzard layer numbering. Actual transfer, native map
readability, rendering and SavedVariables persistence require client acceptance.

## Local installation result — November 16, 2026

The full `npm.cmd test` gate passed in both the prepared tree and the ULO dev
working tree: Lua 5.1 syntax for 18 files, all six Dev manifests, and 246/246
production headless cases. `git diff --check` passed. No release/tag was created.

The repository local installer deployed the working tree to `_anniversary_`,
`_classic_`, `_classic_beta_`, `_classic_era_`, `_classic_era_ptr_`, `_forever_`,
and `_retail_` under `C:\Program Files (x86)\World of Warcraft`. Every client
passed the installer's missing/extra-file and SHA-256 mirror checks for all 28
addon files. All seven exact ULO destinations and reparse-point exclusions were
checked before any replacement; previous ULO folders were backed up under
`%TEMP%\ulo-layer-list-2026-11-16\client-backups-20261116-131008`.

The Forever Overlord LayerJumper remained byte-identical:
`81B836D425A5206A681793259F29B84D0482E67FB2BFD0D9A346879EA5323702`.
Installation did not operate the running game. Restart WoW to ensure the updated
TOCs and new Lua module load. Actual transfer, native UI layout and persistence
remain the client acceptance checks described in [TEST_INFRA.md](TEST_INFRA.md).

## Secret chat correction — current installed build

Following the owner's native AutoLayerProtocol.lua:346 secret-sender report,
guard ordering was corrected and a permanent Tier 4/F12 regression was added.
The full gate now passes 247/247 tests. The corrected Dev tree was reinstalled
to the same seven clients using the local workflow; all 28 addon files matched
per client, with no missing/extra files. Backups are under
`%TEMP%\ulo-secret-chat-2026-11-16\client-backups-20261116-225643`.
Overlord remained unchanged. `/reload` loads this Lua-only correction; native
secret-message acceptance remains pending. The reported stack, regression
evidence and model limitations are recorded in [TEST_INFRA.md](TEST_INFRA.md#user-report-secret-channel-sender-comparison).
