# Slam

Personal workout tracker for iPhone. Single user, data stays on the phone (Files › On My iPhone › Slam).

- `Packages/SlamCore` — models, plates, records, stats, storage. Tested on Linux:
  `cd Packages/SlamCore && docker run --rm -v "$PWD":/src -w /src swift:6.2-noble swift test`
- `Slam/` — SwiftUI app. `project.yml` is the project (XcodeGen); the `.xcodeproj` is generated in CI.
- **Build and screenshots** workflow: builds, then screenshots every screen on iPhone 17e and 17 Pro Max with demo data (`-demo -screen <name>`).
- **TestFlight** workflow: archives and uploads with the App Store Connect API key. Secrets: `TEAMID`, `FASTLANE_KEY_ID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY`.
