# Enemy Tracker (WoW Forever)

Addon for **WoW Forever (Camelot, interface 16001)**. You keep a personal blacklist of players. The addon detects them nearby using only data the client already provides, alerts you with a RareScanner-style toast and a sound, counts how many are nearby right now, and keeps kill statistics for each player. A minimap button opens the dashboard.

**Status:** I wrote this from the spec and checked it only against a mock WoW API (102 automated checks) and a Lua 5.1 compile pass. **It has not been run in the WoW Forever client yet.** The spec says a feature isn't done until it's verified in the game, so use the in-game checklist below.

## Install

Copy the `EnemyTracker/` folder into `World of Warcraft/_forever_/Interface/AddOns/` (or whichever folder your Forever client uses for AddOns). Then enable it on the character select screen.

Turn on **enemy nameplates** (`V`, or Options > Interface > Names). Nameplates are the main detection source.

## Usage

| Command | Action |
|---|---|
| `/et add First Surname` | Add a player by full name (also `First-Surname`) |
| `/et add` | Add your current target (also `/et addtarget`) |
| Right-click a player | Add to / remove from Enemy Tracker. Works on unit frames, target frame, party/raid frames and names in chat |
| `/et remove First Surname` | Remove a player, after confirmation. Deletes their stats too |
| `/et clear First Surname` | Reset kill stats, after confirmation. The player stays in the list and "last seen" is kept |
| `/et list` | Print the blacklist |
| `/et show` | Open or close the dashboard (or left-click the minimap skull) |
| `/et on`, `/et off`, `/et toggle` | Turn scanning on or off. It's on by default |
| `/et unlock`, `/et lock` | Move the alert anchor and the counter |
| `/et resetpos` | Reset frame positions |
| `/et test` | Show a test alert |
| `/et options` | Open settings (or right-click the minimap button) |
| `/et debug` | Toggle diagnostic logging |

Settings live under Esc > Options > AddOns > Enemy Tracker. Changes apply immediately and are saved.

## How it works

| Spec item | Implementation |
|---|---|
| Storage (§2.2) | `EnemyTrackerDB` (account-wide SavedVariables). Names are Forever full names, "First Surname" (each part 2-12 letters), read from both values `UnitName` returns. Keys are case-insensitive with spaces collapsed; `First-Surname` is read as the same name. Cyrillic and Latin-1 are lower-cased correctly. Duplicates are merged on load |
| Detection (§3.1) | Nameplates (`NAME_PLATE_UNIT_ADDED` plus a scan of `C_NamePlate.GetNamePlates`), target, target-of-target, mouseover, focus, group members' targets (only when `UnitIsVisible`) and nearby combat-log events where a player is the source or target |
| Frequency (§3.2) | Events, plus one 1-second `C_Timer` ticker. There's no `OnUpdate` scanning. Unit tokens are pre-built, so the ticker creates no new tables. Blacklist lookup is a single hash lookup |
| De-duplication | A player is counted once across all sources. They count as "lost" after 10 seconds without any source reporting them. If they reappear after that, it's a new detection with a new alert and sound. A shorter gap doesn't re-alert |
| Alerts (§4) | Up to 4 toasts stacked; further alerts queue. Each shows a title, the name and a ✕ button. If the same player reappears while their toast is still open, the toast pulses instead of duplicating. The sound is throttled to once every 2 seconds. Toasts auto-hide after 30 seconds by default (configurable; 0 = never) |
| Click to target (§4) | See the limitations below. A secure macro button runs `/targetexact Name`. Right-clicking the toast closes it |
| Settings (§5) | Visual and sound on/off, alert size (0.5–2.0), sound choice (only sound kits the client defines), sound channel, test sound and test alert buttons, counter and minimap toggles, detection-source toggles, lock and reset position, debug |
| Position (§6) | Unlock mode shows a green drag handle, so normal clicks never drag. Positions are saved in UIParent units, so they survive changes to alert size, UI scale and resolution. Frames are clamped to the screen |
| Counter (§7) | "Nemeses nearby: N" counts unique blacklisted players detected right now. Clicking it shows who, the source and seconds since they were last seen. It's hidden when the count is 0, unless frames are unlocked |
| Stats (§8) | Counts kills each way, last seen, date added and detection count, all starting from when the player was added. The kill rules are below |
| Dashboard (§9) | Opened from the minimap button (drag it around the minimap edge). Search by name, add by name or target, sortable columns, a virtual-scroll list (fine with hundreds of entries), clear stats or remove with confirmation, and a scanning toggle. Esc closes it |
| Modules (§11) | `Core` (events, utilities), `Database`, `Detection`, `Stats`, `Sound`, `Notifications`, `Counter`, `Dashboard`, `MinimapButton`, `Options`, `ContextMenu`, `Slash`, `Locale` (English and Russian). All event handlers are wrapped in `pcall`, so one error doesn't break the addon |

## Forever restrictions handling (v0.1.1)

Forever reportedly applies Retail's Midnight addon restrictions. That's a third-party report of a Blizzard developer-Discord remark, not an official post. The addon is defensive about this:

- **Combat log.** The addon tries to register `COMBAT_LOG_EVENT_UNFILTERED` once. If the client refuses:
  - kill statistics and the combat-log detection source switch off;
  - the dashboard and options say so;
  - nothing else is affected.

  It never tries to read the combat log any other way, such as by parsing the chat tab. `PLAYER_DEAD` is registered separately.
- **Hidden ("secret") values.** Every unit read goes through `ET.PlayerName()`, which treats secret values from `UnitExists`, `UnitIsPlayer` or `UnitName` as "no data" (using `issecretvalue` when the client has it). Hidden names are never compared or stored. Combat-log events with secret GUIDs or flags are skipped.
- **Scan ticker.** The 1-second scan catches its own errors. An unexpected client value logs one debug line instead of producing an error popup every second.

The ban-risk review found no feature that breaks Blizzard's published addon policy or EULA. Everything uses the standard addon API, the targeting needs your click, and nothing is sent to other players.

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
