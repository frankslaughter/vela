# Stage 2 log: latency and noise

Started 2026-11-19. Done when exit criteria 2 and 4 pass: the delay from mouth to ear measured, under 250 ms on Bluetooth and under 150 ms wired, and Open, VOX and PTT holding up against boat noise.

**Status, 2026-11-19: the delay is measured on each Bluetooth side separately, not yet with Bluetooth at both ends. The estimate for both ends is about 255 ms, at the limit. The noise test on the headset shows the three modes doing the right thing, but about a quarter of the iPhone's audio is going missing on the way, so clipped word beginnings cannot be judged yet.**

## How the delay is measured

The Mac records with its own microphone in QuickTime. A clap or a sharp "PA" beside it is heard directly, and again when it comes out of the listening device. The gap is the delay. The listening device is muted in Vela so that it does not send the sound back. Each recording has five claps and five spoken sounds.

## First recordings, 2026-11-19 at about 16:18 to 16:22

| Recording | Talker | Listener | Delay |
|---|---|---|---|
| `latency-1` | iPhone Air, own microphone | iPad, own speaker | 192 ms at the first clap. Then 389, 467, 436, 402, 394 and 375 ms over the next ten seconds |
| `latency-2` | iPhone Air on the OpenComm2 | iPad, own speaker | 222 ms, steady for the whole recording |
| `latency-3` | iPad, own microphone | iPhone Air on the OpenComm2 | 490 ms for the five claps, then 470, 472, 453, 453 and 453 ms for the spoken sounds |

- **Only `latency-2` is clean.** The iPad's speaker fed the sound back into the headset's microphone, so each clap rang on as a train of echoes. The echoes repeat every 222 ms in all five stretches measured, and the first copy of a clap came 221 ms after it.
- **In `latency-1` the delay doubled part way through.** The first clap came back after 192 ms, and the next two left faint traces at the same place. From nine seconds in the copies came 375 to 467 ms late, drifting down. The iPhone's log rates its link as poor at 16:18:20 and excellent again at 16:18:45, which is when this recording was made.
- **`latency-3` followed another poor spell.** The iPhone's link was rated poor at 16:20:45 and excellent at 16:21:00, and the recording began within a minute of that. Its delay steps down by about 20 ms at a time, which is what a player does as it catches up. So 453 to 490 ms is what the delay was at that moment. What it is in a steady link is not known.
- **The link dipped about once a minute**, at 16:16:40, 16:17:15, 16:18:20 and 16:20:45. That is the pattern Stage 1 found for a phone in weak signal that keeps looking for a stronger access point.

## Second recordings, 2026-11-19 at about 16:48 to 16:50

Made in good signal, with test bench run `2026-11-19-164652` going, so each device's own "behind" figure is known for the same seconds.

| Recording | Talker | Listener | Delay | Listener was playing behind by |
|---|---|---|---|---|
| `latency-3b` | iPad, own microphone | iPhone Air on the OpenComm2 | 222 ms: five claps, 221 to 223 ms | 20 ms, steady |
| `latency-1b` | iPhone Air, own microphone | iPad, own speaker | 188 ms: six claps, 185 to 192 ms | 44 to 67 ms |

- **Both are clean.** In each, the listener's link was rated excellent throughout, its "behind" figure held steady, and no ping took over 32 ms.
- **The spoken sounds could not be used.** In `latency-3b` each one overlaps its own copy. In `latency-1b` the copies were too faint to find.
- **In `latency-1b` the iPhone lost 16% of what it sent**, 279 of 1,756 packets, while talking on its own microphone. Its pings were fine and the iPad's "behind" figure did not move, so the delay figure stands. On the headset two minutes earlier it lost 4 of 1,986. The iPhone's link rating fell to poor soon after the headset was switched off, in this session and in the first one. Cause not known.
- **One rough moment between the recordings.** At 16:49:21 a ping to each device took 100 to 170 ms. The iPhone went from 30 ms behind to 255 ms, and was back at 30 ms six seconds later.

## What this says so far

| Path | Delay | Measured |
|---|---|---|
| No Bluetooth: phone's own microphone to the iPad's own speaker | 188 ms | Six claps. The first session's one clean clap gave 192 ms |
| OpenComm2 on the talking side only | 222 ms | First session, steady for 25 seconds |
| OpenComm2 on the listening side only | 222 ms | Five claps |
| OpenComm2 on both sides | about 255 ms | Not measured. Worked out as 222 + 222 - 188 |

