# Stage 1 log: the intercom app

Started 2026-11-14. Done when exit criteria 1 and 3 pass: four phones in full duplex on Bluetooth headsets for 30 minutes, locked and in pockets, and mute from the lock screen (the headset button was dropped, see Known limits) with in-ear confirmation and the "you're muted" reminder.

**Status: built and checked in the simulator. Not yet run on a phone.** Nothing about sound has been verified, because the simulator's audio does not work on this Mac.

## What exists

- **Control service**, in `server/`. Reads `settings.toml`, advertises the boat as `_vela._tcp` through macOS's own Bonjour responder, mints LiveKit tokens, and serves a web roster. The roster shows who is talking: the service sits in every channel as a hidden participant named `vela-monitor`, because LiveKit only reports speech to someone in the room who is subscribed to the speaker. It needs the `livekit` Python package as well as `livekit-api`.
- **Test bench**, for one person testing several phones: phones report what they send and hear, test voices from the Mac give them something to hear, and a page at `/test` shows it, records a timed run and gives a verdict. See `docs/test-bench.md`.
- **Vela iPhone app**, in `ios/`. Bundle identifier `com.tower3.vela`, team N2AAKXA567, iOS 18 or later, LiveKit Swift SDK 2.19.0.
- **Lock-screen Live Activity**, a widget extension inside the app, with a mute button that works without unlocking.

## Running it

One terminal window on the Mac, from the project folder:

```bash
server/start.sh
```

It starts LiveKit and the control service together, and Ctrl-C stops both. LiveKit's log goes to `server/logs/livekit.log`. Run it again after the Mac changes networks, because LiveKit reads the Mac's address when it starts.

Then open `ios/Vela.xcodeproj` in Xcode, choose the `Vela` scheme and a phone, and run. The roster is at `http://MacBook-Pro.local:7890` from any browser on the same network.

After adding or renaming source files, regenerate the Xcode project:

```bash
cd ios && xcodegen generate
```

Set the boat's name in `server/settings.toml` before the first real test. It is `Unnamed Boat` for now.

## Checked in the simulator

| What | Result |
|---|---|
| Bonjour: the service advertises with boat name, host name and port | Yes |
| The app finds the boat and lists it | Yes |
| Token from the control service is accepted by LiveKit, a tampered one refused | Yes |
| Choosing a boat joins it; next launch joins it on sight | Yes |
| Mute button mutes the published track; the web roster shows it | Yes |
| Mute state, mode and channel survive a relaunch | Yes |
| Mode cycles Open, VOX, PTT; hold-to-talk opens and closes | Yes |
| Channel button moves between `all` and `crew` | Yes, about 0.1 s |
| Another person appears in the who-is-talking strip | Yes |
| Kicked off the server: the app notices and rejoins the same channel | Yes, after 3 s |
| Live Activity appears on the lock screen; its button mutes | Yes |
| Leave removes the phone from the roster and stops joining on sight | Yes |
| Leave button on the main screen, with a confirmation | Yes |
| App swiped away in the app switcher: the lock-screen card goes and the roster clears at once | Yes |
| App killed outright: the leftover card turns to Off within 90 seconds | Yes |
| Microphone will not start: stays on the boat listening, shown as muted, no cycling | Yes, with a simulated failure |
| Microphone retried on a tap or on coming back on screen, without leaving the boat | Yes |
| Builds for a real iPhone | Compiles and links, unsigned |

## To check on phones

These are the Stage 1 test. None can be seen in a simulator.

