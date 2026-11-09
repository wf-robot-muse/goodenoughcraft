# GoodEnoughCraft

A first-person voxel sandbox game built on **Godot 4.7** with **Voxel Tools**
(Zylann's `godot_voxel` 1.7 GDExtension), seeded from the `godot-foundation`
project and built/exported entirely by GitHub Actions. Original code, art,
and audio throughout — no assets from any other game.

**Phase 2 (v0.2.0): the full game shell.** A title screen with an
animated block-built logo, named player profiles with unlimited worlds and
save slots, per-user settings and fully remappable controls (keyboard,
mouse, and gamepad), a textured world with biomes, caves, ores, and water,
procedural sound effects and ambient music, a flashlight for the dark, and
profile export/import for backups and syncing.

**v0.2.1: title and controller fixes (from hands-on testing).**
- New title flow: a minimal front screen (**Start** / **Settings**) opens
  a home card with one-click **Continue** (resumes the last played
  profile/world/slot), a Play button per world, and profile chips.
  Rename/delete/export/import live under **Manage profiles & worlds…**.
  The logo's letters use a saturated block palette and the title camera
  sits closer, so the logo reads bigger and punchier against the fog.
- Gamepad: every menu is button-driven with focus set on open, so pad
  navigation works everywhere; a safety net re-focuses if focus is ever
  lost. Name fields open an **on-screen keyboard** when the last input
  device was a gamepad. Settings shows a **"Last gamepad input"**
  readout, and saved bindings can no longer strip an action's gamepad
  events (defaults are restored alongside partial rebinds).
- Gamepad mining/placing is now exactly **one press = one block** (a
  single trigger pull used to repeat ~3 times); mouse hold-to-repeat
  continues at a slower rate.

## Profiles, worlds, and saves

- The title screen manages **profiles**: create, rename, or delete a named
  user. Each profile holds **several worlds** (name + numeric or text
  seed), and each world holds **multiple named save slots**. There is no
  cap on any of them.
- Saves use a versioned format (`manifest.json`, save format 2) stored
  under the game's user data (Godot `app_userdata/GoodEnoughCraft`), laid
  out as `users/<id>/worlds/<world>/slots/<slot>/`. They are designed to
  survive game updates and patches; deleting a profile, world, or slot
  from the title screen removes exactly that data.
- **Export / import:** from the title screen, export any profile to a
  single `.zip` (settings + all worlds + all slots) and import one back —
  the import always lands as a *new* profile, so nothing is overwritten.
- **Sync folder:** set a folder in Settings (a cloud-drive folder, USB
  stick, network share, or a folder inside a git repo all work) and the
  game refreshes `GoodEnoughCraft-<name>.zip` there after every save.
  Import that zip on the title screen of another machine to move a
  profile. The zip contains a `manifest.json` header (`format:
  goodenoughcraft-profile`) plus the profile's folder tree.

## Controls

Every binding below is remappable in **Settings** (title screen or the
in-game pause menu), per profile, including gamepad buttons and sticks.
Defaults:

| Action | Keyboard / mouse | Gamepad (Xbox-style) |
| --- | --- | --- |
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump / swim up | Space | A |
| Sprint | Shift | Left stick press |
| Fly toggle | F | Y |
| Fly up / down | Space / Ctrl | Right / left shoulder |
| Flashlight | L | Right stick press |
| Mine | Left click | Right trigger |
| Place block | Right click | Left trigger |
| Select block | 1–0 keys, mouse wheel | D-pad left / right |
| Pause | Esc | Start |

Menus are fully navigable with the gamepad (D-pad / stick + A). Typing
names (profiles, worlds, slots) uses the keyboard. In-game, **Esc**
pauses: resume, settings, save now, or quit to title. Creative-style for
now: every block type is available in unlimited quantity.

## The world

- Textured blocks from a procedurally generated atlas
  (`tools/make_atlas.py` → `assets/textures/atlas.png`): grass, dirt,
  stone, cobblestone, log, planks, leaves, sand, brick, glass, snow grass,
  cactus, water, and coal / iron / gold ores — 17 block types in
  `scripts/blocks.gd`. The hotbar holds 10.
- Terrain (`scripts/terrain_generator.gd`): rolling hills with three
  **biomes** (plains, desert, snow) from a temperature noise field,
  beaches and **water** filling lowlands to sea level (you can swim),
  **caves** carved by 3D noise, **ores** scattered in the stone layer,
  trees in the plains and snow, cacti in the desert.
- Day/night cycle (10 minutes). The **flashlight** (L) is a spotlight
  from the player's view for nights and caves.
- Worlds save automatically (region files per slot; autosave every 30 s,
  on pause, and on exit) and player state (position, selection, time of
  day, flashlight) with them.

## Audio

All audio is synthesized by `tools/make_audio.py` — no samples: digging /
breaking / placing / footsteps / splash / UI clicks, plus an original
72-second ambient music loop (slow chord pads and a sparse pentatonic
melody). Music and sound-effect volumes are separate per-profile settings.

## Project layout

- `scripts/game.gd` — the `Game` autoload: profiles/worlds/slots, settings
  and input bindings, audio buses and playback, zip export/import, sync
- `scripts/title.gd` / `scripts/title_generator.gd` — title screen UI and
  the floating island with the block-letter logo
- `scripts/main.gd` — game scene: environment + day/night, terrain with
  its save stream, spawn/resume, pause menu, autosave
- `scripts/player.gd` — first-person controller: walk/jump/swim/fly,
  mine/place via `VoxelTool` raycast, flashlight, gamepad look
- `scripts/blocks.gd` — block registry and textured blocky library
- `scripts/terrain_generator.gd` — the terrain generator described above
- `scripts/settings_ui.gd` / `scripts/pause_menu.gd` / `scripts/hud.gd` —
  settings panel, pause menu, in-game HUD
- `scripts/smoke_test.gd` — headless CI check: profile round-trip, terrain
  streaming, player landing, edit round-trip, ore + cave + water presence,
  and a save/reload persistence check
- `tools/` — asset generators (atlas, audio, icon)
- `addons/zylann.voxel/` — Voxel Tools 1.7, vendored exactly as released
- `.github/workflows/godot.yml` — CI: import, smoke test, export all platforms

## Building

Pushes to `main` run the workflow: it downloads Godot 4.7.2 and the export
templates, imports the project, runs the smoke test, and exports
**Windows, Linux, macOS, and a signed release Android APK** as artifacts named
`goodenoughcraft-windows`, `goodenoughcraft-linux`, `goodenoughcraft-macos`,
`goodenoughcraft-android`. Release builds are attached to GitHub Releases.

Notes inherited from the foundation:

- The Android build is a **release APK signed with one fixed keystore**
  (repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), so every build carries
  the same signature and installs over the previous one. The release
  export also packs the correct `template_release` Voxel Tools libraries
  (the addon ships no `template_debug` libraries, which is why debug
  exports packed the editor variants). The same signed APK runs on
  Android and on 64-bit **Fire OS 7/8** tablets (e.g. Fire HD 10, 2019+):
  enable "Apps from Unknown Sources" on the tablet and install the APK
  directly — no Google Play Services are required.
- Windows builds are currently unsigned: SmartScreen and antivirus
  heuristics may warn on first run (Microsoft Defender's machine-learning
  model flagged the v0.2.1 zip as `Trojan:Script/Wacatac.B!ml` — a false
  positive; the release zip's SHA-256 in the release notes is the
  authoritative check). Signing is **prepared** via SignPath
  Foundation's free open-source program — see
  [CODE_SIGNING_POLICY.md](CODE_SIGNING_POLICY.md). It activates when the
  project is approved and the workflow's `SIGNPATH_ENABLED` variable is
  set; until then the `sign-windows` CI job stays dormant. macOS builds
  are also unsigned (Gatekeeper warns on first run).

## License

GoodEnoughCraft is released under the [MIT License](LICENSE).
Third-party components keep their own licenses: the Godot engine (MIT)
and Voxel Tools (MIT), vendored in `addons/zylann.voxel/` — see the
license files inside that folder.

## Roadmap

- **Phase 3:** survival — health/hunger and difficulty setting, fall
  damage, timed mining with block drops, crafting, hostile mobs; plus the
  per-material block-behavior system (dig/move behaviour per block type
  or category, adjustable from a settings screen)
- **Phase 4 (optional):** multiplayer
