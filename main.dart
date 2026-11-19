name: Build FreeF1 Cockpit (Windows)

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  windows-release:
    runs-on: windows-latest
    steps:
      - name: Check out source
        uses: actions/checkout@v7

      - name: Install Flutter stable
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Verify portal build secrets
        shell: pwsh
        env:
          PORTAL_USERNAME: ${{ secrets.PORTAL_USERNAME }}
          PORTAL_PASSWORD: ${{ secrets.PORTAL_PASSWORD }}
        run: |
          if ([string]::IsNullOrWhiteSpace($env:PORTAL_USERNAME)) { throw 'Add PORTAL_USERNAME in repository Actions secrets.' }
          if ([string]::IsNullOrWhiteSpace($env:PORTAL_PASSWORD)) { throw 'Add PORTAL_PASSWORD in repository Actions secrets.' }

      - name: Generate the Windows runner
        run: flutter create --platforms=windows --project-name freef1_cockpit .

      - name: Remove generated Flutter counter test
        shell: pwsh
        run: |
          $sampleTest = 'test/widget_test.dart'
          if (Test-Path $sampleTest) {
            $contents = Get-Content $sampleTest -Raw
            if ($contents.Contains('Counter increments smoke test') -and $contents.Contains('MyApp')) {
              Remove-Item $sampleTest
            }
          }

      - name: Resolve Flutter packages
        run: flutter pub get

      - name: Analyze Dart source
        run: flutter analyze

      - name: Run unit tests
        run: flutter test

      - name: Build Windows release
        shell: pwsh
        env:
          PORTAL_USERNAME: ${{ secrets.PORTAL_USERNAME }}
          PORTAL_PASSWORD: ${{ secrets.PORTAL_PASSWORD }}
        run: flutter build windows --release "--dart-define=PORTAL_USERNAME=$env:PORTAL_USERNAME" "--dart-define=PORTAL_PASSWORD=$env:PORTAL_PASSWORD"

      - name: Upload the complete runnable app folder
        uses: actions/upload-artifact@v7
        with:
          name: FreeF1-Cockpit-Windows-x64
          path: build/windows/x64/runner/Release/
          if-no-files-found: error
          compression-level: 0