| Check | Result |
|---|---|
| Signs and installs with the developer team | Yes, 2026-11-14, on the iPhone Air and on the iPad Air 11-inch (M3). The iPad runs it as a phone-sized app |
| Opened on screen, joins with the microphone on | Yes, 2026-11-14, iPhone Air. No MIC OFF message |
| App swiped away: gone from the roster at once | Yes, 2026-11-14, iPhone Air. The Dynamic Island card cleared too |
| New icon on the Home Screen | Yes, 2026-11-14 |
| Two phones hear each other through headsets | Yes, 2026-11-14, iPhone Air and iPad Air, both ways |
| iOS plays its own mute and unmute tones in the headset | Yes, 2026-11-14 |
| Headset button toggles mute, on each headset model | Dropped, 2026-11-15. Not possible on iPhone without CallKit, and CallKit was not worth its costs. See Known limits |
| Headset button latches talk in PTT mode | Dropped with the row above |
| "You're muted" tone and banner after two seconds of talking while muted | Partly, 2026-11-14. It came once after the app started and not again after unmuting and muting. Fixed in the build installed the same evening, which also speaks the words; not yet retested |
| OpenComm2 boom mute: the app shows MUTED within two seconds, and the roster says "Muted on headset" | By the phone's log, yes: 4 mutes out of 4 recognised, 2026-11-15, each about 1.5 s after the press. On the phone it "seemed to work reliably". What the roster showed was not reported |
| OpenComm2 boom unmute: the app goes back to LIVE at the first sound | By the phone's log, yes: 4 out of 4, 2026-11-15 |
| A live headset in a quiet room is never taken as muted. Read "longest pure silence" in the phone's log | Yes for 90 seconds in a quiet room, 2026-11-15. Not tried on the boat, or with a second headset |
| Dead-microphone warning stays quiet in a silent room with a live mic | |
| Audio keeps flowing for 30 minutes, locked, in a pocket | Partly: 2026-11-14, iPhone Air stayed live on the roster for over 5 minutes locked. Sound not checked, one phone only |
| Walk out of Wi-Fi range and back: rejoins without touching the phone | |
| Headset switched off mid-call: mutes, with a warning | |
| A phone call comes in: mutes, and comes back as it was | |
| Four phones, 30 minutes (exit criterion 1) | |

## Decisions made while building

- **The icon is a sailfish's raised dorsal fin.** It is drawn by `ios/icon/make_icon.py`, which needs the Pillow library. Edit the script and rerun it to change the icon.
- **One LiveKit room per channel.** Changing channel leaves one room and joins the other. It is simple and quick on a LAN. The captain's all-call across channels, in Stage 3, will need more than this.
- **Mute uses Apple's voice-processing mute.** iOS plays its own mute and unmute tones, and it reports speech while muted, which is what drives the "you're muted" reminder. The app's own tones cover the other events: joined, lost, reminder, warnings, and the talk latch in PTT.
- **A gate after noise suppression** does VOX and PTT by replacing the audio with silence. It also closes when muted, as a second lock. VOX opens at -42 dB with 400 ms of hangover; both are for Stage 2 to tune.
- **Discovery carries the Mac's name.** The Bonjour record includes the Mac's `.local` name and the control port, and the app uses those. No address is typed or stored anywhere.
- **Session set to the hands-free profile only**, as the proposal says. A settings switch allows the phone's loudspeaker for testing without a headset.
- **The Xcode project is generated** from `ios/project.yml` with XcodeGen, installed through Homebrew.

## Known limits