- **Each Bluetooth side adds about 35 ms.** That is less than the 40 to 80 ms the proposal allowed.
- **The part without Bluetooth is the larger share, and it is over budget.** The proposal allowed 85 to 150 ms and it measures 188 ms. The listener's "behind" figure accounts for 50 ms of that, as planned. The other 140 ms is in the phones' own audio handling, the coding and the network, and has not been broken down.
- **Bluetooth at both ends comes out at about 255 ms, against a limit of 250 ms.** The proposal's own guide is that under 200 ms sounds like slight reverb and over 300 ms like an echo. The figure rests on three recordings and on taking the iPad's microphone to be as quick as the iPhone's. A recording with headsets on both devices would settle it.
- **A wired earpiece has not been measured.** The 188 ms figure is the nearest stand-in.
- **A rough moment in the Wi-Fi adds 200 to 300 ms for a while.** In the first session it lingered for ten seconds and more. In the second the phone recovered in six.

## Noise test, first try, 2026-11-19 at 17:15 to 17:24: not valid, the headset was off

Boat noise from `stage2/boat-noise.wav` at about 85 dB by the Apple Watch's Noise app, with the room's door shut. Three recorded runs of two minutes: `2026-11-19-171534` in Open, `171851` in VOX, `172144` in PTT.

- **The iPhone was on its own microphone and loudspeaker in all three.** The headset had been switched off for `latency-1b` at 16:49:32 and the phone's log shows no headset after that. The test is meant for the headset's boom microphone, so none of this counts toward criterion 4.
- **Open, on the phone's own microphone:** noise was sent the whole time at about -46 dB, and the loudest speech reached about -30 dB.
- **VOX, on the phone's own microphone:** the noise alone opened the gate for more than half of the first 20 silent seconds. The noise sits at -46 dB with a tenth of it over -44 dB, and the gate opens at -42 dB.
- **PTT:** nothing was sent in the two minutes, which is right for a button that was not held. The lines were spoken from 17:24:08, after the run had ended at 17:23:44, so they were not recorded.
- **The iPhone lost about a quarter of what it sent in all three runs:** 28%, 22% and 24%. In the PTT run no ping was lost and none took over 23 ms, so this is not the Wi-Fi. It is the same loss seen in `latency-1b`, and it has only been seen with the phone on its own microphone. On the headset the same afternoon it lost 4 packets of 1,986. Cause not known.

## Noise test, second try, 2026-11-19 at 17:32 to 17:38: on the headset

Same noise and level. The iPhone was on the OpenComm2 from 17:28:07. Runs `2026-11-19-173202` in Open, `173407` in VOX, `173613` in PTT. A fourth run, `172830`, was begun first and is not used.

| Mode | What was sent in the silences | The spoken lines |
|---|---|---|
| Open | Noise at about -60 dB. A tenth of it is over -56 dB and a hundredth over -50 dB | Peaks of -9 to -13 dB, so 45 to 50 dB above the noise. Seven of eight lines are in the recording |
| VOX | Nothing at all in the 24 silent seconds before the first line, and nothing after the last | All eight lines are in the recording |
| PTT | Nothing while the button was not held | Nine presses by the phone's log. Six carry speech in the recording, and the first three carry almost nothing |

- **The boom microphone makes the difference.** On the phone's own microphone the noise came through at -46 dB and speech stood 15 dB above it. On the headset the noise is at -60 dB and speech stands 45 to 50 dB above it.
- **VOX has room to spare.** It opens at -42 dB. The noise sits 18 dB below that, and its loudest hundredth 8 dB below. Nothing needs tuning on this evidence.
- **The missing lines are not the modes' doing.** Where a line is missing the recording holds pure silence, in Open too, where noise should be heard throughout.
- **About a quarter of the iPhone's audio is missing, in bursts.** The audio server counted 25%, 32% and 25% of the iPhone's packets as never arriving in the three runs. In the Open run's noise-only stretch the recording has 20 holes of pure silence in 55 seconds, from a tenth of a second to 1.4 seconds long, coming every four to four and a half seconds. They add up to 17% of that stretch.
- **No ping was lost in any of the three runs and none took over 21 ms**, so the link itself answers. The first try pointed at the phone's own microphone, but the loss is the same on the headset.
- **It did not begin when the headset was switched off, as first thought.** See the next section.
- **Clipped word beginnings in VOX cannot be judged** from recordings with holes in them.

