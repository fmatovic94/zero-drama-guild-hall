# ZERO DRAMA — Guild Hall

A Horde guild hall addon for **World of Warcraft Forever** (Interface **16001**). It opens an expanded native-style guild window with guild and officer chat, a sortable roster, live member positions on the map, calls for backup, a guild dungeon finder, guild material/gold requests, polls and more.

Current version: **0.19.0-beta** · [CurseForge](https://www.curseforge.com/wow/addons/zero-drama-guild-hall) · [Discord](https://discord.gg/3zQVrNWTm)

## Features

- **Announcements:** the guild message of the day and guild information. Editing follows the real guild permissions.
- **Guild and officer chat:** conversation-style chat with class-colored names, rank badges and saved history (newest 500 messages per channel).
- **Roster:** sortable by name, level, class, rank, area and status, with search, an online-only filter, member details and a marker for members who run the addon.
- **Army map:** live, self-reported positions of guild members on the world map (Blizzard map and OpenMap). Sharing can be turned off with **Share my live location**.
- **Request Army!:** drop a rally point that alerts every online addon user until the caller or an officer cancels it. Guildmates answer from the popup: **I'm on my way** posts an automatic guild chat message and follows the caller's live position on the map for 30 minutes; **I'm busy** hides the alerts for that call.
- **Dungeon finder:** find guild members for dungeon groups.
- **Requests / Guild Needs:** post the profession mats or gold you need (gold needs a reason). Guildmates see them in a small, movable **Guild Needs** window (`/zd needs`) and in a panel at the mailbox, where **Fill** prepares the mail and the gift is recorded after sending.
- **Guild bank, polls, warnings and insignia:** bank item records where available, officer polls, yellow-card warnings and custom rank badges.

## Install

1. Exit WoW.
2. Extract the release zip into `Interface/AddOns/`. The final path must be `Interface/AddOns/NO_DRAMA/NO_DRAMA.toc`.
3. Enable **ZERO DRAMA | Guild Hall** on the character selection AddOns screen.

Or install it with the CurseForge app.

## Commands

- `/zd` or `/zerodrama` (also `/nd`, `/nodrama`): toggle the guild hall
- `/zd needs`: show or hide the Guild Needs window
- `/zd testpopup`: preview the dungeon finder popup
- `/zd testarmy`: preview the Request Army popup (nothing is sent)
- `/ndreset`: reset window and button positions

## How it works

All addon features talk over the `NODRAMA1` guild addon-message prefix. Each client only sends its own data, and receivers check that the sender is in the current guild. Nothing is sent outside the game; the addon does not connect to Discord or the internet.

WoW Forever reports `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` as `true` even though guild addon messages are delivered, so the addon only stops sending during an actual chat lockdown.

| File | Purpose |
| --- | --- |
| `Core.lua` | Saved data, roster, messaging queue and message routing |
| `Groups.lua` | Dungeon finder |
| `Needs.lua` | Guild requests, the Guild Needs window and request forms |
| `NeedsMail.lua` | Mailbox Guild Needs panel and auto-fill |
| `Army.lua` | Request Army! calls and alerts |
| `Tracking.lua` | Live location sharing |
| `LiveMap.lua` | Map pins for Blizzard map and OpenMap |
| `UI.lua` | The guild hall window and pages |

## Contributing

Bug reports and pull requests are welcome. Please keep in mind WoW's Lua 5.1 limits (60 upvalues per function, 200 locals per chunk) and test in the Forever client with `/console scriptErrors 1`.

## License

[MIT](LICENSE.txt). World of Warcraft and its interface assets belong to Blizzard Entertainment; this project is not affiliated with Blizzard.
