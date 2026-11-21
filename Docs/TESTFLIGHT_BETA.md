# Private TestFlight beta (5–10 DPs)

The build pipeline is ready: `release-ios.yml` archives a signed build, checks it and uploads it to
TestFlight. What is left are account steps only the owner can do. Do them in this order.

## 1. Owner steps, once

1. **Apple Developer Program.** Enrol at developer.apple.com/programs ($99/year). To publish under
   Novaluma Films Ltd, enrol as an **organisation**: you need the company's D-U-N-S number (free from
   Dun & Bradstreet via Apple's lookup page, can take a few days) and a company website on your own
   domain (novaluma.dev). Personal Team accounts can't use TestFlight.
2. **Choose the bundle id and the name testers see.** The bundle id can never change after the first
   upload. Recommended: `com.novaluma.framescout`. The name in App Store Connect can change later.
3. **Register the bundle id**: Certificates, IDs & Profiles → Identifiers → + → App IDs → App →
   Explicit, the id from step 2. Tick **Sign in with Apple** now so native Apple sign-in can follow.
4. **Create the app record**: App Store Connect → Apps → + → New App → iOS, the name, English (UK),
   that bundle id, SKU `framescout-ios`, Full Access.
5. **API key and GitHub settings**: follow `Docs/RELEASE.md` steps 5–7. Set the repository
   **variable** `IOS_BUNDLE_ID` to the id from step 2 (the Xcode project keeps `com.framescout.app`).
6. **Live database**: run section 4 of `web/supabase/schema.sql` (adds `delete_my_account()`) in the
   Supabase SQL editor, so "Delete account" works for testers who sign in.
7. **Upload the first build**: GitHub → Actions → App Store release → Run workflow, version `0.9.0`.
   About 15–30 minutes after it goes green the build shows in App Store Connect → TestFlight.

## 2. Testers

For 5–10 outside DPs use an **external** group. Internal testers have to be members of your App Store
Connect team, which would also show them your sales and app settings.

1. App Store Connect → the app → TestFlight → **Test Information**: paste the beta description and
   feedback email below. Fill **Beta App Review Information** (your name, phone, email; "Sign-in
   required" off).
2. **Test it yourself first.** TestFlight → **Internal Testing → +** → group `Team` → add yourself
   (you are already a team member) and the build. No review is needed: install it from the
   TestFlight app and run through "What to test" on your iPhone before inviting anyone.
3. TestFlight → **External Testing → +** → group `DP beta` → add the build, then press
   **Submit Review**. (For later builds of an already-approved version Apple may not require a
   review; then press **Start Testing** instead.)
4. Add testers by email (Testers → +), or turn on a **public link** limited to 10 testers and send it
   yourself.
5. After you submit, **Beta App Review** usually takes under a day. Invites go out once it is
   approved.
6. Testers install the free **TestFlight** app, accept the invite and install FrameScout. Builds
   expire after 90 days; upload a new one to keep the beta going.

## 3. Text to paste

### Beta app description

> FrameScout is a location-scouting tool for cinematographers. Scan a room with your iPhone's LiDAR,
> then plan lights, cameras and shots on the plan and in 3D, check light readings and the sun path,
> and get a kit list. Every number says whether it was measured, estimated or typed in.

### Feedback email

Use a project address on your domain, for example `beta@novaluma.dev` (forward it to your inbox).

### What to test (build notes)

> Thanks for testing. Please try a real recce if you can:
> 1. Scan a room (iPhone/iPad Pro with LiDAR), or draw one by hand, or open the sample room from Home.
> 2. Add two or three lights and a camera. Do the T-stop readings and fall-off look believable for
>    the fixtures you know?
> 3. Line up a shot and check the framing against what your lens and sensor would give.
> 4. Check the sun path for a real date and place.
> 5. Export the kit list or the plan and share it the way you would with your gaffer.
>
> To send feedback, take a screenshot in the app and tap Share Beta Feedback, or open TestFlight →
> FrameScout → Send Beta Feedback. Tell us what you expected, what happened, and the
> device you used. Sign-in and sync are optional.

### Invitation note to send with the link

> Hi [name], I'm building FrameScout, an iPhone app for location recces: scan a room with LiDAR, then
> plan lights and shots on it. I'd value 30 minutes of your eyes on it before it goes public. Install
> TestFlight from the App Store, then open this link: [link]. It needs iOS 17; scanning needs a Pro
> iPhone or iPad with LiDAR, the rest works on any recent iPhone. Scan meshes, textures and photos
> stay on your phone. Sign-in is optional: if you sign in to sync, your projects (including each
> scan's 2D floor plan, the location address and GPS position) are stored on our sync server.

## 4. Reading feedback

Screenshots and comments arrive in App Store Connect → TestFlight → **Feedback**, and crash reports
under **Crashes** (also in Xcode → Organizer). Testers' devices, iOS versions and session counts are
under each tester.

## Before the beta goes public

- Native Sign in with Apple (App Review rule 4.8), now possible with the paid team.
- Privacy policy hosted on novaluma.dev and linked in the app record (needed for the store listing).
- A real-device 3D screenshot for the listing.
