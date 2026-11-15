# Vela Home Prototype: Build Plan

A prototype of Vela, the intercom and its voice assistant of the same name, from the [system proposal](boat-intercom-proposal.md), scoped so every stage can be built and tested at home. The boat is stood in for by recorded audio, replayed tracks, and a simulator. The first time the prototype goes aboard, it should already work; the dock trip is confirmation, not discovery.

## 1. What the prototype has to prove

Eight exit criteria. When all eight pass at home, the prototype is ready for the dock.

| # | Criterion | How it is tested at home |
|---|---|---|
| 1 | Four iPhones in full duplex on Bluetooth headsets for 30 minutes with screens locked and phones in pockets | Four people in four rooms, or two people plus two phones playing speech |
| 2 | Mouth-to-ear latency measured, under 250 ms on Bluetooth and under 150 ms wired | Clap test recorded on a laptop, measured in an audio editor |
| 3 | Mute from the lock screen and the Watch, with in-ear confirmation and the "you're muted" reminder. The headset button was dropped in Stage 1: it cannot be used on iPhone | Each headset model the crew will use |
| 4 | Open, VOX, and PTT modes hold up against recorded engine and wind noise at realistic level | Boat noise recording played from a speaker beside the talkers |
| 5 | Hold-to-ask on the Watch: "mute me", "put me on crew", "log a raised sail", "what's the count", "scratch that", each answered in under two seconds, with no internet | On the intercom VLAN, which the firewall rule keeps off the internet |
| 6 | Crew-channel calls logged automatically from a read script with at least nine of ten caught and the setup-talk false positives rejected | Two people reading a scripted fishing day over the intercom |
| 7 | Replayed tracks produce the right state sequence (trolling, circling, chasing, backing, resuming) and one "was that a fish?" prompt for an unlogged back-down | Simulated tracks replayed through Signal K |
| 8 | Everything restarts by itself after the Mac loses power | Pull the plug, wait, check |

## 2. Standing in for the boat

No trip to the boat is possible before building, so every input the home tests need is synthesized or borrowed. None of this is a compromise on what gets proven; it only means the first real recordings arrive after the dock instead of before.

- **Engine and wind noise.** Two sources, layered. A boat diesel recording from a free sound library (search for "boat diesel engine idle" or "trawler engine", CC0 licensed) for the rumble, and a car at highway speed with a window cracked, recorded on a phone, for wind. Mixed in any audio editor and played from a speaker beside the talker at about 85 dB measured with a phone sound meter app, which is roughly a cockpit at trolling speed. A generated fallback if no recording suits: brown noise low-passed at 300 Hz for the engine, pink noise for the wind.
- **The crew's calls.** Write the scripted fishing day in the crew's own words, with the spread positions, species, and phrases the crew actually uses. Two or three people record it over the intercom with the noise playing, and record it again in different voices. The traps go in the same script: "put the right long out", "that leader is too long", a joke "got him on". This is enough for the spotter and for the first clips in the training set.
- **Tracks.** The simulator in `sim/` generates every scenario from a handful of numbers that only the captain can supply: trolling speed and heading pattern, how long and how tight a sailfish circle is, how hard the boat accelerates on a marlin, how long a chase runs, what a back-down looks like in speed and duration, how long between fish on a double. Write those numbers down first; the scenarios are built from them, and adjusted when the real tracks arrive.
- **Saved tracks, if the boat can be visited at the dock.** Chartplotters keep past tracks. If a visit without going out is possible, export them as GPX and they become real replay inputs for the tracker, labeled roughly from memory of the day. Also check the chartplotter for an engine RPM page and note any existing gateway. If no visit is possible, skip this; the simulator carries the plan.

The first real fishing day after the dock is the data trip. Section 8 lists what to collect then.

## 3. Hardware for the prototype

