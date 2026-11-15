# Shokz Headsets for Vela: Comparison

Checked 2026-11-10 against shokz.com product pages and the September 2026 Shokz OpenRun comparison blog. Independent notes come from SoundGuys (OpenComm2 UC, Nov 2023; OpenRun Pro 2, Nov 2024) and the Shokz OpenComm2 FAQ. Prices are shokz.com list prices; the OpenMeet UC was on sale at $119.95 on the day checked.

## What the proposal asks of an earpiece

From [boat-intercom-proposal.md](boat-intercom-proposal.md), section 4, in order: comfort for 12 hours and open-ear; under $200 with spares; tetherable; a mic that survives 10-20 kt apparent wind and spray, IP55 or better; and a button the app can map to mute. Battery has to cover a 10-14 h day. Every model below is a standard Bluetooth hands-free headset, so the app does not care which one a person picks.

## The lineup today

Two things have changed since the proposal was written:

- **OpenComm2 is now sold as "OpenComm2 2025 Upgrade."** Same headset with USB-C charging instead of the magnetic cable, a new Bluetooth name, and Shokz App support. Specs otherwise unchanged. $159.95. The UC variant adds a Loop120 USB dongle for a computer and costs $199.95; the boat does not need it.
- **OpenRun Air 2 launched August 2026.** $129.95, IP67, Bluetooth 6.0, dual AI mics, 10 h. It replaces the original OpenRun as the cheap option.
- **OpenMeet2 launched 2026.** An office headset with a boom. It has no water rating at all, so it is out for the boat despite the best mic claims in the range.

## Comparison

| | OpenComm2 2025 Upgrade | OpenRun Pro 2 | OpenRun Air 2 | OpenRun (original) | OpenMeet2 / OpenMeet UC |
|---|---|---|---|---|---|
| Price | $159.95 | $179.95 | $129.95 | $129.95 | $219.95 / $249.95 UC (OpenMeet UC on sale $119.95) |
| Mic | Boom, DSP noise cancelling, physical mute button on the boom | Dual in-band AI mics, wind-resistant to 25 km/h (about 13.5 kt) per Shokz | Dual in-band AI mics, no wind figure given | Dual in-band noise-cancelling mics | Boom, dual AI mics, 99.4% / 98.6% noise reduction claim |
| Water | IP55 | IP55 | IP67 | IP67 | None stated |
| Battery | 16 h talk, 1 h charge, 5 min = 2 h | 12 h listen, 1 h charge, 5 min = 2.5 h | 10 h, 5 min = 2 h | 8 h, 10 min = 1.5 h | 12 h talk (OpenMeet2), 14 h talk (OpenMeet) |
| Weight | 35 g | 30.3 g | 26.4 g | 26.4 g | 78 g |
| Bluetooth | Multipoint; version not stated for 2025 unit (2023 unit was 5.1) | 5.3, multipoint | 6.0, multipoint | 5.1, multipoint | 6.0 / 5.4, multipoint |
| Buttons | Multifunction, volume up/down, mute on boom | Multifunction, volume up/down | Multifunction, volume up/down | Multifunction, volume up/down | Volume knob, mute, boom-up-to-mute |
| Sizes | One size, no adjustment | Standard and Mini | Standard and Mini | Standard and Mini | One size |
| Fit for boat | Yes, default for crew | Yes, for anglers and anyone who wants no boom | Yes, cheapest spare | Superseded by Air 2 | No |

All of them run the standard hands-free profile with the SBC codec. None has a latency advantage over another; the 160-300 ms Bluetooth budget in the proposal applies equally.

## What the independent reviews add

- **OpenComm2 in wind.** SoundGuys found the boom mic excellent in quiet, street noise nearly gone, and wind audible through the filtering but still acceptable. Shokz claims no wind figure for it. Best Buy owners report clear calls from a truck cab with the windows down. No one has measured it at trolling-speed apparent wind.
- **OpenComm2 fit.** SoundGuys' one real complaint. The frame is one size with no adjustment, and on a smaller head the rear band droops and the weight sits on top of the ears. Anyone with a small head should try one on. That matters for a 12-hour day.
- **OpenRun Pro 2 in wind.** SoundGuys scored the mic as the weak point: fine in quiet, falls flat in wind. Shokz's own 25 km/h figure says the same thing. Apparent wind while trolling is 10-20 kt, so this mic is at or past its limit on the bridge and in the cockpit facing aft. Comfort scored well for multi-hour wear; buttons are hard to tell apart with gloves on.
- **OpenRun Air 2.** No independent mic test yet. Treat it as the Pro 2 mic without the wind claim.

## The mute-button problem with the OpenComm2

The mute button on the OpenComm2 boom mutes the microphone inside the headset. Shokz's own FAQ says it is normal to hear "mute on" in the ear and see no mute icon on the phone. The phone, and therefore the app, never learns about it. That breaks three things in section 6 of the proposal: the roster shows the person live when they are not, the "you're muted" haptic can never fire, and the captain cannot clear a mute they cannot see.

Handling: the app's mute binds to the multifunction button, which the OpenComm2 also has, and the crew is told the boom button is not the mute. It is worth testing in Stage 1 whether the app can detect a locally muted mic as a dead-silent input and warn, because someone will press the boom button anyway. The OpenRun models have no local mute, so they do not have this problem.

## Recommendation

Unchanged from the proposal, with the prices and models updated:

1. **Crew default: OpenComm2 2025 Upgrade, $159.95.** Boom mic, 16 h talk, IP55, mute-button caveat above. Buy the no-dongle version. Confirm head fit before buying several.
2. **Anglers and spares: OpenRun Air 2, $129.95.** IP67 survives a dunk, lightest, newest Bluetooth, and cheap enough that losing one is a shrug. In-band mic will struggle in wind, which is fine for people who mostly listen.
3. **OpenRun Pro 2, $179.95, only for someone who already owns one.** Same IP55 as the OpenComm2 at a higher price with a weaker mic in wind. Nothing it does better matters on the boat.
4. **Skip OpenMeet and OpenMeet2.** No water rating, 78 g, and the mic gain is for office noise, not wind.

For the prototype shopping list in [prototype-plan.md](prototype-plan.md), the two OpenComm2 units stay, and one OpenRun Air 2 is worth adding so Stage 2 measures an in-band mic against the boom in the noise test.

## Sources

- https://shokz.com/pages/product-comparison
- https://shokz.com/products/opencomm2-2025-upgrade
- https://shokz.com/products/openrunpro2
- https://shokz.com/products/openmeet-2
- https://shokz.com/products/openmeet
- https://shokz.com/blogs/news/openrun-air-2-vs-openrun-pro-2-vs-openrun
- https://www.soundguys.com/shokz-opencomm2-uc-review-103856/
- https://www.soundguys.com/shokz-openrun-pro-2-review-127935/
- https://shokz.ae/pages/opencomm-2-faq