## The missing audio, looked into the same evening

**The explanation in this section was wrong.** It is kept as a record of the evening. The measurements stand; the cause is in "The capture" below, and the fix in the section after it.

**What it is: a phone that is sending audio and receiving none loses about a quarter of what it sends.** As soon as a steady stream flows to the phone, the loss stops.

- **The test that shows it.** Run `2026-11-19-174826`, two minutes, the iPhone live and locked, the iPad muted. Test voices off for 40 seconds: 20 to 40% of the iPhone's packets lost. Voices on for 40 seconds: about 1%. Voices off again: 20 to 40% within four seconds.
- **The afternoon fits.** In run `164652` the iPhone lost 4 to 23% until 16:48:20, nothing until 16:49:40, and 8 to 54% after. The iPad was unmuted from 16:48:15 to 16:49:36, and at no other time in that run. The 30-minute run of 2026-11-18 was clean because the test voices ran throughout.
- **Over the whole afternoon** the audio server counted 20 to 33% of the iPhone's packets lost in each of its four connections. The iPad lost 8.8% in its first connection, 16:02 to 16:24, and none in its second, so it is not only the iPhone.
- **The losses come in bursts** of one packet up to more than sixty, every four to four and a half seconds. None arrive late or out of order.

**Ruled out:**

- **The headset and the phone's own microphone.** The loss is the same on both.
- **Mute.** The iPhone lost packets while muted, from 16:46:50 to 16:48:20.
- **The radio link, as far as pings can tell.** Pings to the iPhone over IPv4, over IPv6, and from the audio server's own address all came back, 500 of 500 in the longest, none over 22 ms. They were not all taken during a loss, though: see below.
- **The phone throwing packets away.** A new line in the phone's log every ten seconds counts packets discarded before sending. It is 0 throughout.
- **Voice marking.** The app marks its audio as a phone call (DSCP). With a new switch turning that off, the loss was the same: the connectivity checks the phone sends alongside the audio went from 37 of 47 answered to 20 of 47.
- **A second audio server or a full receive buffer on the Mac.** One server holds the port. The Mac's count of UDP packets dropped for a full buffer is 449 in 15 million.
- **The Mac's neighbour table.** Its entry for the phone refreshes normally.

**Seen on the way:**

- **The path matters.** At 18:01:59 the iPhone reconnected and its audio moved from UDP to TCP. From then on nothing was lost, 0 of 2,957 packets in run `180627`, and every connectivity check was answered. TCP sends again whatever goes missing, so this hides the loss; it does not show the link is clean. The pings from the audio server's address were taken in this period and so prove little.
- **The connectivity checks are lost too.** On the UDP path a fifth to more than half of them went unanswered, in step with the audio.
- **The cause is not proved.** What fits everything is the Wi-Fi treating a device that only sends differently from one that also receives, in the phone or in the access point. Showing that needs a capture of the radio, which this Mac cannot make without an administrator's password.

**What it means for the boat.** One person talking while the rest are quiet or muted is the ordinary case, and with silence suppression on, as shipped, quiet people send almost nothing. So a talker would often be receiving nothing, and would be chopped up.

**The fix that follows from the evidence** is for the base station to send every phone a steady stream of silence, so no phone is ever only sending. Built the same evening: see the next section.

**Changes made to the app for this:**

- A third switch under Sending in Settings, **Voice marking**. It is off on the iPhone at the moment and should go back on.
- The ten-second "Sending paths" line in the phone's log, in Test mode.

## The steady stream, built 2026-11-19 and removed the same evening

**This was the wrong fix and is no longer in the code.** The section is kept as a record of what was tried. The cause turned out to be the shared UDP port: see the capture below.

**The base station sent every phone silence without a break.** It was on whenever Vela ran, with nothing to switch on.

- **What it is.** The control service takes a seat in each channel, named "Base station", and sends silence: one small packet every 20 ms, with silence suppression off so that it never thins out. The code is `server/steady.py`.
- **Phones do not show it.** The seat cannot be hidden from phones, because a phone ignores audio from a seat it has not been told about. So the app leaves it out of its list of people and its count, by the seat's identity, `vela-steady`. The roster page leaves it out too.
- **It restarts itself.** It starts again if the audio server restarts or the Mac's clock jumps, as the test voices do.
- **The test bench knows it.** Each phone's card has a "Steady stream" line. A run now also fails a phone that never received the stream, or went more than 10 seconds without it. The page has a button to stop the stream, for a comparison only; it comes back on when Vela restarts.
- **The app, on both devices.** The new build is on the iPhone and the iPad. An older build would show "Base station" as a person.

