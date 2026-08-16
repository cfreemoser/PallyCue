# PallyCue

Minimal paladin blessing companion for **Steam Deck / ConsolePort**.

Silent when everyone is buffed. Flashes when someone loses a blessing. One large **Rebuff** button (and one keybind) casts the next missing or expiring buff.

Not a PallyPower replacement for raid assignment leads.

## Install

1. Copy the `PallyCue` folder into `World of Warcraft/_classic_/Interface/AddOns/`
   (or `_classic_era_` / `_classic_tbc_`).
2. Restart the client and enable **PallyCue**.
3. Bind **PallyCue → Rebuff** to a Steam Deck paddle or ConsolePort extra.

## Use

- Red / yellow cluster = something needs a buff. Press Rebuff (or tap the icon).
- Green pip = all clear. Click the pip or type `/pc` for setup.
- `/pallycue` or `/pc` opens setup. `/pc reset` recenters the frame.

## Defaults

- Melee → Blessing of Might
- Casters → Blessing of Wisdom
- Tanks → Blessing of Kings
- Watches your own Righteous Fury, last-seen Aura, and last-seen Seal

Vanilla / TBC / Wrath Classic. Paladin only. If PallyPower is enabled, PallyCue hides so the two AutoBuff buttons do not fight.
