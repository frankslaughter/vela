# Vela test bench

For one person testing several phones. Built 2026-11-15.

Alone, you can hold one phone. The test bench stands in for the people at the others: each phone reports what it is sending and hearing, the Mac supplies voices to hear, and one page shows the result and records it.

The page is at `http://<the Mac's name>.local:7890/test`. `server/start.sh` prints the address.

## A solo session

1. Start the servers with `server/start.sh` and open the test page.
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
- **Sending**: whether its microphone track is putting packets on the wire, and whether the audio server hears it talking. A muted phone shows "stopped"; that is correct.
- **Hearing**: one line for each person or voice on its channel. "Packets" says whether audio is arriving. "Sound" is the level of what arrived and when something audible was last heard. "Lost" is packets that never came. "Patched over" is the share of audio the phone had to invent to cover them.
- **Buttons**: Mute, Unmute, Next mode and Next channel act on that phone within two seconds. Log opens the phone's own log.

A phone that has not reported for seven seconds is shown as not reporting, with no numbers, because old numbers would look like good news. That is what a phone looks like when iOS has suspended the app, which is the thing the pocket test is looking for.

## A run

A run saves every report for its length and ends with a verdict for each phone. A phone passes if it:

- never stopped reporting for more than 10 seconds,
- was on the boat at least 99% of the time,
- never lost the boat, and
- never went more than 10 seconds without packets from a test voice.

Each run leaves a folder under `server/logs/runs/`, named by its start time:

- `report.md`: the verdict and the numbers, readable as it is.
- `summary.json` and `samples.jsonl`: the same, and every report, for a closer look.
- `recordings/`: one WAV file for each phone's microphone, if recording was on. Stretches with no audio at all are left out, so a file can be shorter than the run.

Phone logs arrive every ten seconds while Test mode is on, in `server/logs/phones/`. Nothing under `server/logs/` is kept in git.

## How it works

- **Reports.** A phone in test mode posts to `/api/report` every two seconds. It sends LiveKit's own receive statistics for each track it is subscribed to, which only ever grow; the server works out the change between reports. The reply carries any commands waiting for that phone.
- **Test voices.** Ordinary participants run by the control service, named `vela-voice-<channel>`. They speak with the Mac's `say` command. Phones show them as "Test voice 1" and so on.
- **Recording.** The control service already sits in every channel as a hidden listener, to know who is talking. During a recorded run it also writes what it receives.
- **Code.** `server/testbench.py`, `server/test.html`, and `ios/Vela/Model/Intercom+Testing.swift`.

## Limits

- **What it cannot judge.** How the intercom sounds to a person, beyond the one headset you wear, and two real people talking near each other.
- **Locked.** A phone reports itself locked only if it has a passcode, and about ten seconds after it locks.
- **Test voices are heard by everyone on the channel.** Stop them before real people use the intercom.
- **No protection.** The control service has no authentication, so anyone on the same network can mute a phone that has Test mode on. Fine at home; turn Test mode off at the dock.
- **Recordings are of people's voices.** They are only made when the box is ticked, and they stay on the Mac.
- **Four phones.** Exit criterion 1 needs four. The test voices add load but are not phones.

## Checked so far

On 2026-11-15, on spare ports: two scripted stand-ins for phones and the app in the simulator all reported, heard each other and the test voice, obeyed a command, and uploaded a log; a 30-second recorded run passed and wrote its report and recordings. Not yet tried with real phones.
