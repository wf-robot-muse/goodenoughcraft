# Godot Foundation

A foundation project for game development with **Godot 4.7** and **Voxel Tools
(godot_voxel) 1.7**, built and verified entirely by GitHub Actions — the same
GitHub-only process as the iOS, Android, and Tauri foundations in this account.

The starter content is a small but real voxel demo: a streaming blocky terrain
(`VoxelLodTerrain`) with rolling hills, explored with a fly camera, with four
voxel types (air, grass, dirt, stone — grass surface, dirt beneath, stone
below that). Everything in the demo is built in code (`scripts/main.gd`), so
the project is plain text throughout — no hand-authored binary resources.

**Controls:** click the window to capture the mouse, then WASD to move,
mouse to look, E/Q for up/down, Shift for speed, Esc to release the mouse.
The terrain streams in around the camera as you fly.

## What's pinned

| Piece | Version | Source |
| --- | --- | --- |
| Godot | 4.7.2-stable | godotengine/godot releases |
| Voxel Tools | 1.7 (GDExtension, `v1.7x`) | Zylann/godot_voxel releases |
| Renderer | Mobile | Broad device support, incl. Fire tablets |

Voxel Tools ships as a GDExtension in `addons/zylann.voxel/`, vendored into
this repo exactly as released (all platform binaries included), so stock Godot
4.7.2 runs it with no custom engine build.

## Project layout

- `project.godot` — Godot project (main scene `scenes/main.tscn`).
- `scripts/main.gd` — builds the demo world at runtime: environment, blocky
  voxel library (air/grass/stone/dirt), blocky mesher, LOD terrain, and a
  fly camera (WASD + mouse) carrying the `VoxelViewer`, plus an on-screen
  controls hint.
- `scripts/terrain_generator.gd` — custom rolling-hills generator
  (`VoxelGeneratorScript`) writing the TYPE channel: grass surface, dirt
  beneath, stone below. (The built-in heightmap generators write SDF for the
  smooth mesher, so blocky terrain needs this.)
- `scripts/smoke_test.gd` + `scenes/smoke_test.tscn` — headless smoke test:
  loads the real demo scene, waits for the terrain to generate and mesh
  blocks, prints `SMOKE PASS` / `SMOKE FAIL`, exits 0 / 1.
- `addons/zylann.voxel/` — Voxel Tools 1.7 GDExtension (do not edit by hand;
  replace wholesale when upgrading).
- `export_presets.cfg` — Windows, Linux, macOS, and Android export presets.
- `.github/workflows/godot.yml` — CI.

## CI (GitHub Actions)

One job on `ubuntu-latest` (Godot exports are cross-platform, so no
per-platform runners are needed):

1. Downloads the pinned Godot editor and export templates.
2. Sets up JDK 17 and the Android SDK (platform 35, build-tools 35.0.0) and
   generates a debug keystore for the Android export.
3. Imports the project headlessly (`--headless --import`) — this also loads
   the Voxel Tools extension.
4. Runs the voxel smoke test headlessly; the job fails if the terrain does
   not generate and mesh blocks.
5. Exports Windows, Linux, macOS, and Android builds and uploads them as
   artifacts (`godot-windows`, `godot-linux`, `godot-macos`, `godot-android`).

The Android artifact is a **debug APK** (arm64 + x86_64), installable on
Android and Fire OS devices for testing. Note: because Voxel Tools ships no
`template_debug` Android libraries, the debug APK packs the addon's
editor-variant Android libraries; the release export packs the proper
`template_release` libraries (see activation steps).

## Running locally

With Godot 4.7.2 installed:

```sh
godot --headless --import --path .
godot --headless --path . res://scenes/smoke_test.tscn   # expect SMOKE PASS
godot --path .                                           # play the demo
```

## Identifier

`com.wf.robot.muse.godotfoundation` (macOS bundle ID; reused for the Android
package when that export is activated).

## Activation steps (documented, not wired in yet)

**Android release signing (Google Play / Amazon Appstore).** The CI already
exports an installable debug APK. For a store-ready release APK/AAB: create
an upload keystore, store it and its passwords in GitHub Secrets, fill the
preset's `keystore/release*` fields from those secrets in the workflow, and
export with `--export-release "Android"` (add `gradle_build/use_gradle_build`
if an AAB or Android plugins are ever needed). Package name is already set:
`com.wf.robot.muse.godotfoundation`.

**Code signing / notarization.** Desktop exports are unsigned (the macOS
export completes with Godot's built-in ad-hoc codesign warning when built on
Linux). macOS distribution needs an Apple Developer ID certificate and
notarization credentials; Windows distribution should use a code-signing
certificate to avoid SmartScreen warnings. Add both as GitHub Secrets and
enable the matching preset options when store accounts exist.
