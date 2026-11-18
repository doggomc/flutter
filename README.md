# FreeF1 Cockpit — Flutter

A standalone Flutter Windows app styled after the FreeF1 website cockpit. It automatically connects at launch and shows **only** the configured `LIVE | FORMULA 1 F1` category. There are no server, username, or password fields.

## Features

- Loads the configured Xtream-compatible portal and requests only the exact Formula 1 category.
- Lists that category's streams with search and channel logos.
- Plays a selected feed with `media_kit` / native mpv.
- Theater mode, four-slot Multiview, Race Times, selectable team liveries, and website links.

## Build the Windows app with GitHub Actions

The GitHub workflow reads credentials from repository Actions secrets; no portal username or password is stored in this source tree. Before running it, add these two repository secrets under **Settings → Secrets and variables → Actions**:

- `PORTAL_USERNAME`
- `PORTAL_PASSWORD`

Then:

1. Upload/push the contents of this project to the GitHub repository.
2. Open **Actions** and choose **Build FreeF1 Cockpit (Windows)**.
3. Select **Run workflow** and wait for it to complete.
4. Download the **FreeF1-Cockpit-Windows-x64** artifact and extract it.
5. Run `freef1_cockpit.exe` from the extracted folder; keep the other files beside it.

The workflow generates the Windows runner, resolves dependencies, analyzes the Dart source, runs the unit tests, builds Release, and uploads the complete runnable app folder.

## Local Windows build

Install Flutter stable and Visual Studio with **Desktop development with C++** and a Windows SDK. Set `PORTAL_USERNAME` and `PORTAL_PASSWORD` in the shell environment, then run `build_windows.bat`.

## Credential and transport warning

The compiled app contains the credentials needed for automatic login. Anyone who receives the executable can potentially recover them, so only share the artifact with people authorized to use the account. Keep the source repository free of literal credentials. The portal uses plain HTTP, which does not encrypt login requests or stream URLs. For a public-facing app, use a private authenticated relay instead.

The source was prepared in a Linux workspace. Analyzer and mocked service tests can run here, but the Windows release build and live playback still need verification on a Windows runner with an authorized account. FreeF1 is independent and is not affiliated with Formula One or the FIA.
