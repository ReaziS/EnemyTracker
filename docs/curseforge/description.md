# CurseForge project page

Paste into the project settings on CurseForge. Not part of the addon.

- **Name:** Enemy Tracker
- **Summary:** Warns you when players you marked are nearby, keeps notes on them, and lets friends share their lists.
- **Category:** PvP (also: Chat & Communication, Combat)
- **Game version / flavor:** 1.60.1, Forever
- **License:** MIT
- **Source:** https://github.com/ReaziS/EnemyTracker
- **Avatar:** `docs/curseforge/avatar.png` (400×400, the "ET" monogram, made by `tools/make_avatar.ps1`)

---

## Description

**Enemy Tracker** is a world PvP awareness addon for **WoW Forever**. Mark players who keep ganking you, and the addon tells you when one of them shows up nearby, so you are never caught by surprise.

### Features

- **Personal list of players.** Add your target with `/et add`, by name with `/et add First Surname`, or from the right-click menu on a player or a name in chat.
- **Warns you when they are nearby.** It uses only what the game already shows you: nameplates, your target, mouseover, focus, and your group members' targets. When a listed player is seen, you get an on-screen alert with a sound. Click the alert to target them (outside combat).
- **Who raises an alert is up to you.** Choose enemies only (the default), everyone, or nobody. Players of your own faction can stay on your list and are still marked, but stay quiet.
- **Nearby counter.** Shows how many listed players are around right now. Open the list and click a name to target that player.
- **Notes.** Write a short description of each player ("camps the flight master"). It is shown in a small corner note when they are detected.
- **Red flag.** Listed players are marked with a red flag in chat and in their tooltip.
- **Kill statistics,** when the game lets addons read the combat log. On Forever it currently does not, so this part is switched off there.
- **Shared lists with friends.** Create a group and give its ID to people you trust. Members' lists are combined automatically over a hidden chat channel. No server or website is involved. Only the name, faction and description of listed players are shared; your statistics are not.
- **English and Russian.**

### Getting started

1. Turn on **enemy nameplates** (`V`). They are the main way players are detected.
2. Open the dashboard with the minimap button or `/et show`.
3. Add players, and change the alert options in Options > AddOns > Enemy Tracker.

### Commands

| Command | Action |
|---|---|
| `/et show` | Open the dashboard |
| `/et add` / `/et add First Surname` | Add your target / a player by name |
| `/et remove First Surname` | Remove a player |
| `/et note First Surname text` | Set a player's description |
| `/et group` | Open the groups window |
| `/et group create` / `join ID` / `leave ID` | Manage shared groups |
| `/et on` / `/et off` | Turn detection on or off |
| `/et unlock` / `/et lock` | Move the alerts and the counter |

### Notes

- Made for WoW Forever (interface 16001).
- Detection uses only data the game client gives to every addon. It does not scan the world, and it cannot see players the game does not show you.
- Everyone in a group needs the same version of the addon for lists to sync.
- Bugs and ideas: https://github.com/ReaziS/EnemyTracker/issues

---

## Описание (русский)

**Enemy Tracker** — аддон для **WoW Forever**, который предупреждает о PvP-опасности в открытом мире. Отмечайте игроков, которые вас постоянно ганкают, и аддон сообщит, когда кто-то из них окажется рядом.

- **Личный список игроков.** Добавляйте цель (`/et add`), игрока по имени (`/et add Имя Фамилия`) или через меню правой кнопки мыши.
- **Предупреждение, когда они рядом.** Используются только данные, которые игра и так показывает: таблички над головой, цель, наведение мыши, фокус, цели участников группы. Всплывает уведомление со звуком; клик по нему берёт игрока в цель (вне боя).
- **Кого оповещать, выбираете вы:** только враги (по умолчанию), все или никто. Игроки своей фракции в списке помечаются, но тревоги не поднимают.
- **Счётчик «рядом».** Сколько отмеченных игроков поблизости; клик по имени в списке берёт игрока в цель.
- **Заметки** о каждом игроке, которые показываются в углу экрана при обнаружении.
- **Красный флажок** у отмеченных игроков в чате и в подсказке.
- **Статистика убийств** — если игра даёт аддонам журнал боя. На Forever сейчас не даёт, поэтому там она выключена.
- **Общие списки с друзьями.** Создайте группу и дайте её ID тем, кому доверяете: списки участников объединяются автоматически через скрытый канал чата, без серверов и сайтов. Передаются только имя, фракция и описание игрока; ваша статистика не передаётся.
- **Английский и русский язык.**

Включите таблички врагов (`V`) — это основной способ обнаружения. Всем участникам группы нужна одна и та же версия аддона.
