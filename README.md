# Enemy Tracker (WoW Forever)

Addon for **WoW Forever (Camelot, interface 16001)**. You keep a personal blacklist of players. The addon detects them nearby using only data the client already provides, alerts you with a RareScanner-style toast and a sound, counts how many are nearby right now, and keeps kill statistics for each player. A minimap button opens the dashboard. Shared groups let friends pool their lists without any server.

**Status (v0.3.0):** checked against a mock of the Forever client API (`tests/`, run under LuaJIT). **Not yet verified in the WoW Forever client.** The spec says a feature isn't done until it's verified in the game, so use the in-game checklist below. Upgrading from v0.1.1 converts the saved data to schema 2; v0.1.1 cannot read it back.

## Install

Copy the `EnemyTracker/` folder into `World of Warcraft/_forever_/Interface/AddOns/` (or whichever folder your Forever client uses for AddOns). Then enable it on the character select screen.

Turn on **enemy nameplates** (`V`, or Options > Interface > Names). Nameplates are the main detection source.

## Usage

| Command | Action |
|---|---|
| `/et add First Surname` | Add a player by full name (also `First-Surname`). If the client has not reported that player this session (nearby, group, chat), the addon warns and asks before adding |
| `/et add` | Add your current target (also `/et addtarget`) |
| Right-click a player | Add to / remove from Enemy Tracker. Works on unit frames, target frame, party/raid frames and names in chat |
| `/et remove First Surname` | Remove a player, after confirmation. Deletes their stats too |
| `/et clear First Surname` | Reset kill stats, after confirmation. The player stays in the list and "last seen" is kept |
| `/et note First Surname [text]` | Set the player's description (one per player, up to 200 characters); no text clears it. Also editable in the dashboard |
| `/et list` | Print the blacklist |
| `/et group` | Open the groups window (also the Groups button in the dashboard). The dashboard also has a Group ID box with Join and Create group buttons |
| `/et group create` | Create a shared group and print its ID (`ET-XXXX-XXXX-XXXX`) |
| `/et group join ID`, `/et group leave ID` | Join or leave a group by ID (any case, dashes and spaces optional) |
| `/et group list` | Print your groups and their state |
| `/et group debug` | Print what is needed to find why groups do not connect: your realm and faction, each group's channel number and players in it, messages sent and received, the last send result |
| `/et show` | Open or close the dashboard (or left-click the minimap skull) |
| `/et on`, `/et off`, `/et toggle` | Turn scanning on or off. It's on by default |
| `/et unlock`, `/et lock` | Move the alert anchor and the counter |
| `/et resetpos` | Reset frame positions |
| `/et test` | Show a test alert |
| `/et options` | Open settings (or right-click the minimap button) |
| `/et lang auto`, `/et lang en`, `/et lang ru` | Addon language: as the game client, English or Russian (also in the options). Messages switch at once; the addon offers a reload so every window follows |
| `/et debug` | Toggle diagnostic logging |

Settings live under Esc > Options > AddOns > Enemy Tracker. Changes apply immediately and are saved.

## How it works

