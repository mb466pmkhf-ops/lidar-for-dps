# Installing FrameScout on your iPhone (and the 7-day problem)

With a **free Apple ID**, Apple signs apps you install from Xcode for **7 days**. After that
the icon stays but the app won't open. Your projects and scans are *not* lost — they stay in
the app's Documents folder and come back as soon as the app is re-signed with the same
bundle identifier.

Pick one of these:

## 1. Re-run from Xcode (free, needs your Mac every week)

1. Plug the iPhone in, open `FrameScout.xcodeproj`, choose your phone, press **Run**.
2. Keep the same Team and bundle identifier as before, so iOS treats it as an update and keeps your data.

## 2. SideStore or AltStore (free, refreshes itself)

These sign the app with your own free Apple ID and **re-sign it automatically every week**
over Wi-Fi, so you don't need the Mac each time.

1. Install [SideStore](https://sidestore.io) (no computer needed after setup) or
   [AltStore](https://altstore.io) (refreshes while AltServer runs on your Mac/PC).
2. Download the IPA: GitHub → **Actions** → latest green **Build & test** run →
   artifact **FrameScout-unsigned-ipa** → unzip → `FrameScout-unsigned.ipa`.
   Every push builds a fresh one (kept for 30 days).
3. Open the `.ipa` with SideStore/AltStore (Share → SideStore, or **My Apps → +**).

Free accounts are limited to 3 sideloaded apps at once. LiDAR, RoomPlan, Object Capture and
the camera all work normally in a sideloaded build.

Note: an IPA installed with SideStore gets a different bundle identifier from the one
Xcode used, so it starts with empty data. Move projects across with
**Project › Export › Project Backup** in the old install and **Home › ⋯ › Import Project
Backup** in the new one (do that before the Xcode build expires, or re-run it once from Xcode).

## 3. Apple Developer Program (US$99/year, cleanest)

- Builds from Xcode stay valid for **1 year**.
- **TestFlight**: archive in Xcode (*Product › Archive › Distribute › TestFlight*) and
  install from the TestFlight app. Each build lasts 90 days, and you can share it with
  crew (up to 10,000 testers).

If you shoot with this app regularly, option 3 saves a lot of hassle. Option 2 is the
best free route.
