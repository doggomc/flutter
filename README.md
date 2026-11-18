# Vyse Portal Player — Flutter

A standalone Flutter desktop client for browsing live categories and channels from an **authorized Xtream-compatible IPTV portal**. The app requests `get_live_categories` and `get_live_streams` from `player_api.php`, then plays live streams with `media_kit`/libmpv.

## Credentials

- The server host is prefilled from the request; username and password fields are blank.
- You can enter credentials separately or paste a `http://host:port:user:pass` combo into the server field.
- Credentials remain in memory only and are cleared on disconnect/exit; this project does not persist them.
- The supplied server uses HTTP, which does not encrypt login requests or streams. Use only a portal you are authorized to access, and avoid reusing that password.

## Easiest Windows build: GitHub Actions

This project includes `.github/workflows/build-windows.yml`. To build without installing Flutter or Visual Studio locally:

1. Create a GitHub repository and upload the contents of this project to it.
2. Open the repository's **Actions** tab and choose **Build Windows app**.
3. Select **Run workflow**. When the job finishes, download the `VysePortalPlayer-Windows-x64` artifact.

GitHub's Windows runner generates the Flutter Windows runner, builds Release, and zips the complete runnable app folder.

## Build locally on Windows

Install the Flutter stable SDK and Visual Studio 2022 with **Desktop development with C++** and a Windows SDK. Run `build_windows.bat` from this folder. It generates the Windows runner if needed, fetches Flutter dependencies, builds Release, and creates a ZIP under `dist/`.

Manual commands:

```bat
flutter create --platforms=windows --project-name vyse_portal_player .
flutter pub get
flutter build windows --release
```

The Windows build is a folder containing the `.exe` and its required DLLs/resources; distribute the whole folder (or ZIP), not just the executable by itself.

## Playback

The app uses `media_kit` and its native video libraries, rather than a browser video tag, so MPEG-TS live streams can be decoded by libmpv. It does not host channels or include portal credentials. Actual access and playback depend on the provider's API, stream availability, and authorization.

This source was prepared in a Linux environment without the Flutter SDK, so it has not been compiled or tested here.