| Spec item | Implementation |
|---|---|
| Storage (§2.2) | `EnemyTrackerDB` (account-wide SavedVariables). Names are Forever full names, "First Surname" (each part 2-12 letters), read from both values `UnitName` returns. Keys are case-insensitive with spaces collapsed; `First-Surname` is read as the same name. Cyrillic and Latin-1 are lower-cased correctly. Duplicates are merged on load |
| Detection (§3.1) | Nameplates (`NAME_PLATE_UNIT_ADDED`, rechecked after 0.3 s because the unit can still be empty, plus a scan of `C_NamePlate.GetNamePlates`), target, target-of-target, mouseover, focus, focus-target, group and raid members and their targets (only when `UnitIsVisible`; a member changing target is checked at once via `UNIT_TARGET`) and nearby combat-log events where a player is the source or target |
| Frequency (§3.2) | Events, plus one 1-second `C_Timer` ticker. There's no `OnUpdate` scanning. Unit tokens are pre-built, so the ticker creates no new tables. Blacklist lookup is a single hash lookup |
| De-duplication | A player is counted once across all sources. They count as "lost" after 10 seconds without any source reporting them. If they reappear after that, it's a new detection with a new alert and sound. A shorter gap doesn't re-alert |
| Alerts (§4) | Up to 4 toasts stacked; further alerts queue. Each shows a title, the name and a ✕ button. If the same player reappears while their toast is still open, the toast pulses instead of duplicating. The sound is throttled to once every 2 seconds. Toasts auto-hide after 30 seconds by default (configurable; 0 = never). Alerts and sound are only for the opposing faction: blacklisted players of your own faction stay on the list and are still tracked (last seen, detections, nearby list) without an alert. An unknown faction counts as hostile |
| Click to target (§4) | See the limitations below. A secure macro button runs `/targetexact Name`. Right-clicking the toast closes it |
| Settings (§5) | Visual and sound on/off, alert size (0.5–2.0), sound choice (only sound kits the client defines), sound channel, test sound and test alert buttons, counter and minimap toggles, detection-source toggles, lock and reset position, debug |
| Position (§6) | Unlock mode shows a green drag handle, so normal clicks never drag. Positions are saved in UIParent units, so they survive changes to alert size, UI scale and resolution. Frames are clamped to the screen |
| Description note (plan §5) | When an opposing-faction (or unknown) blacklisted player is detected and has a description, a small note shows it in a screen corner. Options: on/off, corner (bottom right/left, top right/left), size, display time (0 = until clicked), test button. Up to 3 notes stack; the oldest is replaced. Empty descriptions show nothing |
| Red flag (plan §4) | A red flag (`Media/Flag.tga`, generated by `tools/make_flag_tga.lua`) marks blacklisted players of **either** faction: in front of their chat messages (say, yell, emotes, whispers both ways, party, raid, instance, guild, channels) via `ChatFrame_AddMessageEventFilter`, and as a line in their unit tooltip. Hovering the chat flag, or the tooltip line, shows the description. Option: on/off. **Not yet:** party/raid frames and the player search (who) list; see limitations |
| Counter (§7) | "Nemeses nearby: N" counts unique blacklisted players detected right now. Clicking it shows who, the source and seconds since they were last seen. It's hidden when the count is 0, unless frames are unlocked |
| Stats (§8) | Counts kills each way, last seen, date added and detection count, all starting from when the player was added. The kill rules are below |
| Dashboard (§9) | Opened from the minimap button (drag it around the minimap edge). Search by name, add by name or target, sortable columns, a virtual-scroll list (fine with hundreds of entries), clear stats or remove with confirmation, and a scanning toggle. Esc closes it |
| Shared groups | See the section below |
| Modules (§11) | `Core` (events, utilities), `Database`, `Detection`, `Stats`, `Sound`, `Notifications`, `DescriptionNote`, `Flags`, `Groups`, `GroupSync`, `SharedList`, `GroupsPanel`, `Counter`, `Dashboard`, `MinimapButton`, `Options`, `ContextMenu`, `Slash`, `Locale` (English and Russian, both complete; chosen in the options or with `/et lang`, default: the game client's language). All event handlers are wrapped in `pcall`, so one error doesn't break the addon |

## Shared groups

A group pools the lists of everyone in it. Create one, give its ID to people you trust, and each of them joins with that ID. You can be in up to 3 groups.

- **Joining checks the group.** The last character of an ID is a check character, so a typo is rejected at once. Since there is no server, a group exists only while someone is in it: after joining, the addon asks the channel who is there, and if no member answers within 15 seconds it prints "group not found: nobody from it is online" and leaves. So you can join only while at least one member is in the game.
- **No server.** Addons cannot reach the internet, and the project rules out companion programs. A group is a hidden in-game chat channel named after its ID (`ET` + 12 characters); members' addons exchange lists with addon messages on that channel. The channel is removed from every chat window, and groups are rejoined 10 seconds after login so General and Trade keep `/1` and `/2`.
- **What is shared:** the player's name, faction and description, who changed the record last and when. **Not shared:** kill statistics, last seen, detections. Kills and deaths count only for you.
- **No duplicates.** Records are keyed by name like your own list, so a player appears once however many members added them, and once across all your groups. Your own entry always wins; if your description is empty, the newest description a group has is shown.
- **Shared players are watched for like your own**: alerts and sound (opposing faction only), corner note, red flag, nearby counter. They are listed in the dashboard in blue, marked "from a group"; "Add to my list" copies one into your own list.
- **Sync.** When you connect, one online member sends you the group's list and you send back anything they lack; after that every add, description change and removal is sent immediately. Each member keeps a copy, so the list survives while its authors are offline, but you only receive updates while at least one other member is online.
- **Logged messages.** Group messages go out with `SendAddonMessageLogged`, which Blizzard made for player-written text: if someone reports a description, support can see it. The dashboard reminds you to keep descriptions about in-game behaviour, with no insults or personal information.
- **Conflicts:** the latest change wins. An empty description never overwrites a member's text. Removing a player you shared last removes them from the group; removing one someone else shared only removes them from your own list.
- **Protection** (there is no server to rate-limit, so each client protects itself): a per-sender message budget with a 5-minute mute for flooding, one full-list answer per member per minute, at most 2000 players per group, every field validated (name format, faction, time not in the future) and UI escape codes stripped from descriptions. Group creation is limited by the 3-group cap. IDs are random (about 59 bits), so they cannot be guessed, but **anyone who has the ID can read and edit the group**; there are no admins.

## Forever restrictions handling

Forever reportedly applies Retail's Midnight addon restrictions. That's a third-party report of a Blizzard developer-Discord remark, not an official post. The addon is defensive about this:

- **Combat log.** The addon tries to register `COMBAT_LOG_EVENT_UNFILTERED` once. If the client refuses:
  - kill statistics and the combat-log detection source switch off;
  - the dashboard and options say so;
  - nothing else is affected.

  It never tries to read the combat log any other way, such as by parsing the chat tab. `PLAYER_DEAD` is registered separately.
- **Hidden ("secret") values.** Every unit read goes through `ET.PlayerName()`, which treats secret values from `UnitExists`, `UnitIsPlayer` or `UnitName` as "no data" (using `issecretvalue` when the client has it). Hidden names are never compared or stored. Combat-log events with secret GUIDs or flags are skipped.
- **Scan ticker.** The 1-second scan catches its own errors. An unexpected client value logs one debug line instead of producing an error popup every second.

The ban-risk review found no feature that breaks Blizzard's published addon policy or EULA. Everything uses the standard addon API, and the targeting needs your click. Only shared groups send data, and only to members of your groups, using standard addon messages on a chat channel.

## Research findings and limitations (§12)

Interface number, Lua version and menu API come from other Forever addons' public sources (TOC `16001`, Lua 5.1, `Menu.ModifyMenu`). The targeting finding comes from RareScanner's release notes.

1. **No programmatic targeting.** `TargetUnit()` is gone from current Classic-family clients (removed after 1.15.7), and addons can't target from their own code. So each toast has a **secure overlay button** whose click runs `/targetexact Name`. Secure frames can't be shown, hidden or reconfigured during combat. So:
   - When combat starts, the overlays are detached.
   - Alerts raised during combat still appear and play the sound, with the hint *"In combat: click after combat to target"*.
   - The overlays reattach when combat ends.
   - Targeting only works if the player is within the client's targeting range.
2. **"They killed me".** The combat log doesn't name your killer directly. It's counted only when both of these happen within 2 seconds of each other:
   - a damage event from that blacklisted player to you with **overkill > 0** (the killing blow);
   - your death (`PLAYER_DEAD` or `UNIT_DIED` for you).

   **Not counted, because the data is ambiguous:**
   - a hit that was exactly lethal (overkill 0);
   - kills by pets, totems or guardians (the combat log doesn't give their owner);
   - deaths with no logged killing blow.
3. **"I killed them"** counts only `PARTY_KILL` events where you are the source and the blacklisted player is the target. Killing blows by your pet aren't counted.
4. **Sound volume.** WoW can't set the volume of a single sound. Instead of a fake slider, there's a **sound channel** choice. The options panel shows that channel's current effective volume, which you change in the game's sound settings.
5. **Minimap.** Ordinary players don't show on the minimap in a way addons can read, and Classic-family clients don't have vignettes. So the minimap isn't a detection source.
6. **Range.** Detection is limited to what the client reports: nameplate range (the `nameplateMaxDistance` setting), your target, mouseover, group targets and combat-log range. The addon never claims full-zone coverage. There's no world scan and no workaround for client limits.
7. **Right-click menu.** This uses `Menu.ModifyMenu`. If a client doesn't have it, the menu entry is skipped and `/et add` (target) is the fallback. The legacy `UnitPopup` hooks aren't used, because they taint the menu.
8. **Adding your current target** detects them right away, if they're in range, so you get an alert immediately. That's expected.
9. Scope: data is shared across your account. Statistics count kills by whichever of your characters is logged in.
10. **Red flag coverage.** Chat and unit tooltips use documented, taint-free hooks. Party/raid frames and the who list are Blizzard frames whose name text is (or may be) a hidden value on Forever; changing them needs in-game verification first, so they are not flagged yet. The chat flag is an `addon:` hyperlink; if a Forever build does not support that link type, clicking it may do nothing.
11. **Checking that a typed name exists.** Forever has no global player search, and `/who` only lists players of your own faction, so enemies cannot be looked up. A typed name is confirmed only if the client reported that player during this session (units, nameplates, group, chat authors); otherwise the addon asks before adding it. Adding your target or from the right-click menu needs no check.
12. **Shared groups are unverified on Forever.** They rely on `JoinTemporaryChannel` and `C_ChatInfo.SendAddonMessageLogged` (falling back to `SendAddonMessage`) on a `CHANNEL`, which exist in the Forever API dump, but the channel's arguments in `CHAT_MSG_ADDON` and the server's throttling have not been observed in game. Sending waits only while `InChatMessagingLockdown` is true. `AreOutgoingAddonChatMessagesRestricted` is ignored: on Forever it stays true while messages go through. A message the server refuses for flooding or lockdown (results 3, 8, 11) stays in the queue and is retried. Messages are paced under the per-prefix limit (a burst of 8, then 0.9 per second), and a change you just made goes ahead of a whole-list upload. If the client has no free chat channel slot, joining fails with a message.

## Tests

Requires [LuaJIT](https://luajit.org/) (Lua 5.1 compatible, like the game client; on Windows `winget install DEVCOM.LuaJIT`). From the repository root:

```bash
luajit tests/run_tests.lua            # all specs
luajit tests/run_tests.lua detection  # only tests whose name contains "detection"
```

- `tests/wowmock.lua` mocks the WoW: Forever client API. It follows what is known about Forever: `UnitName` returns first name and surname, there is no `CombatLogGetCurrentEventInfo`, and `issecretvalue` exists.
- `tests/harness.lua` boots the addon in a fresh mock environment the way the client does (TOC order, SavedVariables, `ADDON_LOADED`, `PLAYER_LOGIN`) and fails a test if the addon swallowed any error.
- Each `tests/*_spec.lua` returns a list of `{ "name", function() ... end }`.

The mock can't prove rendering, real secure-template behaviour or real event payloads.

## In-game acceptance checklist (§14)

1. `/reload` with an empty blacklist, then with a big one: no Lua errors (turn on `/console scriptErrors 1`).
2. `/et add Name`, `/et add` on a target, and right-click a target portrait and a name in chat. All three should add the player.
3. Restart the game: the list, stats, settings and positions are all still there.
4. A blacklisted player comes into nameplate range: one toast and one sound, and the counter goes up by 1. Nothing repeats while they stay visible.
5. They leave for more than 10 seconds and come back: a new alert.
6. Click the toast out of combat and they become your target. Do the same during combat: the hint text changes, and the click works after combat.
7. ✕ closes the toast; right-click also closes it. `/et unlock`, drag, `/et lock`, `/reload`: the position is kept. The size slider resizes the toast without a reload.
8. Several blacklisted players at once: separate toasts, then queued ones when all four slots are full. The counter shows the unique count.
9. Kill a blacklisted player: "I killed" +1. Get killed by one: "Killed me" +1. Run `/et debug` to see the lethal-hit log lines.
10. Dashboard: search, sort, clear stats (list entry and "last seen" kept), remove (with confirmation).
11. With `/et debug` on, check that nothing is logged every frame while idle.
12. Groups, with a friend: you `/et group create`, they join with the ID. Within ~10 seconds each sees the other's players in the dashboard (blue). `/et debug` logs "group ready" and the channel number. The channel does not appear in chat, and `/1` and `/2` are still General and Trade after a relog.
13. Add a player and change a description while both are online: the friend sees it within a few seconds. Log out, add someone, log back in: it reaches them after the reconnect.
14. A shared opposing-faction player comes into range: alert, note and flag as for your own.
