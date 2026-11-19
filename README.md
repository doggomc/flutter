# FreeF1 Cockpit — Flutter

A standalone Flutter Windows app styled after the FreeF1 website cockpit. It launches directly into **Theater mode** and automatically loads only the configured `LIVE | FORMULA 1 F1` category. There are no server, username, or password fields.

## Cockpit features

- Responsive theater-first player with an always-visible **Exit theater** control and Escape shortcut.
- Four independent Multiview tiles. Each tile can select, clear, retry, and show its own playback state; duplicate feeds are disabled, stale selections are remapped after refresh, and rapid changes are serialized per player.
- Green **LIVE** badges beside every listed stream, plus a green on-air indicator when playback is active.
- Search, channel artwork, refresh, and links to the FreeF1 website.
- Race Times and Team Livery controls are intentionally removed.

## Build the Windows app with GitHub Actions

The GitHub workflow reads credentials from repository Actions secrets; no portal username or password is stored in this source tree. Before running it, add these two repository secrets under **Settings → Secrets and variables → Actions**:

- `PORTAL_USERNAME`
- `PORTAL_PASSWORD`

Then:

1. Put the project in the repository root or in a `freef1_cockpit_flutter/` subfolder. Make sure this workflow file is at the repository root under `.github/workflows/build-windows.yml`—GitHub does not discover workflows stored inside a nested project folder.
2. Open **Actions** and choose **Build FreeF1 Cockpit (Windows)**.
3. Select **Run workflow** and wait for it to complete.
4. Download the **FreeF1-Cockpit-Windows-x64** artifact and extract it.
5. Run `freef1_cockpit.exe` from the extracted folder; keep the other files beside it.

The workflow caches Flutter and Dart packages between runs, skips Windows-runner generation if it already exists, removes Flutter's generated counter-test, then resolves dependencies, analyzes the Dart source, runs the unit tests, builds Release, and uploads the complete runnable app folder.

### If `flutter analyze` reports hundreds of errors at `main.dart:1`

Check that `lib/main.dart` is the Dart app entrypoint and starts with Dart imports. The Actions YAML starts with `name: Build FreeF1 Cockpit (Windows)` and belongs only at `.github/workflows/build-windows.yml`. A stray root-level `main.dart` containing that workflow is automatically removed by CI and by `build_windows.bat`. To fix a local checkout before running `flutter analyze`, run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\prepare_project.ps1`. If `lib/main.dart` itself contains YAML, overwrite it with the Dart file from this source package.

## Local Windows build

Install Flutter stable and Visual Studio with **Desktop development with C++** and a Windows SDK. Set `PORTAL_USERNAME` and `PORTAL_PASSWORD` in the shell environment, then run `build_windows.bat`.

## Credential and transport warning

The compiled app contains the credentials needed for automatic login. Anyone who receives the executable can potentially recover them, so only share the artifact with people authorized to use the account. Keep the source repository free of literal credentials. The portal uses plain HTTP, which does not encrypt login requests or stream URLs. For a public-facing app, use a private authenticated relay instead.

Analyzer and mocked service tests pass in the Linux workspace. The Windows release build and live playback still need verification on a Windows runner with an authorized account. FreeF1 is independent and is not affiliated with Formula One or the FIA.
