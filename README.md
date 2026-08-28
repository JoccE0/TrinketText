# TrinketText

![TrinketText](logo.png)

A lightweight World of Warcraft addon that shows a **changeable on‑screen message when an equipped trinket comes off cooldown**.

- **Interface:** `120100` (WoW 12.1)
- **Version:** 1.4.2
- **Saved variables:** `TrinketTextDB` (account‑wide)
- **Slash commands:** `/tt` or `/trinkettext`

---

## Installation

1. Copy the `TrinketText` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
   so that `Interface/AddOns/TrinketText/TrinketText.toc` exists.
2. Fully restart the client (or `/reload` if it was already running).
3. Enable **TrinketText** in the AddOns list on the character select screen. If it is
   flagged out of date, tick **Load out of date AddOns**.

---

## How it works

Every 0.2 seconds the addon checks trinket slots 13 and 14. A trinket is considered
**on cooldown** when either of these is true:

| Source | Notes |
| --- | --- |
| `GetInventoryItemCooldown` | Plain item cooldown. Durations shorter than `threshold` or longer than 1 hour (e.g. Ruby Whelp Shell's daily whelp‑training timer) are ignored. |
| `C_Spell.GetSpellCooldown().isActive` | For trinkets whose cooldown lives on their *use spell* rather than the item. The cooldown numbers are "secret" values in 12.1, so only the boolean flag is read. |

The trinket's use‑spell is resolved once from its item link and cached, so the result
does not flicker between polls.

### Display modes

- **Flash (default):** the message fades in, holds for `time` seconds, then fades out —
  once, the moment a trinket goes from on‑cooldown to ready.
- **Permanent:** the message stays on screen the entire time a watched on‑use trinket is
  ready, and disappears as soon as it is used again. Enable with `/tt permanent on`.
  Passive/stat trinkets (no use effect) are ignored in this mode so the text is not
  shown forever.

When `%s` appears in the message it is replaced with the trinket's name. A message with
no `%s` is shown verbatim.

---

## Commands

Type `/tt` with no arguments to print the current settings and this list.

| Command | Description | Default |
| --- | --- | --- |
| `/tt` | Show current settings and help | — |
| `/tt test` | Preview the message | — |
| `/tt debug` | Print what the API reports for each trinket slot (item CD, `spell.isActive`, final `onCD` verdict) | — |
| `/tt unlock` / `/tt lock` | Show a draggable box to reposition the text, then lock it | locked |
| `/tt reset` | Reset the text position to default (centre, +200 y) | — |
| `/tt text <message>` | Set the message. Use `%s` for the trinket name | `%s is ready!` |
| `/tt size <8-72>` | Font size | `34` |
| `/tt time <1-30>` | Seconds the message stays on screen (flash mode) | `3` |
| `/tt color <r> <g> <b>` | Text colour, 0–1 each (e.g. `1 0.82 0`) | `1 0.82 0` (gold) |
| `/tt threshold <sec>` | Ignore cooldowns shorter than this | `20` |
| `/tt combat on\|off` | Only show the message while in combat | `off` |
| `/tt sound on\|off` | Play a ready‑check sound with the message | `off` |
| `/tt permanent on\|off` | Keep the text up the whole time a trinket is ready (alias: `/tt sticky`) | `off` |
| `/tt slot both\|1\|2` | Which trinket slot to watch (`1` = top, `2` = bottom) | `both` |

### Colour examples

| Colour | Command |
| --- | --- |
| Gold | `/tt color 1 0.82 0` |
| Hot pink | `/tt color 1 0.08 0.58` |
| Pink | `/tt color 1 0.41 0.71` |
| Pastel pink | `/tt color 1 0.75 0.8` |
| Red | `/tt color 1 0 0` |
| Green | `/tt color 0 1 0` |
| Cyan | `/tt color 0 1 1` |

---

## Troubleshooting

**Nothing shows when the trinket comes off cooldown**
Run `/tt debug` right after using the trinket. Check the `onCD` line:
- If `onCD=true` while the trinket is actually ready, the cooldown source is wrong for
  that trinket — note the `itemCD` and `spell.isActive` values.
- If the trinket has a short cooldown, lower the filter: `/tt threshold 10`.

**Text shows while the trinket is on cooldown (permanent mode)**
Usually caused by a second trinket with no use effect, or a trinket whose cooldown the
API does not report. Pin the addon to the one you care about with `/tt slot 1` or
`/tt slot 2`.

**Message appears in the wrong place**
`/tt unlock`, drag it, `/tt lock`. `/tt reset` restores the default position.

**Wiped my settings**
Delete `WTF/Account/<account>/SavedVariables/TrinketText.lua` while logged out to start
fresh.

---

## Files

| File | Purpose |
| --- | --- |
| `TrinketText.toc` | Addon manifest (interface version, saved variables, icon) |
| `TrinketText.lua` | All logic — display frame, cooldown tracking, slash commands |
| `README.md` | This document |
| `icon.tga` | 64×64 addon icon used in‑game (`## IconTexture`) |
| `icon.svg` / `icon-*.png` | Source icon and PNG exports |
| `logo.svg` / `logo.png` | Project wordmark |

### Regenerating the artwork

The SVGs are the source. To re-export after editing:

```sh
rsvg-convert -w 512 -h 512 icon.svg -o icon-512.png
rsvg-convert -w 2240 logo.svg -o logo.png
magick icon-512.png -resize 64x64 -background none -alpha on \
  -type TrueColorMatte -compress none TGA:icon.tga
```

If the in‑game icon appears upside down, add `-flip` to the `magick` command.