| Item | For the prototype | Later, on the boat |
|---|---|---|
| Mac | Any Apple silicon MacBook with 32 GB runs the intercom, Signal K, and the assistant with an 8B-class model | Mac mini M5 Pro, 18/20-core, 64 GB, 1 TB, per the proposal's spec, with the 30B-class model |
| Phones | Three or four iPhones from family and friends, iOS 18 or later | Crew phones |
| Watch | One Apple Watch, Series 9 or later for Double Tap | One per crew member who wants it |
| Earpieces | Two Shokz OpenComm2 2025 Upgrade, one Shokz OpenRun Air 2 so Stage 2 measures an in-band mic against the boom, the AirPods already owned, one wired boom earpiece. See [shokz-comparison.md](shokz-comparison.md) | Crew choice |
| Wi-Fi | An intercom VLAN and an SSID named for the boat on the home UniFi network, with a firewall rule blocking it from the WAN except the Mac. Nothing to buy; the configuration is the boat's | The same VLAN and SSID on the boat's UniFi gateway (Dream Router 7 or similar) |
| Speaker | Any speaker that can play the noise recording at conversation-drowning level | Not needed |
| Developer account | Apple Developer Program, for TestFlight so phones that are not plugged into the Mac can install builds | Same |
| NMEA gateway | Not needed; the simulator stands in | USB or Wi-Fi gateway per the proposal |

## 4. Network setup on the home UniFi

Ten minutes in the UniFi console, done once, and the prototype is built against the boat's network from day one.

- Create a network on its own VLAN with its own DHCP range. Its name is only a label; `intercom` will do. The Mac takes an ordinary DHCP address like everything else; nothing refers to it by address.
- Create a Wi-Fi network on that VLAN, named exactly as the boat's will be, which is the boat's own name. Phones that join it at home then join aboard without anyone touching them. WPA2/WPA3, 5 GHz preferred with 2.4 GHz allowed, WMM on. Broadcast it from one access point near where testing happens; the house is over-provisioned, so one is plenty.
- Add a firewall rule: the intercom VLAN to the WAN is blocked, except from the Mac, picked in the rule as a device rather than by address. Phones on this SSID then have no internet, which is the boat's condition, and iOS's handling of a no-internet network gets exercised in every test rather than in one special session.
- Keep the Mac, the phones, and the Watch's phone on this one VLAN. Do not rely on the mDNS reflector to bridge discovery across VLANs; the boat will not need it and the prototype should not either.
- Export or screenshot the settings. The boat gateway is configured by copying them.

If a tester needs internet on their phone during a long session, that is what cellular is for; the SSID stays as it is.

## 5. Repository layout

One repository, four parts, Python for everything on the Mac and Swift for everything on Apple devices.

```
fishing/
  server/      LiveKit config, launch scripts, the vela control service (Python, FastAPI),
               and settings.toml, the one file that holds every changeable name
  ios/         Vela iPhone app and Watch app. The Xcode project is generated from project.yml by XcodeGen
  assistant/   LiveKit Agents worker: speech-to-text, grammar, local model, tools, fish log, spotter, tracker
  sim/         Track generator, Signal K feeder, noise clips, scripted test days
  docs/        The proposal, this plan, test logs
```

Python on the Mac for the control service, assistant, and simulator keeps one language and one process model for everything that is not an app. The proposal mentioned Go or Node for the control service; for the prototype, Python is the right call.

**Names.** They follow the Names table in the proposal's section 7. Two are permanent and go in before the first Stage 1 build: the Bonjour service type `_vela._tcp` and the app bundle identifier `com.tower3.vela`. Everything else lives in `server/settings.toml`, which the control service and the assistant both read:

```toml
boat_name      = "<the boat's name>"   # Bonjour instance name and the entry in the app's boat list
assistant_name = "Vela"                # spoken name and the assistant's participant identity
channels       = ["all", "crew"]
```

The Wi-Fi name is the boat's name too, but it is set on the gateway, not here; the apps and the Mac never need it.

## 6. Stages

Each stage ends with a test that can be run at home and a short log entry in `docs/`. Roughly one weekend per stage, eight weekends total.

### Stage 0: First call with no code written

**Build.** Install LiveKit server and the LiveKit command-line tool on the Mac with Homebrew. Run the server in development mode on the intercom VLAN. Install LiveKit's open-source example iOS app on two phones from Xcode, pointed at the Mac by its `.local` name, which is the same on every network. Pair a Bluetooth headset to each.

**Test.** Two people in two rooms talking in full duplex. Then three. Note how the example app handles the headset and background, because the real app has to do better.

**Done when** two phones hold a conversation through the Mac for ten minutes.

### Stage 1: The intercom app

**Build.** Before the first build, fix the two permanent names from section 5: the bundle identifier in the Xcode project and `_vela._tcp` in the app's Info.plist. Then a Swift app on the LiveKit iOS SDK with: auto-join by browsing Bonjour for `_vela._tcp`, listing the boats found, remembering the one chosen, and joining it with a saved display name; the audio session configured for the hands-free profile; background audio mode; the headset play/pause command mapped to mute; mute and unmute tones in the ear; the "you're muted" reminder; three big buttons (mode, mute, channel) and a who-is-talking strip; a lock-screen Live Activity with mute state.

Alongside it, the first version of the control service: reads `server/settings.toml`, advertises `_vela._tcp` under the boat's name, mints LiveKit tokens, holds the roster, serves a one-page web roster.

**Test.** Four phones, screens locked, in pockets, 30 minutes. Mute from the lock screen with each headset model. On the OpenComm2, press the boom mute button and confirm the app notices the dead-silent mic and warns, since the phone is not told about that mute. Walk out of Wi-Fi range and back. Exit criteria 1 and 3.

### Stage 2: Latency and noise

**Build.** Nothing new in the app. A test rig: two headsets side by side on a desk, one wired into a laptop recording directly, the other recording the intercom path from a talker in another room. A clap in the talker's room appears twice in the recording; the gap is the latency. Repeat for each headset and for wired. Record the numbers.

Then play the synthesized boat noise from section 2 through a speaker beside the talker at a level that makes unaided conversation hard. Try Open, VOX, and PTT. Tune the VOX gate on the noise-suppressed signal until engine noise does not open it and speech does.

**Test.** Exit criteria 2 and 4. If Bluetooth latency comes in above 250 ms, this is the moment to decide on wired earpieces for the people who stand together.

### Stage 3: Watch and self-mute

**Build.** The watchOS companion: a full-screen mute toggle wired to Double Tap, hold-to-talk, hold-to-ask (routes audio to the assistant track, which does not exist yet; for now it mutes the crew track and shows a listening state), channel switch, haptics for incoming talk, a complication showing mute state. Force-mute from the web roster.

**Test.** Mute from the wrist with wet hands and a glove. Haptic on incoming talk in a noisy room. Force-mute from the roster page and confirm the person cannot unmute.

### Stage 4: The assistant, commands only

**Build.** A LiveKit Agents worker in Python that joins as a participant under the assistant name from the settings file and subscribes to the assistant track. Speech-to-text with a streaming Whisper model on the Mac, with the boosted vocabulary. The deterministic grammar for the dozen core commands, matched on the transcript first. A local model through MLX, 8B class on the MacBook, called only when the grammar does not match, with tool calls constrained to the schema. Tools: intercom (mute, unmute, channel, roster), fish log (add, correct, undo, count) on SQLite, position (from Signal K, which at this stage reports the simulator's position). Text-to-speech through macOS voices, into the requester's ear only.

**Test.** A scripted list of forty commands read by three different voices, with the noise recording playing. Log the transcript, the action, and the reply time for each. Exit criterion 5: all core commands correct, replies under two seconds, Wi-Fi only with no internet route on the Mac.

### Stage 5: Hearing the cockpit

**Build.** The spotter on the crew channel: subscribe per talker, run the recognizer continuously on the crew track for now (a dedicated lightweight spotter comes later, once there are clips to train it), match the phrase table, create provisional events with readback in the speaker's ear, confirm after a few minutes or on "scratch that". The setup-talk rule: ignore spread positions for a minute after "lines out". Store clips around every match with speaker, headset, and outcome, which is the start of the training set.

**Test.** Two people read a scripted fishing day over the crew channel with noise playing: lines out, a raised fish on the right long, a bite, a hookup, a double, a leader, a lost fish, and the traps: "put the right long out", "that leader is too long", a joke "got him on". Exit criterion 6.

### Stage 6: The fight tracker on replayed tracks

**Build.** Signal K on the Mac. A simulator in `sim/` that writes a 1 Hz Signal K stream of position, speed over ground, course over ground, heading, and RPM for scripted scenarios: straight trolling, a spread-reset turn, a sailfish circle at trolling speed for four minutes, a marlin run with acceleration then a chase and a back-down, a double with back-down, forward, back-down. A second feeder that replays any GPX file at adjustable speed, for saved chartplotter tracks if any could be exported and for the first real fishing day later. The tracker: five states from the Signal K feed, confirming voice events, stamping releases during backing, asking once about an unlogged back-down in the captain's ear.

**Test.** Each scenario produces the expected state sequence and no others; the spread-reset turn does not produce CIRCLING. If any saved track is available, replaying it produces a plausible state sequence with no CIRCLING during what memory says was plain trolling. One unlogged back-down produces exactly one question. Exit criterion 7.

### Stage 7: Dress rehearsal

**Build.** Everything launched at login on the Mac, restarting on failure, with LiveKit also restarting when the Mac's address changes. TestFlight builds on all phones. The web roster becomes the first helm dashboard: who is on, tally, track with pins. A two-page runbook: how to start, how to reset.

**Test.** Pull the Mac's power, wait a minute, restore it, and confirm phones rejoin on their own without anyone touching them. Then a full simulated day: noise playing, the fishing script read over the crew channel while the sailfish and marlin tracks replay, hold-to-ask commands mixed in. Exit criterion 8 and all the others together.

Optionally, a car ride: the MacBook and two phones on one phone's personal hotspot, the tracker running on phone GPS. Drive straight, circle a lot, reverse in a car park. It is a rough stand-in for the boat, but it is the only way to see real GPS noise before the dock.

## 7. What is deliberately left out

- Android. Added after the iPhone app is right; the LiveKit Android SDK makes it a port, not a redesign.
- CallKit. Tried in Stage 1 for the headset button and dropped; see `docs/stage-1-log.md`.
- The 30B-class model. The grammar plus an 8B model is enough to prove the assistant; the bigger model arrives with the Mac mini.
- The dedicated keyword spotter. The recognizer running continuously on the crew track is good enough to prototype and collects the clips the real spotter trains on.
- VHF or hailer bridge, day recorder, online answer mode, wake word.
- Any NMEA 2000 hardware. The simulator and the replayed track cover it until the dock.

## 8. From home to the dock, and the first real day

When the eight criteria pass, the dock trip is: mount the AP, plug in the Mac mini, run the latency and coverage check from the proposal's day-one check, plug in or point Signal K at the gateway, and run the same scripted fishing day with the engines idling.

The first real fishing day runs the Eartec and the prototype side by side, and it is also the data trip the home tests had to do without. Collect, with no extra effort beyond switching things on:

- **Cockpit and bridge audio at trolling speed** through each headset type, which the spotter and the assistant record around every match anyway. Add a phone in a pocket recording continuously, for the noise bed that replaces the synthetic one.
- **The crew's real calls**, as spotted events with clips. Compare them to the scripted phrases and add what the crew actually says.
- **The track**, from Signal K at 1 Hz and from the chartplotter export, with the prototype's log and a paper log of fish times side by side. Wherever they disagree, the paper log wins and the difference is a bug or a label.
- **The simulator's numbers**, checked against the real track: circle duration and radius, marlin acceleration, back-down speed and duration. Update the scenarios so the next home tests use real shapes.

The prototype's log is checked against the paper log at the end of the day. That comparison is the first honest measure of the whole system.