**Checked on spare ports, with a stand-in for a phone:**

| Check | Result |
|---|---|
| Packets from the stream in 10 seconds | 500, none lost |
| Roster page lists the seat | No |
| Run with the stream on | Passed, stream received |
| Stream switched off, then on | Seat left, then returned and sent again |
| Audio server stopped | Stream noticed within 1 second |
| Audio server started again | Stream back within 10 seconds |

**Tried on the real phones the same evening: it does not stop the loss.** See the next section. A real sleep of the Mac was not tried.

**What it costs.** Each phone's radio now receives 50 small packets a second all the time. A phone in Open mode already sends that many, so the extra battery should be small, but it has not been measured.

## The steady stream on the real phones: the loss is still there

**Run `2026-11-19-195644`, two minutes, the stream on and received by both phones the whole time.**

| Phone | Packets lost on the way | Steady stream received |
|---|---|---|
| iPhone | 15.9% | 100% of the time, none lost |
| iPad | 5.5% | 97% of the time, none lost |

So "a phone that receives audio stops losing what it sends" is wrong, and the stream is not the fix.

**What the evening's measurements do show:**

- **The radio link carries traffic cleanly in both directions.** Pings to both phones at ten a second, over IPv4 and over IPv6 at once, came back 400 of 400 on every stream, none over 30 ms. The bench's own pings, which have never failed, travel over IPv4; the audio travels over IPv6, so IPv6 was tried on purpose. Loss was 14 to 19% a few minutes before these pings and 40% a few minutes after. It was not measured in the same seconds.
- **The loss follows what the other phone is doing.** In run `195644` the iPhone lost about 8% while the iPad was sending 50 packets a second, and about 25% from ten seconds after the iPad dropped to 5 a second. At 20:12:38 the iPad's audio moved from UDP to TCP by itself. Before that, in run `200950`, the iPhone lost 113 of 282 packets. After it, in runs `201618` and `201650`, it lost 4 of 284 and 6 of 276. The iPhone's own path did not change.
- **A phone whose audio goes over TCP loses nothing**, seen twice now: the iPhone at 18:01:59 and the iPad at 20:12:38.
- **The Mac itself discards packets under a system network policy** (the "NECP drop" count in `netstat -s`). It ran at 4.4 a second while the phones were losing, 15 a second for the half minute in which the iPad was reconnecting, and 0.7 a second once the iPad was on TCP. No third-party filter, VPN or firewall is on this Mac. Whether these are the phones' packets is not shown: the same count also rises when apps that are refused multicast are sent multicast, which phones produce when they look for the boat.

**Tried and failed to reproduce on the Mac alone.** A small test with one UDP socket talking to several addresses of the router at once, with and without sends to the Mac's own address in between, lost nothing in 300 to 400 exchanges each way.

**Two explanations are left, and one capture separates them:**

1. The packets reach the Mac and are discarded inside it, when more than one phone uses the audio server's single UDP port.
2. The packets never reach the Mac, for a reason in the Wi-Fi that pings do not show.

A capture of what arrives at the Mac's Wi-Fi interface, taken while the loss is happening, settles it: the packets are either in the capture or they are not. It needs an administrator's password.

## The capture: the packets reach the Mac and are lost inside it

**Taken 2026-11-19, 20:25:02 to 20:26:31, at the Mac's Wi-Fi interface, during run `2026-11-19-202514`.** Both phones were on UDP. The audio server counted the iPhone's loss at 21.1% and the iPad's at 9.2%. The iPad was unmuted and muted again by accident during the run, which does not affect the count.

| Stream in the capture | Numbered | Present | Missing |
|---|---|---|---|
| iPhone's audio arriving at the Mac | 956 | 956 | 0 |
| iPad's audio arriving at the Mac | 424 | 424 | 0 |
| iPhone's audio leaving the Mac for the iPad | 956 | 765 | 191, or 20% |
| Steady stream leaving the Mac, to each phone | 4,454 | 4,454 | 0 |

