# Vela: Boat Intercom System Proposal

Full-duplex crew audio for a sportfishing boat, built on phones people already carry, Bluetooth earpieces, the boat's Wi-Fi, and a Mac mini base station on the boat's 120 V generator power that also runs a voice assistant for intercom control, a fishing log, and hookup detection.

The system is called Vela, and so is its voice assistant. The crew joins the boat's Wi-Fi, opens the Vela app, and asks Vela.

## 1. Recommendation in brief

Build a phone-based intercom on a self-hosted WebRTC server (LiveKit) running on a Mac mini in the cabin, with native iPhone and Android clients and an Apple Watch companion app that acts as a control surface (talk, mute, channel), not as an audio endpoint. The design point is trolling at 6-10 knots with 3-4 people talking and up to 8 at times. The boat already runs an Eartec full-duplex intercom, which sets the bar for talk quality and stays aboard as the fallback during rollout. Its two complaints, headset discomfort over a long day and headsets lost overboard, are the first things the new system has to fix.

Why this shape:

- **Full duplex with per-person gating.** Everyone can talk and hear at once. Open mics are the default while trolling, as with the Eartec, with voice activation available for anyone in a noisy spot and a one-touch self-mute from the headset button or the wrist. The captain can force-mute anyone.
- **Earpieces the crew will actually wear and can afford to lose.** Light open-ear headsets, tethered, cheap enough to keep spares. This is the direct answer to the Eartec complaints.
- **Gating matters more as talkers multiply.** Eight open mics sum eight copies of the engine noise floor into everyone's ear. Per-talker gating and level normalization are what make a 6-8 person mix usable.
- **Phones do the audio, the Watch does the buttons.** watchOS does not give third-party apps a background, real-time, two-way audio path over the network. The Watch is the glove-friendly, wet-hands control surface, which is what you actually want on the wrist.
- **Any headset that does phone calls works.** AirPods, Shokz bone-conduction, Jabra, or wired. The app uses the standard hands-free profile, so nothing is bespoke.
- **A voice assistant that runs entirely on the Mac mini.** Hold the Watch's Ask button and say "mute me", "log a raised sail", or "where was the last bite". Speech recognition, the language model, and speech synthesis all run locally, so the assistant works the same with Starlink up or down. It also listens on the crew channel for the calls the crew already makes ("right long", "got him on", "leader", "came off") and logs them, and reads the boat's track (circling, chasing, backing down) to confirm and time-stamp each fight.
- **Starlink is aboard but nothing depends on it.** Everything lives on the boat LAN. Starlink is used for software updates, backing up the day's log, and an optional online answer mode that can be switched off entirely.

## 2. Operating requirements

The boat, not the software, sets the requirements.

| Factor | Reality | Design consequence |
|---|---|---|
| Current system | Eartec full-duplex DECT intercom. Works, but the headsets are uncomfortable over a long day and several have gone overboard | Talk quality must match it; comfort and loss tolerance of earpieces are first-order; Eartec stays aboard as fallback during rollout |
| Crew | Captain (bridge/tower), mate (cockpit), 2-6 anglers, guests | 8 endpoints max; roles and channels |
| Talkers | 3-4 active most of the time, 6-8 when a fish is on | Per-talker gating; client mixes up to 7 incoming streams |
| Speed | Trolling at 6-10 kt is the design point; 25+ kt running between spots | Open mic default while trolling, VOX for noisy spots, PTT while running |
| Distance | 35-65 ft boat, tower to cockpit ~30-50 ft | The UniFi gateway's built-in AP in the cabin first; a second AP only if the tower or cockpit drops |
| Noise | Engines at trolling RPM, 10-20 kt apparent wind, water, shouting | Boom mic or bone-conduction preferred; noise gate keyed on speech, not level |
| Power | 120 V from the generator | Mac mini base station; small UPS to ride through generator starts and transfers |
| Hands | Wet, gloved, holding rods | No touchscreen for core actions; Watch + headset button |
| Water | Spray, rain, occasional dunk | Phone in pocket or dry case, screen off; earpiece IP55 or better |
| Day length | 10-14 h underway | Phone battery management; Watch is the weak link |
| Earshot | People within 10 ft hear each other directly | Latency must stay low or you hear an echo of the real voice |
| Safety | Crew must still hear engines, lines, shouts | Open-ear headsets by default; captain priority channel |

## 3. Architecture

```
  Tower / Bridge                 Cockpit                       Cabin
  ┌──────────┐                   ┌──────────┐                  ┌────────────────────┐
  │ Captain  │                   │ Mate     │                  │ Base station       │
  │ iPhone   │                   │ Android  │                  │ Mac mini, 120 V+UPS│
  │  + Watch │◄── BT HFP ──►(ear)│  + Wear  │                  │                    │
  └────┬─────┘                   └────┬─────┘                  │ livekit-server     │
       │ Wi-Fi 5 GHz                  │ Wi-Fi                  │ (SFU, Opus)        │
       │                              │                        │ vela control       │
       ▼                              ▼                        │ (roster, tokens,   │
  ╔═══════════════════════════════════════════════════════════╗│  roles, alerts)    │
  ║ UniFi gateway AP, boat's SSID on its own VLAN, no WAN    ║│ mDNS advertiser    │
  ╚═══════════════════════════════════════════════════════════╝│ web dashboard      │
       ▲                              ▲                        │ Vela assistant     │
       │                              │                        │ fish log + detector│
  ┌────┴─────┐                   ┌────┴─────┐                  │ Signal K ◄─ NMEA2k │
  │ Angler 1 │      ...          │ Angler N │                  └────────────────────┘
  │ iPhone   │                   │ iPhone   │
  └──────────┘                   └──────────┘
```

