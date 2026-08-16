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
- Type `/pc` for setup. When **Hide if healthy** is on, the HUD disappears completely while buffs are up.
- `/pallycue` or `/pc` opens setup. `/pc reset` recenters the frame.

## Defaults

- Melee → Blessing of Might
- Casters → Blessing of Wisdom
- Tanks → Blessing of Kings
- Watches your own Righteous Fury, last-seen Aura, and last-seen Seal
- Self-buff warning at 5s remaining (cycle 0 / 5 / 10 / 15 / 20 / 30 in setup; 0 = missing only)
- Optional tank aggro alert (off by default): if you are tanking, warns when a non-tank group member is targeted by an enemy

Vanilla / TBC / Wrath Classic. Paladin only. If PallyPower is enabled, PallyCue hides so the two AutoBuff buttons do not fight.
