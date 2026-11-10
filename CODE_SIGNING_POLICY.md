# Code Signing Policy

GoodEnoughCraft's Windows releases are signed with the project owner's
**self-signed code-signing certificate**. This page publishes that
certificate's fingerprints so anyone can verify that a downloaded
executable is exactly the file this project's CI produced, signed by
the project's own key — tamper evidence for every release.

## The signing certificate

- **Subject:** CN=Wade Feltman
- **Issuer:** CN=Wade Feltman (self-signed)
- **Serial:** 1CFC24EA56D9EF3EDA7FBB0C784258DF6BC44B55
- **Valid:** 2026-11-10 to 2036-11-07 (UTC)
- **SHA-256 fingerprint:**
  `AF:FA:FC:91:08:15:72:F0:81:C9:F0:78:3A:59:59:5E:61:F4:BE:00:D8:F3:77:CA:55:82:DD:3D:52:CE:62:B3`
- **SHA-1 thumbprint:**
  `EE:74:DD:10:DA:4D:DA:13:59:EF:E9:72:0B:65:4D:25:52:22:FB:D5`

The public certificate is in this repository at
[`signing/wade-feltman-codesigning.cer`](signing/wade-feltman-codesigning.cer).
The private key is held only by the project owner and by this
repository's GitHub Actions secrets (`WINDOWS_CERT_BASE64`,
`WINDOWS_CERT_PASSWORD`); it is never committed to the repository.

## What this signature does — and does not — guarantee

**It guarantees integrity and origin.** If the executable's signature
verifies and the signing certificate's fingerprint matches the one
published above, the file has not been altered since this project's CI
signed it, and it was signed with the project's key.

**It is not a CA-issued certificate.** A self-signed certificate does
not chain to a certificate authority in the Microsoft Trusted Root
Program, so Windows SmartScreen and antivirus heuristics may still
warn on first run — treat those warnings as "unrecognized publisher,"
not as evidence about this file. Verify the fingerprint (below)
instead; it is the authoritative check, alongside the SHA-256 hash
published with each release.

History: the project applied to SignPath Foundation's free
open-source signing program in November 2026; the application was
declined (the project does not yet have the level of public trust and
visibility the program looks for), so releases use this self-signed
certificate until a publicly trusted route is adopted.

## Who

- **Project owner and certificate holder:** Wade Feltman.
- **Build automation:** GitHub Actions workflows in this repository —
  the only system that uses the key, and only to sign release builds.

## What gets signed

- Only the Windows executable `GoodEnoughCraft.exe`, exactly as
  produced by this repository's GitHub Actions export step from the
  public source in this repository.
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
2. The CI workflow decodes the certificate from the repository secret,
   signs `GoodEnoughCraft.exe` with osslsigncode, and applies an
   RFC 3161 timestamp (DigiCert TSA) so signatures remain verifiable
   after the certificate expires.
3. The workflow then extracts the signature from the signed file and
   **fails the build** if the signer's SHA-256 fingerprint does not
   match the fingerprint published above.
4. The signed executable is packaged with the unsigned components and
   published as a GitHub Release together with its SHA-256 hash.

## Verifying a download

1. Download only from this repository's GitHub Releases page.
2. Check the zip's SHA-256 hash against the hash published in the
   release notes.
3. Check the executable's signature — either way works:
   - **File properties:** right-click `GoodEnoughCraft.exe` →
     Properties → **Digital Signatures** → the signer is
     **Wade Feltman**, timestamped at signing time. Open the
     signature's certificate details and compare its SHA-256
     fingerprint with the one published above.
   - **PowerShell:**
     `(Get-AuthenticodeSignature .\GoodEnoughCraft.exe).SignerCertificate.Thumbprint`
     must print `EE74DD10DA4DDA1359EFE9720B654D255222FBD5`.
     (Windows reports the verification status of a self-signed
     certificate as untrusted — that refers to CA trust, which this
     certificate does not claim; the thumbprint match is the check
     that matters.)
4. Optional: to make Windows trust this project's builds on your own
   machine, import `signing/wade-feltman-codesigning.cer` from this
   repository into your **Trusted Publishers** certificate store. Only
   do this if the certificate's fingerprint matches the one published
   above — and understand it makes your machine trust anything signed
   with this key.

## Privacy

GoodEnoughCraft collects no telemetry and sends no data anywhere. It
will not transfer any information to other networked systems unless
specifically requested by the user or the person installing or
operating it.

## Reporting

Report signature misuse, a suspected compromised release, or any other
signing problem via this repository's GitHub Issues. If the key is ever
compromised, this page will be updated with a new certificate and
fingerprint, and the change will be announced in the release notes.
