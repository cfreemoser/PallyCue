# PallyCue

Minimal paladin blessing companion for **Steam Deck / ConsolePort**.

Silent when everyone is buffed. Flashes when someone loses a blessing. One large **Rebuff** button (and one keybind) casts the next missing or expiring buff.

Not a PallyPower replacement for raid assignment leads.

## Install

1. Copy the `PallyCue` folder into `World of Warcraft/_classic_/Interface/AddOns/`
   (or `_classic_era_` / `_classic_tbc_`).
2. Restart the client and enable **PallyCue**.
3. Bind **PallyCue → Rebuff** to a Steam Deck paddle or ConsolePort extra.
   A bar macro also works: `/click PallyCueRebuff LeftButton 1` (do not type this in chat).

## Use

- Red / yellow cluster = something needs a buff. Press Rebuff (or tap the icon).
- Green pip = all clear. Click the pip or type `/pc` for setup.
- `/pallycue` or `/pc` opens setup. `/pc reset` recenters the frame.

## Defaults

- Melee → Blessing of Might
- Casters → Blessing of Wisdom
- Tanks → Blessing of Kings
- Watches your own Righteous Fury, last-seen Aura, and last-seen Seal
- Optional tank aggro alert (off by default): if you are tanking, warns when a non-tank group member is targeted by an enemy
- **Watch target** (on by default): include a friendly target, focus, or mouseover who is not in your group. Uses a single blessing, not Greater. If nobody is selected, Rebuff applies that blessing to you. Group members who actually need a buff stay first.
- **Show HUD** is off by default (macro-only). Turn it on in `/pc` if you want the on-screen button.

Vanilla / TBC / Wrath Classic. Paladin only. If PallyPower is enabled, PallyCue hides so the two AutoBuff buttons do not fight.
