# Code Signing Policy

GoodEnoughCraft's Windows releases are prepared for code signing through
SignPath Foundation's free open-source program.

**Free code signing provided by [SignPath.io](https://signpath.io),
certificate by [SignPath Foundation](https://signpath.org).**

## Who

- **Project owner and release approver:** Wade Feltman — the only person
  who approves a signing request before a signature is applied.
- **Build automation:** GitHub Actions workflows in this repository.
  No other person or system may submit signing requests.

## What gets signed

- Only the Windows executable `GoodEnoughCraft.exe`, exactly as produced
  by this repository's GitHub Actions export step from the public source
  in this repository.
- Nothing else is signed as a project binary. Third-party open-source
  components ship as released by their upstreams:
  - the Godot engine (MIT License, Godot Engine contributors), and
  - the Voxel Tools library `libvoxel.windows.template_release.x86_64.dll`
    (MIT License, Zylann), vendored in `addons/zylann.voxel/`.
- The game data file `GoodEnoughCraft.pck` is not an executable and is
  not signed; its integrity is covered by the SHA-256 hash published
  with each release.

## How signing works

1. Every release build runs on GitHub-hosted runners from this public
   repository — never on a private machine.
2. The CI workflow uploads the unsigned executable as a GitHub Actions
   artifact and submits that exact artifact to SignPath.
3. The project owner reviews and approves (or denies) each signing
   request in SignPath. No signature is applied without that approval.
4. The signed executable is packaged with the unsigned components and
   published as a GitHub Release together with its SHA-256 hash.

Signing is currently **prepared but not yet enabled**: it activates once
the project is approved by SignPath Foundation and the workflow's
`SIGNPATH_ENABLED` repository variable is set (see the `sign-windows`
job in `.github/workflows/godot.yml`). Until then, release builds are
unsigned and Windows SmartScreen / antivirus heuristics may warn about
them.

## Verifying a download

- Download only from this repository's GitHub Releases page.
- Check the file's SHA-256 hash against the hash published in the
  release notes.
- Once signing is enabled: right-click `GoodEnoughCraft.exe` →
  Properties → **Digital Signatures** should list a signature issued
  to **SignPath Foundation** with a valid timestamp.

## Privacy

GoodEnoughCraft collects no telemetry and sends no data anywhere. It
will not transfer any information to other networked systems unless
specifically requested by the user or the person installing or
operating it.

## Reporting

Report signature misuse, a suspected compromised release, or any other
signing problem via this repository's GitHub Issues.