- **Nothing is lost on the air.** Every audio packet either phone sent is in the capture, in order, none repeated.
- **A fifth of the iPhone's packets go missing between the Mac's Wi-Fi and the audio server's own forwarding.** The 20% missing on the way out matches the 21.1% the audio server reported.
- **So the Wi-Fi, the access point, the headset and the phones are cleared**, and so is everything said earlier about a phone that "only sends". The file is `server/logs/capture.pcap`, which git ignores.

**What the lost packets have in common.** The audio server uses one UDP port for every phone. Matching each of the iPhone's 956 packets to its forwarded copy shows which were lost, and what the Mac did just before each arrived:

| The Mac's previous packet on the Wi-Fi | iPhone packets lost |
|---|---|
| Sent to the iPad: a report, data or a connectivity check | 34 of 40 |
| Sent to the iPhone's own sending connection | 0 of 29 |
| The iPhone's own previous audio packet arriving | 3 of 99 |
| Steady stream sent to the iPhone's listening connection | 111 of 641 |
| Steady stream sent to the iPad's listening connection | 8 of 58 |

A packet from one phone is very likely to be discarded when the shared port has just been used to send a report, data or a check to the other phone, and is safe when the port's last use was that phone's own sending connection. After a steady-stream packet to another connection about one in six is lost. That fits the earlier observations: the loss follows what the other phone is doing, it vanishes when the other phone is on TCP, and the Mac's own count of packets discarded under its network policy rises and falls with it. It also explains why the test voices seemed to help and the steady stream did not: both only changed the order of sends on the shared port.

**Not shown:** whether macOS or the audio server does the discarding. The policy count points at macOS, version 27.0.1. A small test of the same pattern outside the audio server lost nothing, so the exact trigger is not pinned down.

**The fix that follows** is to give every connection its own UDP port, so that a port only ever talks to one phone. The audio server supports it: a range of ports in place of the single one. Checked on a spare audio server: two connections were given ports of their own and audio flowed. Not yet tried on the real phones.

## A UDP port for each connection, built 2026-11-19

**The audio server now gives every connection UDP ports of its own**, from 20000 to 21999, in place of the one shared port 7882. `server/start.sh` writes the range into the audio server's settings, and prints which it is using when it starts. The app is unchanged: a phone is told which port to use when it connects.

- **Why so many ports.** A connection holds about twenty, one for each of the Mac's addresses, and a phone makes two connections. The control service's four seats held 84. Six phones and the seats need about 350.
- **To move the range,** set `rtc_udp_port_range` in `server/settings.toml`. Setting `rtc_udp_port` instead brings back the single shared port, for comparison only.

**Checked on spare ports with two stand-ins for phones:** all six connections were given different ports inside the range, each stand-in received 250 packets in five seconds from the other and from the steady stream, and none was lost.

**On the real phones, the same evening: the loss is gone.** Run `2026-11-19-203521`, one minute, the iPhone live on the headset, the iPad muted, the steady stream on, test voices off.

| | Shared port, run `202514` | A port each, run `203521` |
|---|---|---|
| iPhone's packets lost on the way | 21.1% | 0 of 1,863 |
| iPad's packets lost on the way | 9.2% | 0 of 290 |
| iPhone's connectivity checks answered | a half to four fifths | 50 of 50 |
| iPhone's link rating | good to poor | excellent throughout |
| Packets the Mac discards under its network policy | 4.4 a second | 0.0 a second |

- **Both phones' sending connections were on UDP**, the iPhone's over IPv6 and the iPad's over IPv4, each on a port of its own. The iPhone's listening connection was on TCP.
- **The Mac's policy count fell to nothing**, which ties those discards to the shared port. It is still not shown why macOS 27.0.1 discards on a shared port.
- **One minute with two devices is all this is.** A long run, and more than two phones, have not been tried with the new ports.

**The steady stream was then removed**: `server/steady.py`, its switch and line on the test page, the test bench's check for it, and the line in the app that hid its seat. A one-minute run with the stream off, run `2026-11-19-204058`, both phones muted: the iPhone lost 0 of 284 packets and the iPad 0 of 278. In the same state on the shared port, run `200950`, they lost 113 of 282 and 25 of 282.

The build on both devices still has the line that hides the seat. It does nothing now that the seat is gone, and the next build installed will not have it.

## Still to do

- A longer run on the new ports, as part of the next test that needs one.
- Then one more VOX run, to listen for clipped word beginnings.
- A recording with Bluetooth headsets on both devices, when a second headset is on hand.