- **A Live Activity can only be started while the app is on screen.** A join that happens in a pocket shows nothing on the lock screen until the app is next opened. iOS also ends Live Activities after about eight hours.
- **Found on the first phone run, 2026-11-14.** Swiping the app away left the card in the Dynamic Island saying Live although the app was gone. The app now removes the card and leaves the boat as it closes, and every card expires 90 seconds after its last refresh.
- **Joining with the phone locked, seen 2026-11-14.** Launched from the Mac onto a phone that then locked, the app joined and dropped every few seconds with no microphone track. The likely cause is iOS refusing to start the microphone for an app that is not on screen; the app's log could not be read to confirm it. The app now stays on the boat and listens when the microphone will not start, says so on screen, and tries again when it comes on screen or the big button is tapped. Failed joins also back off, from 3 seconds up to 30. If the cause is right, joining on sight in a pocket only works while the app is already running with its audio alive. Whether a locked phone can even hear the others in that state is untested.
- **PTT and the roster.** Someone in PTT who is not talking shows as live on the web roster, because the gate is on the phone and the server cannot see it.
- **The headset button does not work on the OpenComm2, seen 2026-11-14.** While the app is on the boat, the multifunction button does nothing. With the app closed, the same button starts the app. The likely reason: while the intercom holds the headset in its hands-free profile, the button sends a call command (hang up), and iOS only passes those to an app that has a call registered through CallKit. With the app closed the headset is in its music profile, where the button sends play, which iOS hands to the last app that showed a Now Playing card. CallKit is the fallback the proposal names.
- **The boom mute button as the hands-free mute, built 2026-11-15, not yet tried on a headset.** With the headset button ruled out, the OpenComm2's own mute button is the one control the crew can reach without looking. The phone is never told about it, so the app infers it: a second and a half of pure digital silence from a Bluetooth headset's microphone is taken as a mute on the headset, and the first sound afterwards ends it. While it lasts the app shows MUTED with "On the headset", the lock-screen card says Muted, and the phone reports it to the boat as a participant attribute (`mic` = `headset-muted`), which the roster and the other phones show as muted. The audio track is left alone, because muting it would hide the sound that ends the state. The app's own mute is refused meanwhile, with the spoken words "Muted on the headset". Two things decide whether this works and neither is known: whether the OpenComm2's mute really delivers pure silence after iOS's voice processing, and whether a live microphone in a quiet room ever does. The app logs the microphone's quietest level and longest pure silence every 30 seconds to settle both. Rehearsed in the simulator only, where every microphone is silent. **First try on the OpenComm2, 2026-11-15: recognised only rarely**, 4 times in some 30 to 40 presses. The phone's log shows why. Live in a quiet room, the headset never read below about -81 dB and never gave pure silence, so false alarms are not the problem. Muted, it gave pure silence only now and then; mostly it left a hiss at about -90 to -96 dB, one step of a 16-bit sample, which the pure-silence test rejects. **Second build, same day, not yet tried:** the test is now a level, -86 dB, held for a second and a half, and the mute ends at the first block above -80 dB. The log also counts blocks by level every 30 seconds, to show how much room there really is between muted and quiet. **Second try on the OpenComm2, 2026-11-15: worked, by the phone's log.** All four mutes were recognised, about 1.5 seconds after each press, and all four unmutes; a full minute of mute held with no flicker, and 90 seconds live and quiet raised no false mute. The level counts show a clean split. Muted, 3018 of 3020 blocks in half a minute sat between -95 and -90 dB, the loudest at -90. Live and quiet, about 99 in 100 blocks were above -85 dB, and none below -90. So the -86 dB line has roughly 4 dB of room on each side in a quiet room, and boat noise can only widen the live side. On the phone it seemed to work reliably. Not known: what the roster and the other phone showed, and whether another OpenComm2 or another headset model mutes the same way. The control service must be restarted for phones to be allowed to report the mute.
- **The media card is gone, 2026-11-14.** The app used to put a Now Playing card on the lock screen, because iOS sends a headset's play/pause press to the app that owns one. The OpenComm2 test showed that press never arrives while the intercom is running, so the card only duplicated the Live Activity's Mute button, with a pause symbol and two dead skip buttons. It was also why a button press could start the closed app. `HeadsetButton.swift` is deleted. Two things went with it: the centre button on wired earbuds no longer mutes, and when there is no Live Activity (a join in a pocket, or after iOS ends it at about eight hours) the lock screen has no Vela control.
- **CallKit experiment, 2026-11-14 and 15. Dropped on 2026-11-15 and the code removed** (`CallSession.swift`, the Settings switch and the `voip` background mode; the second try is in the repository's first commit). It did work in the end, one press toggling mute about a second later, but the phone shows an active call on its lock screen the whole time, every press ends and restarts that call, and other apps cannot play sound. What follows is the record. Settings had a switch, "Headset button through a phone call", off by default. With it on, the app registers the session with iOS as an outgoing call named after the boat and lets iOS switch the audio on before LiveKit starts. The code is `ios/Vela/Model/CallSession.swift`. The app needed the `voip` background mode for iOS to accept the call.
  - **First try, refusing the hang-up: failed on the iPhone Air with the OpenComm2.** The call showed, sound reached the iPad, and the first press of the multifunction button toggled mute. But iOS ended the call although the app refused the request: the call indicator went away, a second press showed Live in the app with nothing reaching the iPad, and a third press started the music player. So the press does arrive, and a refusal does not keep the call.
  - **Second try, built the same evening, not yet tried on a phone.** The app accepts the hang-up, starts a new call at once, waits for iOS to switch the audio back on, and only then counts the press. Expect a gap in sound on every press while the call and the headset link restart. The log line "Call restarted in N ms" gives its length. To find out: how long the gap is, whether sound comes back in both directions, and whether the mute tone is heard.
  - **Second try on the iPhone Air with the OpenComm2, 2026-11-15: failed.** A press made the app leave the boat and rejoin, and afterwards it showed "weak signal". The audio server's log agrees: after the rejoin the phone's microphone audio arrived at about 20 packets a second where 50 are expected, with about a quarter lost. The rejoin is the app's own fall-back for a call that would not restart; why it would not restart, and why the audio is choppy afterwards, is not known, because the phone's log could not be read.
  - **Third build, 2026-11-15.** The app now writes its log to `Documents/vela-log.txt` on the phone, which the Mac can copy off (the command is at the top of `ios/Vela/Model/EventLog.swift`). The log records every call event, route change, interruption and quality change, with the state of the audio. The restart also asks iOS again for up to two seconds if a new call is refused straight after the old one ends.
  - **Third build on the iPhone Air with the OpenComm2, 2026-11-15: the press worked, by the phone's log.** One press at 09:12:04. iOS refused the first request for a new call with CallKit error 7 (too many calls: it was still counting the old one) and accepted the second, 270 ms later. The audio was switched off for 88 ms, the headset stayed on its hands-free link, and mute toggled 1013 ms after the press. No rejoin and no error. So the earlier rejoin was the refused first request. Not yet known: what it sounded like, whether a second press unmutes, and what quick repeated presses do.
  - **"Weak signal" is not only about the press.** In the same log it appeared 35 seconds after joining, before any press and on the phone's own microphone, and cleared within 15 seconds. Cause unknown; one suspect is the quality score reacting to silence suppression (DTX).
  - **Known costs.** The phone shows a call the whole time, other apps cannot play sound, the End button in the system's call display counts as a press, and End & Accept on an incoming phone call ends the intercom's call, which the app then tries to restart. Hold & Accept mutes the intercom and gives it back afterwards. The call is kept while a lost boat is being looked for, so the app stays alive; Settings now offers Leave in that state too.
  - **Simulator.** It has no call screen and ends every call itself, so only the call starting and the fall-back to plain audio were checked there. The restart was not.
- **Started unseen by the headset button, seen 2026-11-14.** With the app swiped away, a press of the OpenComm2 button started it in the background. It joined muted, put a media control on the lock screen, and dropped off the roster about 40 seconds later, when iOS suspended it. The app now joins only after it has been on screen once since it started. Checked in the simulator only that a normal launch still joins; the background start itself has not been retested.
- **The "you're muted" reminder came only once, seen 2026-11-14.** The reminder was limited to once a minute, and unmuting did not reset that. Each new mute now gets its own reminder, and the reminder is the two-note cue followed by the spoken words "You're muted". Someone who stays muted and keeps talking is still reminded only once a minute.
- **Simulator audio hangs on this Mac.** Launch with `-noAudioDevice YES` to run without an audio device, and `-micFailures 2` to make the first two microphone starts fail. In that mode the first join times out after ten seconds and the retry succeeds; with a real audio device the first join connected.
- **Audio server down.** The control service now checks LiveKit before handing out a token, so the app says the boat's audio server is not answering.
- **Development keys.** LiveKit runs with its placeholder key, and the control service has no authentication. Fine at home, not for the dock.

## Result

- Exit criterion 1:
- Exit criterion 3:
- What Stage 2 needs to know:
