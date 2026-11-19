# Vela test bench

For one person testing several phones. Built 2026-11-15.

Alone, you can hold one phone. The test bench stands in for the people at the others: each phone reports what it is sending and hearing, the Mac supplies voices to hear, and one page shows the result and records it.

The page is at `http://<the Mac's name>.local:7890/test`. `server/start.sh` prints the address.

## A solo session

1. Start the servers with `server/start.sh` and open the test page. Locked phones that were on the boat rejoin by themselves after a restart (fixed and tried 2026-11-18, with gaps of seven seconds and of three minutes). After half an hour without the boat a phone stops waiting and rejoins when Vela is next opened.
2. On each phone, open Vela, go to Settings and turn on **Test mode**. The phone appears on the page within a few seconds. The app's header shows "test mode".
3. Press **Start test voices**. A voice joins each channel and says the time every six seconds.
4. Turn each spare phone's volume to zero, lock it, and put it in a pocket, a bag or another room. What a phone hears is measured inside the app, so zero volume hides nothing and nothing feeds back.
5. Wear the headset on the phone you keep, and listen to the voices say the time. Dropouts and delay are audible directly.
6. Set the length, tick **Record each phone's microphone** if you want to listen afterwards, and press **Start run**.
7. Do whatever the test is: wait, walk out of Wi-Fi range and back, mute a phone from the page.
8. When the run ends, the verdict appears under **Last run**.

## What the page shows

For each phone:

- **Chips**: on the boat or not, locked or on screen, headset or phone microphone, battery, link quality, and the mute state.
- **Sending**: whether its microphone track is putting packets on the wire, and whether the audio server hears it talking. A phone muted in the app still shows "flowing": it goes on sending packets of silence, and the audio server stops passing them on, so the other phones' "Hearing" lines for it show "stopped". A phone with no working microphone shows "stopped" here. The "Lost" figure on this line is the share of the phone's own packets, since it joined, that the audio server says never arrived.
- **Hearing**: one line for each person or voice on its channel. "Packets" says whether audio is arriving. "Sound" is the level of what arrived and when something audible was last heard. "Lost" is packets that never came. "Patched over" is the share of audio the phone had to invent to cover them. "Behind" is how long audio waits in the phone before it is heard.
- **During a run** two more chips appear. "Ping" is the slowest answer from that phone in the last two seconds, and goes red over 60 ms or when one is lost. An answer that comes late counts as slow, not lost. "Audio stalled" appears when the phone's own audio stood still for 60 ms or more.
- **Buttons**: Mute, Unmute, Next mode and Next channel act on that phone within two seconds. Log opens the phone's own log.

A phone whose Settings have **Silence suppression** or **Redundancy** switched off, under Sending, shows a chip saying so. Both should be on except for the test below.

A phone that has not reported for seven seconds is shown as not reporting, with no numbers, because old numbers would look like good news. That is what a phone looks like when iOS has suspended the app, which is the thing the pocket test is looking for.

## A run

A run saves every report for its length and ends with a verdict for each phone. A phone passes if it:

- never stopped reporting for more than 10 seconds,
- was on the boat at least 99% of the time,
- never lost the boat, and
- never went more than 10 seconds without packets from a test voice.

Each run leaves a folder under `server/logs/runs/`, named by its start time:

- `report.md`: the verdict and the numbers, readable as it is. It ends with every moment of lost or patched audio and what the network and the phone's audio were doing then: a slow or lost ping points at the network, an audio stall with a quick ping points at the phone. "Lost on the way" is the share of each phone's own packets that never reached the audio server; it does not decide pass or fail.
- `summary.json` and `samples.jsonl`: the same, and every report, for a closer look.
- `recordings/`: one WAV file for each phone's microphone, if recording was on. Stretches with no audio at all are left out, so a file can be shorter than the run.

Phone logs arrive every ten seconds while Test mode is on, in `server/logs/phones/`. Nothing under `server/logs/` is kept in git.

## Finding the lost packets

On 2026-11-16 about half the iPad's packets never reached the audio server, mostly in quiet stretches; see `docs/stage-1-log.md`. To find out whether silence suppression or redundancy is behind it:

Use the iPad on its own microphone in a quiet room, which is where the loss was seen. The iPhone Air on a headset lost nothing on 2026-11-17.

Result, 2026-11-17: neither phone lost anything in any of the three settings, so the settings are not the cause. The sessions that did lose packets had been muted; see `docs/stage-1-log.md`. A mute in mid-session and a muted join were both clean the same evening. So was a muted start, on both phones. The loss is unexplained and has not been seen since 2026-11-16; "Lost" on the Sending line is how it will be noticed if it comes back.

1. Join with one phone, unmuted, Test mode on. Talk for a minute with pauses, and note "Lost" on its Sending line.
2. In the phone's Settings, under Sending, turn **Silence suppression** off. The phone rejoins and the count starts again. Do the same minute and note the figure.
3. Turn it back on, turn **Redundancy** off, and do the minute again.
4. Turn both back on.

A recorded run during each minute keeps the microphone audio, to hear whether word beginnings are clipped.

## How it works

- **Reports.** A phone in test mode posts to `/api/report` every two seconds. It sends LiveKit's own receive statistics for each track it is subscribed to, which only ever grow; the server works out the change between reports. The reply carries any commands waiting for that phone.
- **Test voices.** Ordinary participants run by the control service, named `vela-voice-<channel>`. They speak with the Mac's `say` command. Phones show them as "Test voice 1" and so on. Each voice checks every round that the control service's listener is hearing it, and starts again if it has not been heard for 90 seconds, or if the clock has jumped.
- **The Mac stays awake.** `server/start.sh` keeps the Mac from going to sleep by itself for as long as it runs. Closing the lid still puts it to sleep.
- **Timing the network.** During a run the control service pings each phone five times a second, at the address its reports come from. The address is not kept. With silence suppression on, the pings themselves keep a locked phone's radio a little more awake than it would be.
- **Events.** Test voices starting, stopping and restarting are written to `server/logs/testbench.log`.
- **Recording.** The control service already sits in every channel as a hidden listener, to know who is talking. During a recorded run it also writes what it receives.
- **Code.** `server/testbench.py`, `server/test.html`, and `ios/Vela/Model/Intercom+Testing.swift`.

## Limits

- **What it cannot judge.** How the intercom sounds to a person, beyond the one headset you wear, and two real people talking near each other.
- **Locked.** A phone reports itself locked only if it has a passcode, and about ten seconds after it locks.
- **An iPad in a case.** Closing a keyboard case or cover cuts the iPad's microphone in hardware and suspends the app. Lock an iPad with its top button and leave the case open.
- **Test voices are heard by everyone on the channel.** Stop them before real people use the intercom.
- **No protection.** The control service has no authentication, so anyone on the same network can mute a phone that has Test mode on. Fine at home; turn Test mode off at the dock.
- **Recordings are of people's voices.** They are only made when the box is ticked, and they stay on the Mac.
- **Four phones.** Exit criterion 1 needs four. The test voices add load but are not phones.

## Checked so far

On 2026-11-15, on spare ports: two scripted stand-ins for phones and the app in the simulator all reported, heard each other and the test voice, obeyed a command, and uploaded a log; a 30-second recorded run passed and wrote its report and recordings.

The same evening, a first five-minute run with the iPhone Air and the iPad: both reported, Mute and Unmute from the page reached the iPad, both logs arrived, and both microphones were recorded. The run failed, correctly, because the iPad went silent for 69 seconds; see `docs/stage-1-log.md`. The test voices were off for that run, so it did not check hearing.

On 2026-11-16, in the simulator on spare ports: the two Sending switches were read, logged and shown on the page, and the page showed the phone's own loss as 0%. The simulator has no real microphone, so whether switching silence suppression off changes what a phone sends is not checked.

On 2026-11-17 the first try on the iPhone Air showed that the Silence suppression switch had no effect; see `docs/stage-1-log.md`. After the fix, in the simulator on spare ports, the audio server's answer left silence suppression off when the switch was off. Not yet tried on a phone.
