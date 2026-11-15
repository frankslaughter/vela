# Stage 0 log: first call with no code written

Started 2026-11-13. Done when two phones hold a conversation through the Mac for ten minutes.

**Status: done on 2026-11-14.** The follow-ups below carry into Stage 1.

## Set up so far

- LiveKit server 1.13.11 and the `lk` command-line tool 2.19.4 installed with Homebrew.
- Server running in development mode, started with `livekit-server --dev --bind 0.0.0.0`. It listens on port 7880 and uses the placeholder key `devkey` with secret `secret`.
- Server reached from the Mac's network address, and a test client joined and left room `stage0` cleanly.
- Three join tokens minted for `phone-1`, `phone-2`, `phone-3`, valid until 2026-11-20. They are in [join-details.md](../stage0/join-details.md) with the server URL.
- LiveKit's example app cloned to `stage0/swift-example` at commit d08da72 (SDK 2.19.0).
- 2026-11-14: example app built to an iPhone Air with a personal team. It needed the screen-share extension detached and the App Groups and Multipath capabilities removed, since the app group belongs to LiveKit and personal teams cannot use Multipath.
- 2026-11-14: the phone connected with `ws://MacBook-Pro.local:7880`. Reaching the Mac by name works from a phone, so no address is typed anywhere. If the Mac changes networks while the server runs, restart the server.

## Follow-ups

- **The intercom VLAN.** The Mac is on the main Wi-Fi of the California home. Section 4 of the plan has not been applied, so phones still have internet during tests. The first call works without it; the no-internet condition does not get exercised until it is in place.
- **A headset on the second phone.** The iPhone 18 Pro ran without one, so only one Bluetooth leg has been tested. The boat's condition is a headset on both ends.
- **A third phone.** Optional.

## Putting the app on a phone

1. Open `stage0/swift-example/LiveKitExample.xcodeproj` in Xcode, not the `-dev` workspace.
2. In Signing & Capabilities for the `LiveKitExample` target, pick your team and change the bundle identifier to something of your own. A free personal team works for a week.
3. Plug in the phone, pick it as the destination, run the `SwiftSDK.1` scheme.
4. In the app, enter the server URL and that phone's token from the join details file, then connect. Copying on the Mac and pasting on the phone is the easy way to move the token.
5. Allow the microphone and local network prompts. Leave the camera off.

The example's README also offers a prebuilt version on TestFlight, which skips Xcode entirely.

## What to note during the call

| Question | phone-1 | phone-2 | phone-3 |
|---|---|---|---|
| Phone model and iOS version |iPhone Air   | iPhone 18 Pro| |
| Headset model | Shokz OpenComm2| None| |
| Audio keeps flowing with the screen locked, phone in a pocket? | Yes| | |
| Mic and speaker route through the headset, or the phone? | headset| | |
| Does the headset button do anything? | no| | |
| Seconds to recover after walking out of Wi-Fi range and back | no obvious delay once wifi reconnects| | |
| Anything that sounded wrong: echo, clipping, dropouts | no| | |

## Result

- Two phones, ten minutes: yes, on 2026-11-14. iPhone Air with a Shokz OpenComm2 and iPhone 18 Pro with no headset, on the main California Wi-Fi.
- Three phones: not tried.
- What the real app has to do better: the OpenComm2's button did nothing, so Stage 1 has to map it to mute. Joining meant pasting a URL and a token by hand on each phone, which Stage 1 replaces with finding the Mac over Bonjour. Everything else held up: audio survived a locked phone in a pocket, routed through the headset, and came back with no obvious delay after a Wi-Fi drop.
