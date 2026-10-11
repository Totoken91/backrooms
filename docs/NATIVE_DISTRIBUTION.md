# Native Windows / Linux distribution and Vercel showcase

Kenny chose native PC (Windows and Linux x64) as the primary target on 2026-10-11. Vercel serves
the static showcase in `site/`, not the Godot Web export. Do not resume Web
performance work or replace the showcase with the browser game without asking.
No push without Kenny's authorization; the initial migration was explicitly authorized.

## Packaging

`export_presets.cfg` has Windows and Linux x64 release presets, separate EXE/PCK, no
console wrapper. `.github/workflows/windows.yml` downloads official Godot 4.6
and templates, validates SHA-512 against the official release checksums, imports
the project, runs `test_world.gd`, exports and checks ZIP integrity, and publishes
GitHub Release `desktop-<source SHA>`. Its token is the scoped Actions token;
no personal token or secret is stored in source. Third-party licence notices and
the exact source SHA accompany the executable. The Windows executable is not signed. Linux is packaged as TAR.GZ to preserve executable permissions and smoke-tested headless on the Linux CI runner; GPU rendering on a real Linux desktop still needs validation.

The workflow runs on gameplay/export/distribution changes or manual dispatch.
It never commits generated binaries into Git. The download link always uses:
`https://github.com/Totoken91/backrooms/releases/latest/download/Hors-Plan-Windows-x64.zip`

Before announcing a release, download the public ZIP, compare SHA-256 to its
`SHA256SUMS.txt`, extract it, and launch the actual exported binary. GPU captures
use the existing watchdog with `GODOT_PACKAGED=1`, `GODOT=<exported EXE>` and an
absolute `CAPTURE_LOG`; exported Godot binaries reject `--path`. Run from the
extracted game's directory. Keep one GPU job at a time.

Linux uses the same release: `Hors-Plan-Linux-x64.tar.gz`.

## Website

`site/index.html`, `style.css`, `favicon.svg`, and three WebP images. No runtime
JS, build dependencies, trackers, reference photos, API keys, or third-party fonts.
Images are real native P07 gameplay captures, seed 99: `pillars`, `depth`, and
`seam_west`. No externally sourced references. The `.gdignore` keeps site assets
out of Godot. French copy describes only the playable prototype; no survival,
entities or save system claimed. Test anchor navigation, images, keyboard focus,
the actual release download and no console errors before publishing.

Vercel project `backrooms`, production alias
`https://backrooms-sable-five.vercel.app/`, output directory `site`.
GitHub main triggers Vercel. Site-only commits do not create new game releases.

## Previous Web version

P07 Web build is retained in `build/web`, historical commit `a959072`. Its old
`.github/workflows/web.yml` is manual-only. Source and exports remain recoverable;
there is no active link from the showcase. Do not delete or overwrite this archive
as part of ordinary Windows development.

## Next work

Initial validation (2026-10-11): release `desktop-8368fbd`, CI run
`38151484481` succeeded, both public archives downloaded and SHA-256 verified.
Windows archive integrity / PE header checked and actual exported executable
started. The first Windows release of the same P07 gameplay also rendered a
1280×720 depth capture under the watchdog with zero pending bakes and no runtime
errors. Linux archive contains an ELF x64 executable with mode 0755; headless
startup passed in CI. Native Linux GPU validation remains outstanding.

Profile native performance and startup lighting where necessary; then continue
the Level 0 generation roadmap (P08 blackout zones, no arches). Web optimization
is suspended, rather than a prerequisite for P08.