Media path: each phone captures mic audio, runs echo cancellation, noise suppression, and gain control (WebRTC's built-in audio processing), encodes Opus, and sends it over UDP to the base station. The base station is a selective forwarding unit (SFU): it forwards each talker's stream to every other member of that channel. Each phone mixes the streams it receives. With eight people this is trivial for a phone, and forwarding instead of server-side mixing keeps the server dumb and the latency low.

Control path: a small "vela" service on the base station owns the roster, mints LiveKit access tokens, holds channel and role state, handles force-mute and alerts, and advertises itself over mDNS under the boat's name so phones auto-join when they see the boat's Wi-Fi.

## 4. Endpoints

### iPhone (primary)

- Native Swift app on the LiveKit iOS SDK.
- Audio session: `playAndRecord`, mode `voiceChat`, `allowBluetoothHFP`. This routes to the headset's hands-free profile, which is what enables the headset mic. Voice quality is 16 kHz wideband, which is fine for speech.
- Background: the `audio` background mode with a continuously active audio session keeps the app alive with the screen locked and the phone in a pocket. Evaluate CallKit as an alternative in Phase 1; it is more robust against the system suspending the app, but it changes what the headset button means (a press ends the "call").
- Headset button: register for the play/pause remote command. A single press on an AirPods stem or a headset multifunction button toggles the mic. This is the one hands-free control that works across nearly every Bluetooth headset.
- Auto-join: browse for base stations over Bonjour, list the boats found, and remember the one chosen. From then on, join that boat on sight, on the last-used channel with the saved display name. The app should be usable without ever unlocking the phone once configured.
- Big-target UI: three buttons (mode, mute, channel), a "who is talking" strip, battery and signal. Nothing smaller than a thumb with a wet glove.

### Apple Watch (control surface)

- Companion watchOS app talking to the phone over WatchConnectivity.
- Controls: hold-to-talk or tap-to-latch, mute, channel switch, captain "all call".
- Feedback: haptic tap when someone starts talking to you, a distinct pattern for a captain call, a complication showing mute state.
- Not an audio endpoint. This is a platform limit, not a choice. If the phone is unreachable the Watch shows that plainly.

### Android (secondary)

- Kotlin app on the LiveKit Android SDK. Foreground service with the microphone type, communication audio mode, Bluetooth SCO for the headset mic. Media-button handling through MediaSession for the headset button. A Wear OS controller can follow the Watch design later.

### Earpieces

Anything that works as a phone headset works here, which is the point: the Eartec headsets are the part of that system the crew dislikes, and they cost several hundred dollars each to lose overboard. The selection criteria, in order:

- **Comfort for 12 hours.** Light, open-ear, nothing clamping the head or filling the ear canal. Bone-conduction bands score best here.
- **Cheap enough to lose.** Under two hundred dollars, with two spares aboard. A lost earpiece is a shrug, not a line item.
- **Tethered.** A neck lanyard or a clip to the shirt on every earpiece. AirPods in particular go over the side.
- **Wind and spray.** A boom mic beats an in-band mic in wind; IP55 or better.

Recommended tiers:

| Headset | Why | Cautions |
|---|---|---|
| Shokz OpenComm2 2025 Upgrade (bone conduction, boom mic), $160 | Crew default. Ears stay open for safety, boom mic beats wind, IP55, 16 h talk, USB-C | Boom mic is exposed to spray; wipe down. One size, droops on small heads; try before buying several. The boom's mute button mutes inside the headset and the phone never sees it, see below |
| Shokz OpenRun Air 2 (bone conduction, in-band mic), $130 | Anglers and spares. IP67 survives a dunk, 26 g, 10 h, cheapest to lose | In-band mic is weaker in wind; fine for people who mostly listen |
| Shokz OpenRun Pro 2, $180 | Only if already owned. Same IP55 as the OpenComm2 | Pricier than the OpenComm2 with a weaker mic in wind (Shokz rates it to 25 km/h) |
| AirPods Pro 2 | Already owned, good call noise handling | Fall out with wet hands, easy to lose overboard; use a tether |
| Wired earpiece with boom (Lightning/USB-C) | Lowest latency, no charging, cheapest | Cable in the way of rods |

Bone-conduction with a boom is the default recommendation for crew: comfortable all day, ears open, affordable, and easy to tether. Anglers can use whatever they own. Because every earpiece is a standard Bluetooth headset, the crew can change their minds per person without touching the system.

Shokz OpenMeet and OpenMeet2 are not on the list: best mic claims in the range, but no water rating and 78 g. The full model-by-model check, with sources, is in [shokz-comparison.md](shokz-comparison.md).

One caution specific to the OpenComm2. The mute button on its boom mutes the microphone inside the headset, and Shokz confirms the phone is not told. That would leave the roster showing the person live, silence the "you're muted" reminder, and hide the mute from the captain. The app therefore binds mute to the multifunction button, which the OpenComm2 also has, and the crew is told the boom button is not the mute. Stage 1 of the prototype checks whether the app can detect a locally muted mic as dead silence and warn, because someone will press it anyway.

## 5. Audio behavior

**Talk modes, chosen per person and switchable from the Watch:**

- **Open, the trolling default.** Mic always on, exactly how the Eartec works today, so the crew's habits carry over. Per-talker level normalization on the receiving side keeps a shouting angler and a quiet captain at the same level.
- **VOX.** Mic gated by a speech detector working on the noise-suppressed signal, with a hangover of about 400 ms. The gate keys on speech likelihood rather than raw level so engine noise at trolling RPM does not open it. For anyone in a noisy spot, or for everyone when six or more are on and the noise floor stacks. The captain can push the whole boat to VOX with one command.
- **PTT.** Momentary (hold on the Watch) or latched (tap headset button). For running between spots at 25+ kt, when no gate will hold.

**Handling 3-8 simultaneous talkers.** Bandwidth and CPU are not the problem: seven incoming Opus streams are about 220 kbps and a few percent of a phone's CPU. The problem is noise stacking and intelligibility. Three things keep the mix usable:

- Per-talker gating (VOX or PTT) so silent people contribute nothing. With eight open mics the engine floor arrives eight times.
- Per-talker level normalization on the receiving phone, so a shouting angler and a quiet captain land at the same level.
- Channels for the cases where eight people genuinely talk at once: `crew` for captain and mate, `all` for the cockpit chatter. The captain's all-call cuts through both.

## 6. Self-muting

Muting yourself has to be faster and more reliable than talking, because it is what people do while coughing, swearing at a tangle, or holding a private conversation. Every mechanism below is a single action with immediate confirmation in your own ear.

**Ways to mute, all equivalent:**

- **Headset button, single press.** Toggles mute on AirPods stems and on the multifunction button of nearly every Bluetooth headset. This is the primary path because it needs no looking and no wrist.
- **Watch, one big button.** The app's main screen is a mute toggle that fills the display. On Series 9, Ultra 2, and later, the Double Tap gesture is wired to that button through the primary-action hand gesture shortcut, so a pinch of the fingers mutes without touching anything.
- **Phone lock screen.** A Live Activity shows mute state and a toggle without unlocking.
- **Cough switch.** Holding the Watch button (or holding the headset button on headsets that support hold) mutes only while held and releases when let go.

**Confirmation and reminders:**

- A short low tone in your own earpiece on mute, a short rising tone on unmute. Nobody else hears these.
- If you are muted and the phone detects you speaking for more than about two seconds, a Watch haptic says "you're muted" once, then stays quiet for a minute. This is the single most useful feature in a group intercom and costs nothing, because the speech detector is already running.
- The Watch complication and the Live Activity show a solid mute glyph, so a glance at the wrist answers "am I live?"
- Everyone's mute state shows on the helm dashboard and on each phone's roster.

**Automatic mutes, all of which are announced in the ear:**

- Headset disconnects or its battery dies: mute, and route nothing to the phone speaker.
- Phone call comes in: mute, resume on hangup.
- Leaves the boat Wi-Fi: mute and mark absent on the roster.
- Captain force-mute: mute with a distinct tone, and the person cannot unmute until the captain releases it.

Muted is the safe state. Any time the app cannot tell what it should do, it mutes and tells you.

**Roles and channels:**

- Channels: `all`, `crew` (captain and mate), and optional per-group channels.
- Captain has a priority "all call" that ducks other audio by about 12 dB while speaking.
- The base station can inject short alert tones (fish on, lines in, come to the bridge) that everyone hears regardless of channel.

**Codec and processing:**

- Opus, 20 ms frames, 24-32 kbps per talker, in-band forward error correction on, discontinuous transmission on.
- WebRTC echo cancellation, noise suppression, and automatic gain control on the phone. Bluetooth headsets add their own processing.
- Jitter buffer kept tight (target 40-60 ms) because the LAN is short and stable.

**Latency budget, mouth to ear:**

| Stage | Bluetooth headset | Wired |
|---|---|---|
| Headset mic to phone | 40-80 ms | ~5 ms |
| Capture, processing, Opus frame | 30-40 ms | 30-40 ms |
| Wi-Fi to base station, forward, Wi-Fi to phones | 10-30 ms | 10-30 ms |
| Jitter buffer and decode | 40-70 ms | 40-70 ms |
| Phone to headset | 40-80 ms | ~5 ms |
| **Total** | **160-300 ms** | **85-150 ms** |

Under about 200 ms the delayed copy of a nearby voice reads as slight reverb. Above 300 ms it reads as an echo and becomes annoying for people standing next to each other. Bluetooth is the dominant cost and the main reason to keep everything else lean.

## 7. Network

- **A UniFi gateway with a built-in access point** (Dream Router 7 or similar) is the boat's router, with Starlink in bypass mode as its WAN. The gateway lives in the cabin on the same 120 V circuit and UPS as the Mac mini. Its own radio is the first and probably only access point: a 35-65 ft boat is a small space, and the day-one check walks the tower and the cockpit to confirm. Fiberglass is transparent; an aluminum tower or a hardtop can shadow the bridge, and if it does, one UniFi outdoor AP on a PoE run is the fix.
- **One VLAN for the intercom.** A dedicated network and SSID on its own VLAN, 5 GHz preferred with 2.4 GHz fallback, WPA2/3. The SSID is the boat's own name, so two boats at one dock never broadcast the same network. Each phone joins it once in Settings and remembers it; the apps never need to know it. The Mac mini, the phones, and the NMEA gateway if it is Wi-Fi all sit on this one VLAN, so Bonjour discovery and phone-to-Mac media never cross a VLAN boundary. A firewall rule blocks this VLAN from the WAN except for the Mac mini, named in the rule as a device rather than by address, which is how "nothing depends on Starlink" is enforced rather than hoped. Voice tagged DSCP EF (46) with WMM voice enabled on the SSID. Guests, chart tablets, and anything else go on the gateway's other networks as usual.
- **The same configuration at home.** The home UniFi setup can carry an identical VLAN and SSID for the prototype, under the same name the boat will broadcast, with the same firewall rule, so the apps are built against exactly the network they will meet aboard, and the boat gateway is configured by copying settings rather than inventing them.
- Signaling over WebSocket to the base station; media over UDP in a fixed port range. On a single LAN, ICE resolves to direct host candidates and no TURN server is needed.
- Discovery: the base station advertises the service type `_vela._tcp` over mDNS, with the boat's name as the instance name. The app lists the boats it can see and remembers the one chosen. After that, phones join within a couple of seconds of associating.
- Failure modes: if the base station is down, phones show "no base station" and nothing else. A peer-to-peer mesh fallback is possible in a later phase but is not in scope for the first version. Handheld VHF and the hailer remain the backup.

### Names

Two identifiers are permanent and are chosen once, before the first app build. Everything else is a setting.

| Name | Value | Where it lives | Can it change? |
|---|---|---|---|
| Bonjour service type | `_vela._tcp` | Compiled into the apps, since iOS requires it declared in Info.plist, and advertised by the base station | No. It is the contract between the apps and the base station |
| App bundle identifier | `com.tower3.vela`, with the Watch app at `com.tower3.vela.watchkitapp` and the Android application ID to match | Xcode project and the Apple Developer account | No, once a build reaches TestFlight |
| Boat name | The boat's own name | Settings file on the base station | Yes. It is the Bonjour instance name and the entry in the app's boat list |
| Wi-Fi network name | The boat's name, by convention | UniFi gateway | Yes. Phones rejoin once |
| VLAN name | Any label | UniFi gateway | Yes. Only the VLAN number matters |
| Assistant name | Vela | Settings file | Yes. It is the spoken name and the assistant's participant identity. A trained wake word would pin it |
| App display name | Vela | Xcode project | Yes |
| Channel names | `all`, `crew` | Settings file | Yes |

One settings file on the base station holds the boat name, the assistant name, the channels, and the ports. The control service and the assistant both read it, so a rename is a one-line change. The service type is a protocol identifier, not a brand: it never appears on screen and stays as it is even if the product is renamed.

## 8. Base station

**Hardware.** A Mac mini with the M5 Pro, 64 GB of unified memory, and a 1 TB SSD, in the cabin on the generator's 120 V circuit, behind a small line-interactive UPS. The memory is for the assistant: a streaming speech recognizer, a local language model in the 30B class, and speech synthesis all resident at once, with the intercom server and Signal K alongside. The UPS is not optional: generator starts, stops, and shore-to-generator transfers drop power for seconds, and the intercom should not blink every time. A 600 VA unit rides through any of those and gives the Mac a clean shutdown if the generator dies. Eight Opus streams are a rounding error for this machine; the assistant is what uses it. A Linux mini PC runs the same software if a Mac is ever inconvenient.

**Mac mini M5 Pro configuration (US prices as of the August 2026 launch):**

| Choice | Pick | Price | Why |
|---|---|---|---|
| Chip | M5 Pro, 18-core CPU, 20-core GPU | $1,900 base | The upgraded tier adds 25% more GPU over the 15/16 for $200. The GPU is what runs the recognizer and the model's prompt processing at the same time; it is the cheapest headroom in the configuration. The 15/16 tier works if budget is tight. |
| Memory | 64 GB | +$1,000 | A 30B-class model at 4-bit takes 18-20 GB plus a few GB of context, two recognizer instances take 3-4 GB, macOS and the services take 6-8 GB. 48 GB runs that with little room to try a larger model or a second one for the spotter. Memory is soldered, so this is the one choice that cannot be revisited. |
| Storage | 1 TB | +$300 | Several candidate models at 20-40 GB each, a season of event clips, and room for a day recorder at roughly 1 GB per fishing day. 512 GB fills up with the third model. 2 TB at $800 only if every day is to be recorded in full for years. |
| Ethernet | 2.5 GbE, standard | $0 | Eight voice streams and a Signal K feed are well under 10 Mbps. The 10 GbE option buys nothing here. |
| **Total** | | **$3,200** | A 15/16-core chip with 64 GB and 1 TB is $3,000; the minimum that still runs the 30B model is 15/16 with 48 GB and 512 GB at $2,300. |

What the machine provides and what it needs around it:

- **Ports.** Three Thunderbolt 5 ports and one HDMI at the back, two USB-C ports and a headphone jack at the front. No USB-A, so the NMEA USB gateway and a later USB audio interface for the VHF bridge each need a USB-C adapter or a small powered hub. One Ethernet cable to the UniFi gateway; Wi-Fi 7 is aboard but the Mac should be wired.
- **Power.** 100-240 V input, 155 W maximum, typically a fraction of that. With the UniFi gateway on the same 600 VA UPS there is still ample margin; the UPS is for riding through transfers, not for long runtime.
- **Size and mounting.** About 5 by 5 by 2 inches and 1.6 lb. It has a fan, so it needs airflow: a ventilated shelf or cabinet in the cabin, strapped down, not a sealed box. Keep it where spray cannot reach and condensation drains away from it.
- **Setup.** An ordinary DHCP address on the intercom VLAN; nothing refers to the Mac by address. Phones find it over Bonjour, and maintenance reaches it by its `.local` name. LiveKit reads the Mac's address when it starts, so its launch agent restarts it if the address ever changes. Auto-login, sleep disabled, the services as launch agents, screen sharing and SSH on for headless maintenance from the helm iPad or a laptop. Raise the GPU memory limit from the macOS default so the model can use most of the 64 GB.
- **Buy it configured.** Memory and SSD cannot be changed after purchase. Order from Apple with the exact configuration above.

**Software.** macOS, launched at login as background services:

- `livekit-server`, single node, no Redis, LAN-only config.
- `vela` control service (Go or Node): roster, token minting, channel and role state, force-mute, alert injection, mDNS advertising under the boat's name, REST and WebSocket API for the apps. It reads the settings file (section 7, Names).
- Web dashboard for the helm iPad: who is on, who is talking, battery per phone, mute buttons, alert buttons.
- Voice assistant (section 9): a LiveKit Agents process with local speech-to-text, a local language model served through MLX, local text-to-speech, and the fishing log and hookup detector behind it.
- Signal K server reading the boat's NMEA 2000 bus through a USB or Wi-Fi gateway (section 9): position, speed and course over ground, heading, depth, water temperature, engine RPM, rudder angle.
- Optional later: recorder for the day's audio, and a USB audio interface bridging the boat's VHF or hailer into a channel so the captain hears radio traffic in the earpiece.

## 9. Voice assistant

Vela is also the name of the assistant: a chatbot on the Mac mini that the crew talks to through the same earpieces. The name is one line in the settings file (section 7, Names). It does three jobs: runs the intercom by voice, keeps the fishing log by voice, and watches the boat's movement for the signature of a hooked fish.

### How you talk to it

- **Hold the Ask button on the Watch** (or double-press the headset button) and speak. Your audio is routed to the assistant instead of the crew for as long as you hold. This is the primary path: no wake word to miss in the wind, no risk of the crew hearing you talk to a computer.
- **Wake word** ("hey Vela") as a later option. It has to run on each phone continuously, which costs battery and mis-fires in wind, so it is not the first version.
- **Text** from the helm dashboard or the phone app, for the cabin and for reviewing the day.
- **It answers in your ear only**, in one short sentence, and reads back what it logged. Announcements to everyone ("lines in, we're heading home") are a deliberate command, not a default.

### Pipeline on the Mac mini

```
Watch hold-to-ask ─► phone mic ─► LiveKit (assistant track)
   ─► speech-to-text, local (whisper.cpp, boosted vocabulary)
   ─► local language model (MLX, 30B class, schema-constrained tool calls)
   ─► tool calls: intercom · fish log · position · detector
   ─► text-to-speech, local (macOS voices) ─► your earpiece
```

- **Speech-to-text runs locally** on the Mac's Apple silicon with a streaming Whisper model. It gets a boosted vocabulary: species (sailfish, wahoo, mahi, blue marlin, yellowfin, kingfish), spread positions (left long, right short, shotgun, teaser, flat line), and the crew's names. This is what makes "two bites on the right long" come through as words rather than noise.
- **Language understanding is a local open-weight model** served through MLX on the Mac's Apple silicon. A current instruction-tuned model in the 30B class with reliable tool calling is the target; the exact model is chosen by testing candidates against the command set during Phase 3, and swapped as better ones appear. It receives the transcript plus a compact state block (who is on the intercom, today's tally, position, detector state) and acts only through a small set of typed tools. Tool calls are schema-constrained at decode time, so the model cannot emit a malformed or invented action. Every change to the intercom or the log is a tool call, which is what makes "undo" possible.
- **A deterministic grammar underneath** handles the dozen commands that must work even if the model is slow or wrong: mute, unmute, channel, log a raised/bite/catch, undo, count. These are matched on the transcript before the model is consulted, which also makes them the fastest path.
- **Text-to-speech is local** through macOS voices. End-of-speech to start-of-reply target is under two seconds: roughly 400 ms for recognition to settle, under a second for the model with the state block cached, and a fast start on synthesis.
- **Optional online mode, off by default.** When Starlink is up, open-ended questions that are not commands ("what was our best day for sails last month?") can be routed to Claude Opus 5 through the API with the same tools, falling back to the local model if the link is down. This is a switch on the helm dashboard. It never sits in the path of a command or a log entry.

### Tools the assistant can call

| Tool | What it does | Examples of what you'd say |
|---|---|---|
| Intercom | Mute or unmute anyone, move people between channels, all-call, play an alert, read the roster and battery levels | "Mute me." "Put Dave on crew." "Tell everyone lines in." "Who's on?" |
| Fish log | Add, correct, or undo an event; report tallies | "Log a raised sail." "Two bites, wahoo, shotgun." "Caught it, released." "Make that a lost fish." "Undo." "What's the count?" |
| Position | Current position, speed, depth, water temp; mark a spot; distance and bearing back to a past event | "Mark this spot." "Where was the last bite?" "How far to where we raised the marlin?" |
| Fight tracker | Read the tracker's state; answer its one question about an unlogged back-down | "Yes, that was a fish." "No, we were just turning." |

### Fishing log

Every event is one row with the same shape: time, position, speed and course, depth, water temperature, who reported it, event type, species, count, spread position, and free notes. Event types follow the sportfishing funnel: **raised**, **bite**, **hookup**, **catch** (released or boated), and **lost**. The tally is counts per species per event type per day, which is exactly the "3 raised, 2 bit, 1 released" number the captain wants at the dock.

- The assistant reads back each entry ("Logged: bite, sailfish, right long. Two bites today.") so a mis-hearing gets caught in the moment.
- Corrections are conversational and land on the most recent matching event: "make that a wahoo", "that was two", "undo".
- Missing fields are asked once, briefly, if they matter ("which species?"), otherwise left blank.
- Storage is SQLite on the Mac mini. Each day exports a GPX track with event waypoints and a CSV of the log. The helm dashboard shows the tally and the track with pins.
- The whole day's log is available to the assistant as context, so "how are we doing versus this morning" and "what depth were the bites at" are answerable.

### Hearing the cockpit: the primary hookup signal

The crew already narrates the fishing. A raised fish is called by its position in the spread, a hookup is "got him on", a lost fish "came off", and a billfish release is "leader". Those calls are the earliest, most reliable signal there is, so the assistant listens for them on the crew channel and logs them. Nothing about how the crew talks has to change.

| Event | Phrases the spotter listens for | Notes |
|---|---|---|
| Raised | "right long", "left long", "right short", "left short", "left teaser", "right teaser", "shotgun", "flat line", "there he is", "look at the ..." | A spread position called on its own is a raised fish at that position. Species if spoken, otherwise the trip target (sailfish), marked as assumed |
| Bite | "he ate", "bite", "he's eating", "drop back", "feed him" | |
| Hooked | "got him on", "hooked up", "we're on", "he's on", "tight", "double", "triple", "two on" | "Double" and "triple" set the count |
| Release | "leader", "got the leader", "release", "released", "tagged" | Under billfish rules a leader touch is the catch, so "leader" logs a release at that moment |
| Lost | "came off", "pulled the hook", "lost him", "he's off", "broke off" | |
| Correction | "scratch that", "no, that was ...", "make that ..." | Applies to the most recent event |

How it works:

- The assistant subscribes to the crew channel per talker, so it knows who said what. A lightweight keyword spotter with the phrase list runs continuously on the Mac mini; when it fires, a few seconds of audio around the phrase go through the full recognizer for species, count, and position words. Continuous full transcription of the crew is not needed and not done.
- Spotted events are logged immediately as **provisional**, with a short readback in the speaker's ear only ("Raised, right long"). Nothing interrupts the fight. Provisional events become confirmed when the boat's movement agrees (below) or after a few minutes with no correction. "Scratch that" removes the last one.
- Setup talk is the main false positive: "put the right long out" while setting the spread. The spotter knows the difference between a position called in a sentence about deploying lines and a position called on its own, and it ignores spread positions for the first minute after "lines out" or after a resume from a fight.
- Nothing is stored except matched events and the few seconds of audio around each. Unmatched audio is never kept; matched clips are kept for the season as training data (below) and can be heard and deleted from the dashboard. Keyword spotting is on by default for the crew channel and off for every other channel; a switch on the helm dashboard turns it off entirely.
- Species defaults to the trip's target when not spoken. "Blue", "marlin", "sail", "white", "dolphin", "mahi", "wahoo", "tuna", "kingfish" override it.

### Reading the boat's movement: confirmation and the fight

Billfish do not produce a throttle-back at hookup, so movement is a poor way to detect one. What it shows reliably is the fight and its end:

- **Sailfish hookup.** The boat keeps trolling speed and turns to circle the area for several minutes, trying to raise more fish from the same group. Speed unchanged, heading rate elevated for minutes, and the track closes on itself within a few hundred meters.
- **Blue marlin hookup.** The boat holds course and may accelerate. At hookup this looks like normal trolling or a speed increase, and only the later chase and back-down give it away.
- **The chase.** Forward gear, speed and heading changes that break the trolling pattern, sometimes at well above trolling speed.
- **The finish.** Always a back-down: course over ground roughly opposite to heading, in bursts. Nothing else a sportfisher does while fishing looks like this.
- **Multiple fish.** Back down, release, forward again to chase the next fish, back down again. The alternation counts fish fought.

The tracker keeps five states from the 1 Hz Signal K feed: TROLLING, CIRCLING (sailfish pattern, must persist longer than a spread-reset turn, about two minutes), CHASING, BACKING, and RESUMING. It uses them for four things:

1. **Confirming voice events without asking.** "Got him on" followed within a few minutes by CIRCLING, CHASING, or BACKING confirms the hookup. "Leader" during or just after BACKING confirms the release and stamps its position.
2. **Fight bookkeeping.** Fight duration from hookup to the end of the last BACKING. Fish count from the number of BACKING episodes when the voice log is ambiguous. Whether it was a chase or a straight fight.
3. **Catching missed entries.** A BACKING episode with no hookup logged in the previous 30 minutes prompts, in the captain's ear only, "You backed down at 10:42 with nothing logged. Was that a fish?" This is the only question the tracker ever asks.
4. **Labels for later.** Every confirmed event is a label on the movement data, so after a season a classifier over speed, heading rate, course-versus-heading angle, RPM, and rudder angle can be trained to recognize CIRCLING and CHASING earlier and with fewer false alarms than thresholds.

The voice log is the record; the movement tracker is the witness that confirms it, times it, and notices what the crew forgot to say.

### NMEA 2000 gateway

The boat's instruments already put everything the detector wants on the NMEA 2000 backbone. One gateway brings it to the Mac mini:

- **If the boat already has a Wi-Fi gateway** for tablet chart apps (Yacht Devices YDWG-02 or similar), use it. Put it in client mode on the Mac mini's VLAN and have it broadcast its data over UDP, which Signal K listens for without needing the gateway's address. Nothing else to buy.
- **Otherwise, either kind works and Signal K reads them identically.** A USB gateway (Yacht Devices YDNU-02 or Actisense NGX-1) plugs into the Mac mini with a tee and drop cable on the backbone; it is bus-powered and depends on nothing but the bus and the Mac. A Wi-Fi gateway mounts anywhere on the backbone with no cable to the cabin, and depends on the access point staying up; most are 2.4 GHz only. Pick USB if the backbone is within a drop cable's reach of the cabin, Wi-Fi if it is not.
- **Either way, the data reaches every device.** Signal K rebroadcasts the feed to the helm dashboard and can serve NMEA 0183 over TCP to chart apps on tablets, so a USB gateway does not mean the data is locked inside the Mac.
- **Signal K** on the Mac mini reads the gateway and publishes a clean 1 Hz stream: position, speed and course over ground, heading, rate of turn, depth, water temperature, and engine RPM if the engines are on the bus. Rudder angle if the autopilot or a rudder sensor reports it.
- **Engine RPM from the MAN V12-1550s.** These are common-rail engines with an electronic control unit that reports RPM, load, coolant temperature, and fuel rate over J1939 CAN, which is how MAN's own displays get their data. Whether that reaches the NMEA 2000 bus depends on whether a J1939-to-NMEA 2000 engine gateway was fitted at install. The quick test: if the chartplotter can show engine RPM, it is already on the bus. If it cannot, a Yacht Devices YDEG-04 or Maretron J2K100 engine gateway bridges it, connected at the MAN diagnostic connector; check with the installer whether one unit sees both engines or each engine needs its own. Without RPM, the tracker still sees circling, chasing, and backing down from position and heading alone; RPM mainly sharpens the marlin acceleration and the gear changes during a back-down.
- **What each field buys.** Position and speed alone support the log and the circling state. Heading versus course is what detects backing down. RPM separates a deliberate acceleration on a marlin from a speed change due to sea state, and marks gear changes during a back-down. Rudder angle sharpens the fight-versus-turn distinction.
- **Fallback without a gateway:** the captain's phone at 1 Hz through the app. Enough for the log and the track; the detector is noticeably weaker without heading and RPM.

If a gateway needs buying, budget roughly the price of a good reel including the tee and drop cable. It can be added after the intercom and assistant are running; the software treats the gateway as one more data source.

### Collecting data for training

The spotter, the speech recognizer, and the fight tracker all get better with this crew's own data, and the assistant is in the best position there is to collect it. The rule from day one: keep the inputs next to the outcome, so every correction becomes a label.

- **Audio around every event.** The few seconds before and after each spotted phrase and each Ask-button request, with who spoke, which headset, speed and RPM at the time, and what the system did with it. If someone says "scratch that" or corrects an entry, the clip is marked as a false positive or a mis-hearing. These clips are the training set for a spotter tuned to this crew's voices and this boat's noise, and after five to ten hours they are enough to fine-tune the recognizer on fishing vocabulary over engine and wind.
- **Movement with labels.** The 1 Hz track is logged all day regardless. Each confirmed event stamps it, so a season of fishing days is a labeled dataset of what circling, chasing, and backing down look like on this boat, with no extra work.
- **Commands and their outcome.** Every transcript the language model saw, the tool call it produced, and whether the crew accepted or corrected it. This is the evaluation set for swapping models, and the training set if a smaller, faster model is ever fine-tuned for the command vocabulary.
- **A held-out set.** A few hundred real clips set aside and never trained on, so a retrained model is measured as better before it goes aboard, not just different.

Storage is a few gigabytes a season on the Mac mini, backed up over Starlink at the dock. Clips that matched nothing are discarded daily; clips attached to events are kept for the season. The crew knows the clips exist, can hear them on the dashboard, and can delete any of them. Retraining happens at the dock in the off-season, never on the water, and the generic models stay as the fallback if a retrained one misbehaves.

### What it does not do

- It does not transcribe or store crew conversation. On the crew channel it listens only for the fishing phrases, keeps only the few seconds around each match, and can be switched off from the helm.
- It does not act on the intercom without a spoken command, except for the single "was that a fish?" question after an unlogged back-down.
- It does not need Starlink for anything. The online answer mode is an optional extra, off by default.

## 10. Options considered

| Option | Verdict | Notes |
|---|---|---|
| **Mumble** (murmur server, Mumble iOS, Mumla Android) | Dock test only | Purpose-built low-latency full-duplex intercom, zero code. Useful for a two-hour test of the Bluetooth-to-Wi-Fi latency path before the MVP exists. Apps are dated, no Watch app, UI not glove-friendly, so not a phase. |
| **LiveKit** (self-hosted SFU + native SDKs) | Build on this | Modern WebRTC stack, iOS and Android SDKs, built-in audio processing, runs on Linux and macOS. Token service is a small amount of custom code. |
| **Custom Opus over UDP with a server mixer** | Not worth it | Smaller, but you re-implement jitter buffering, echo cancellation, and NAT-free transport that WebRTC already gets right. |
| **Apple Push to Talk framework** | No | Half-duplex, and delivers audio via push notifications that require internet. Wrong shape for a no-internet boat. |
| **FaceTime / group call** | No | Needs internet, no channels, no control. |
| **Commercial full-duplex intercoms** (Eartec UltraLITE, already aboard; Hollyland Solidcom C1; Cardo Packtalk mesh) | The incumbent | The Eartec is the baseline: near-zero latency, proven on this boat, and the fallback during rollout. Its headsets are the problem. The phone-based system wins on earpiece choice and comfort, cheap replaceable earpieces, Watch control, channels, alerts, and the assistant and fishing log. It loses on latency. |

## 11. Phased plan

A stage-by-stage build plan for a prototype that can be tested at home before it goes aboard is in [prototype-plan.md](prototype-plan.md).

There is no pilot phase. The Eartec experience already answers whether open mics work at trolling speed and whether the crew can hear through wind on a wireless headset. Two questions remain that only the real audio path can answer, and they take an afternoon at the dock rather than a phase.

**Day-one check, half a day at the dock, before or alongside the MVP.**
- Place the UniFi gateway in the cabin, walk the boat with a phone, and confirm its built-in AP covers the tower and the cockpit. Add an outdoor AP only if it does not.
- Any Mac on the boat Wi-Fi is the server for this: Mumble's server installs from Homebrew and does almost nothing, so a MacBook at the dock is fine before the Mac mini is fitted. Put three phones on Bluetooth headsets through Mumble or the first MVP build, stand two of the people within earshot of each other, and listen for the 200 ms echo of the direct voice. Decide from that whether Bluetooth earpieces are acceptable for everyone or whether the people who stand together (captain and mate on the bridge) get wired boom earpieces.

**Phase 1, MVP (6-8 weeks of part-time work).**
- Base station: LiveKit plus the control service, mDNS, roster dashboard.
- iPhone app: auto-join, three talk modes, self-mute from headset button and lock screen with in-ear confirmation, "you're muted" reminder, background audio, big-button UI.
- Watch app: full-screen mute toggle with Double Tap, hold-to-talk, channel, haptics.
- Android app: parity on talk modes and auto-join.

**Phase 2, boat features.**
- Channels and roles, captain all-call with ducking, alert tones.
- Helm dashboard on the iPad.
- Battery and signal reporting per phone.
- VHF or hailer bridge, day recorder.
- NMEA 2000 gateway (existing Wi-Fi unit if the boat has one, else USB or Wi-Fi), Signal K on the Mac mini; 1 Hz track logging and GPX export.

**Phase 3, voice assistant.**
- Hold-to-ask from the Watch and headset, assistant track in LiveKit, local speech-to-text and text-to-speech.
- Local language model through MLX with the intercom, log, and position tools and schema-constrained calls; deterministic grammar for the core commands; model selection by testing on the command set.
- NMEA 2000 gateway and Signal K, if not already fitted in Phase 2.
- Fish log with readback, corrections, tally, dashboard view, daily GPX and CSV export.
- Keyword spotting on the crew channel for raised, bite, hooked, leader, and lost calls, with provisional entries and readback.
- Data collection from day one: event clips with outcome, labeled track, command transcripts with outcome, held-out set.
- Fight tracker as a state machine (circling, chasing, backing, resuming) that confirms and time-stamps voice events and asks about unlogged back-downs.

**Phase 4, learned detector.**
- Spotter retrained on the season's clips of the crew's own voices; recognizer fine-tuned on boat audio once there are enough transcribed hours.
- Classifier trained on the season's labeled movement data to recognize circling and chasing earlier; wake word if the crew wants it.

## 12. Risks and open questions

- **Latency is where the new system is worse than the Eartec.** The Eartec is near zero latency; the Bluetooth path is 160-300 ms. Crew standing together will hear a delayed copy of a voice they can also hear directly. This is the number one risk on the intercom side, and the day-one check exists to measure it. Mitigations, in order: wired boom earpieces for the people who stand together, a tight jitter buffer, and lower-latency Bluetooth headsets as they appear.
- **The crew already has an intercom that works.** If plain talking is not at least as good as the Eartec, they will go back to it, and the assistant and log never get used. Keep the Eartec aboard through rollout and do not retire it until the crew asks to.
- **iOS background survival.** The audio background mode is well trodden, but test Low Power Mode, a long day, and phones in dry bags that overheat in the sun.
- **Headset button semantics.** Each headset maps its buttons a little differently. Test the specific models the crew will use.
- **Wi-Fi around the tower.** Aluminum plus a hardtop can shadow the bridge. Start with the gateway's built-in AP, add an outdoor AP only if the day-one check shows drops.
- **Watch battery.** A Watch driving haptics and a live control screen all day may not make it. Use the complication for state and open the app only to act.
- **Feedback with the hailer.** If a hailer or cockpit speaker is ever fed the intercom mix, it will feed back into open mics. Keep speakers on a one-way channel.
- **Speech recognition in the wind.** The assistant is only as good as the transcript. The boosted vocabulary helps, but test "log a bite" from the cockpit at trolling speed with each headset type in the first week of Phase 3.
- **Local model quality.** A 30B-class local model handles commands and logging well but is not Claude. Open-ended questions will sometimes get a wrong or clumsy answer. The grammar and the constrained tool calls keep the commands safe regardless; the optional online mode exists for the harder questions, and it is a switch, not a dependency.
- **Phrase false positives.** "Right long" while setting the spread, "leader" in an unrelated sentence, an angler joking "got him on". Provisional entries, per-talker readback, "scratch that", and the movement tracker's confirmation keep these from polluting the tally, but expect to tune the phrase list on the first few trips.
- **Movement false positives.** A spread-reset turn looks like the start of circling, and a stop for weed or debris can look like a chase ending. The circling state needs two minutes to fire and the tracker only ever asks one question, about an unlogged back-down, so the cost of a wrong guess is one "no".
- **Engine data on the bus.** Position and heading are almost certainly on NMEA 2000 already. RPM from the MAN engines depends on a J1939-to-NMEA 2000 engine gateway having been fitted. Check the chartplotter for an engine RPM page before counting on RPM as the throttle-back signal.
- **Open question: how many simultaneous talkers matter?** If it is really captain-to-mate most of the time with occasional angler chatter, the channel design can be simpler than described.
