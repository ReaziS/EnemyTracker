# Changelog

## 0.4.0

- **Alert about:** choose who raises alerts: enemies only (default), everyone, or nobody. Players of your own faction on your list are still tracked and flagged, but stay quiet with "enemies only".
- **New look:** flat, minimal style for the dashboard, groups window, alerts, description notes and the nearby counter.
- **Nearby list:** click a name in the counter's list to target that player (outside combat).
- **Groups:**
  - Joining and messaging work on Forever.
  - New members receive the whole shared list, and lists that missed each other catch up within minutes, without a reload.
  - Only the member who added a player can remove them from the group; anyone else removes them only from their own list.
  - The groups window shows how many players are on the shared list and how many members are online.
  - `/et group debug` prints what is needed to find connection problems.
- **Language:** choose English or Russian in the options or with `/et lang`.

All members of a group need this version: older versions do not understand the new shared record format.

## 0.3.0

- Shared groups: friends pool their lists over a hidden chat channel, without any server.
- The dashboard lists players shared by your groups and can copy one into your own list.

## 0.2.0

- One description per player, shown in a corner note when they are detected.
- Red flag next to listed players in chat and unit tooltips.
- Alerts only for the opposing faction.
- Group members, their targets and the focus target as detection sources.
- Typed names are confirmed against players seen this session.
- Saved data moved to a versioned format (upgraded automatically from 0.1.1).

## 0.1.1

- First version: personal blacklist, nearby detection, alerts with sound, nearby counter, kill statistics, minimap button.
