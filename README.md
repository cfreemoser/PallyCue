# PallyCue

<img src="icon.png" alt="PallyCue" width="160" />

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
- Type `/pc` for setup. When **Hide if healthy** is on, the HUD disappears completely while buffs are up (in and out of combat). Rebuff still works from the keybind or `/click` macro.
- `/pallycue` or `/pc` opens setup. `/pc reset` recenters the frame.

## Defaults

- Melee → Blessing of Might
- Casters → Blessing of Wisdom
- Tanks (role, main tank, or Righteous Fury) → Blessing of Kings
- Watches your own Righteous Fury, last-seen Aura, and last-seen Seal
- Self-buff warning at 5s remaining (cycle 0 / 5 / 10 / 15 / 20 / 30 in setup; 0 = missing only)
- Optional tank aggro alert (off by default): if you are tanking, warns when a non-tank group member has aggro and keeps that event on the HUD until it drops
- **Watch target** (on by default): include a friendly target, focus, or mouseover who is not in your group. Uses a single blessing, not Greater. If nobody is selected, Rebuff applies that blessing to you. Group members who actually need a buff stay first.
- **Show HUD** is off by default (macro-only). Turn it on in `/pc` if you want the on-screen button.

Vanilla / TBC / Wrath Classic. Paladin only.

## CurseForge packaging

Releases are built by [CurseForge automatic packaging](https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging) from this repo.

1. Create the project on CurseForge if it does not exist yet.
2. Generate an API token at [curseforge.com/account/api-tokens](https://www.curseforge.com/account/api-tokens).
3. In GitHub: **Settings → Webhooks → Add webhook**.
   - Payload URL: `https://www.curseforge.com/api/projects/{projectID}/package?token={token}`
   - Content type: `application/json`
   - Events: **Just the `push` event**
4. Publish by pushing a git tag:
   - `1.0.1` → release
   - `1.0.1-beta` → beta
   - `1.0.1-alpha` → alpha

`{projectID}` is the numeric ID in **About This Project** on the CurseForge overview. Untagged commits package as alpha only if the project is set to package every commit.

The packaged zip uses `@project-version@` from the tag (see `.pkgmeta`).

## License

[MIT](LICENSE)
