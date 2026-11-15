"""Vela test bench: lets one person test several phones.

A person alone can hold one phone. This module stands in for the people at the others:

- Phones in test mode report every two seconds what they are sending and hearing.
  The reply carries any commands waiting for them, so the Mac can mute a phone
  that is locked in a pocket.
- Test voices join each channel from the Mac and say the time, so every phone
  always has something to hear.
- A run records every report for a set time and ends with a verdict per phone.
- A recording saves what each phone's microphone sent, to listen to afterwards.
- Phones send their logs here, so nothing has to be copied off them.

Everything is kept in memory or under logs/. None of it is on unless a phone has
its Test mode switch on, or someone presses a button on the test page.
"""

from __future__ import annotations

import asyncio
import json
import math
import re
import tempfile
import time
import wave
from datetime import datetime
from pathlib import Path

from livekit import api, rtc

# Test voices are ordinary participants, so phones show them. This marks them as not people.
VOICE_PREFIX = "vela-voice-"

REPORT_INTERVAL = 2.0
# A phone that has not reported for this long is shown as silent.
STALE_AFTER = 7.0
# Limits a run must stay within for a phone to pass.
MAX_REPORT_GAP = 10.0
MAX_HEARING_GAP = 10.0
MIN_CONNECTED = 0.99

COMMANDS = {"mute", "unmute", "mode", "channel"}
SAFE_NAME = re.compile(r"[^A-Za-z0-9-]+")


def _db(level: float) -> float | None:
    return round(20 * math.log10(level), 1) if level > 0 else None


def _safe(text: str) -> str:
    return SAFE_NAME.sub("-", text).strip("-")[:40] or "phone"


class TestBench:
    def __init__(self, settings: dict, logs_dir: Path) -> None:
        self.settings = settings
        self.logs_dir = logs_dir
        self.devices: dict[str, dict] = {}  # device_id -> latest report and what was worked out from it
        self.commands: dict[str, list[dict]] = {}
        self.voice_tasks: list[asyncio.Task] = []
        self.run: dict | None = None
        self.last_run: dict | None = None
        self.run_task: asyncio.Task | None = None
        # (channel, identity) -> (name, track), kept current by the activity monitor.
        self.tracks: dict[tuple[str, str], tuple[str, rtc.Track]] = {}
        self.recordings: dict[tuple[str, str], asyncio.Task] = {}
        self.recording_dir: Path | None = None
        # Filled in by the control service: who the audio server says is talking.
        self.speaking: dict[str, str] = {}

    # ---- Reports from phones ----

    def accept_report(self, report: dict) -> list[dict]:
        """Stores a phone's report, works out what changed since the last, and returns its commands."""
        device_id = report["device_id"]
        now = time.time()
        device = self.devices.setdefault(device_id, {"hearing": {}, "sent": {}, "first_seen": now})
        previous = device.get("report") or {}
        device["report"] = report
        device["received"] = now

        # Sending: is the phone's own microphone track putting packets on the wire?
        sent = report.get("sent") or {}
        before = (previous.get("sent") or {}).get("packets")
        packets = sent.get("packets")
        device["sent"] = {
            "flowing": packets is not None and before is not None and packets > before,
            "known": packets is not None,
        }

        # Hearing: for each person the phone is subscribed to, what arrived since the last report.
        earlier = {h["identity"]: h for h in previous.get("hearing") or []}
        hearing: dict[str, dict] = {}
        for h in report.get("hearing") or []:
            identity = h["identity"]
            old = earlier.get(identity) or {}
            state = dict(device["hearing"].get(identity) or {})
            state["name"] = h.get("name") or identity
            state["voice"] = identity.startswith(VOICE_PREFIX)

            def delta(key: str) -> float | None:
                a, b = old.get(key), h.get(key)
                if a is None or b is None or b < a:  # counters restart when the phone rejoins
                    return None
                return b - a

            got, lost = delta("packets"), delta("lost")
            samples, concealed = delta("samples"), delta("concealed")
            energy, duration = delta("energy"), delta("duration")
            state["flowing"] = bool(got)
            state["packets"] = got
            state["lost"] = lost
            state["concealed_fraction"] = (concealed / samples) if samples and concealed is not None else None
            level = math.sqrt(energy / duration) if energy and duration else 0.0
            state["level_db"] = _db(level)
            if got:
                state["packets_at"] = now
            if level > 0.003:  # about -50 dB: somebody is audibly speaking
                state["heard_at"] = now
            hearing[identity] = state
        device["hearing"] = hearing

        if self.run is not None:
            self._record_sample(device_id, device, now)
        return self.commands.pop(device_id, [])

    def queue_command(self, device_id: str, action: str) -> None:
        if action not in COMMANDS:
            raise ValueError(f"unknown command {action}")
        self.commands.setdefault(device_id, []).append({"action": action})

    # ---- Logs from phones ----

    def log_path(self, device_id: str) -> Path:
        name = (self.devices.get(device_id, {}).get("report") or {}).get("name", "phone")
        return self.logs_dir / "phones" / f"{_safe(name)}-{device_id[:8]}.log"

    def append_log(self, device_id: str, name: str, lines: list[str]) -> None:
        self.devices.setdefault(device_id, {"hearing": {}, "sent": {}, "first_seen": time.time()}).setdefault(
            "report", {"device_id": device_id, "name": name}
        )
        path = self.logs_dir / "phones" / f"{_safe(name)}-{device_id[:8]}.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a") as f:
            f.writelines(line.rstrip("\n") + "\n" for line in lines)

    def read_log(self, device_id: str, lines: int = 400) -> str:
        path = self.log_path(device_id)
        if not path.exists():
            return "No log from this phone yet."
        return "".join(path.read_text().splitlines(keepends=True)[-lines:])

    # ---- Test voices ----

    @property
    def voices_on(self) -> bool:
        return any(not t.done() for t in self.voice_tasks)

    def start_voices(self) -> None:
        if self.voices_on:
            return
        self.voice_tasks = [
            asyncio.create_task(self._voice(channel, number))
            for number, channel in enumerate(self.settings["channels"], start=1)
        ]

    async def stop_voices(self) -> None:
        for task in self.voice_tasks:
            task.cancel()
        await asyncio.gather(*self.voice_tasks, return_exceptions=True)
        self.voice_tasks = []

    async def _voice(self, channel: str, number: int) -> None:
        """Joins a channel and says the time every six seconds, with silence in between."""
        url = f"ws://127.0.0.1:{self.settings['livekit_port']}"
        rate, block = 48000, 480  # 10 ms
        while True:
            room = rtc.Room()
            try:
                token = (
                    api.AccessToken(self.settings["api_key"], self.settings["api_secret"])
                    .with_identity(f"{VOICE_PREFIX}{channel}")
                    .with_name(f"Test voice {number}")
                    .with_grants(api.VideoGrants(room_join=True, room=channel))
                    .to_jwt()
                )
                await room.connect(url, token, rtc.RoomOptions(auto_subscribe=False))
                source = rtc.AudioSource(rate, 1)
                track = rtc.LocalAudioTrack.create_audio_track("voice", source)
                await room.local_participant.publish_track(
                    track, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
                )
                silence = bytes(block * 2)
                while True:
                    clock = datetime.now()
                    words = f"Voice {number}. {clock.hour % 12 or 12} {clock.minute:02d} and {clock.second} seconds."
                    speech = await self._speak(words, rate)
                    cycle = max(6.0, len(speech) / 2 / rate + 2.0)
                    for start in range(0, int(cycle * rate) * 2, block * 2):
                        chunk = speech[start : start + block * 2]
                        if len(chunk) < block * 2:
                            chunk = chunk + silence[: block * 2 - len(chunk)]
                        await source.capture_frame(rtc.AudioFrame(chunk, rate, 1, block))
            except asyncio.CancelledError:
                await room.disconnect()
                raise
            except Exception:
                await room.disconnect()
                await asyncio.sleep(2)  # the audio server restarted; come back

    @staticmethod
    async def _speak(words: str, rate: int) -> bytes:
        """The Mac's own speech, as 16-bit mono samples."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "speech.wav"
            process = await asyncio.create_subprocess_exec(
                "say", "-o", str(path), f"--data-format=LEI16@{rate}", words,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
            )
            await process.wait()
            if process.returncode != 0 or not path.exists():
                return b""
            with wave.open(str(path), "rb") as f:
                return f.readframes(f.getnframes())

    # ---- Recording what each phone's microphone sent ----

    def track_added(self, channel: str, identity: str, name: str, track: rtc.Track) -> None:
        self.tracks[(channel, identity)] = (name, track)
        if self.recording_dir is not None:
            self._record(channel, identity)

    def track_removed(self, channel: str, identity: str) -> None:
        self.tracks.pop((channel, identity), None)
        task = self.recordings.pop((channel, identity), None)
        if task:
            task.cancel()

    def start_recording(self, folder: Path) -> None:
        folder.mkdir(parents=True, exist_ok=True)
        self.recording_dir = folder
        for channel, identity in list(self.tracks):
            self._record(channel, identity)

    async def stop_recording(self) -> None:
        self.recording_dir = None
        tasks = list(self.recordings.values())
        self.recordings = {}
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    def _record(self, channel: str, identity: str) -> None:
        if identity.startswith(VOICE_PREFIX) or (channel, identity) in self.recordings:
            return
        name, track = self.tracks[(channel, identity)]
        stamp = datetime.now().strftime("%H%M%S")
        path = self.recording_dir / f"{_safe(name)}-{identity[:8]}-{channel}-{stamp}.wav"
        self.recordings[(channel, identity)] = asyncio.create_task(self._write_wav(track, path))

    @staticmethod
    async def _write_wav(track: rtc.Track, path: Path) -> None:
        """Writes the track as it arrives. Stretches with no audio at all are not in the file."""
        stream = rtc.AudioStream(track, sample_rate=16000, num_channels=1)
        out = wave.open(str(path), "wb")
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16000)
        try:
            async for event in stream:
                out.writeframes(bytes(event.frame.data))
        finally:
            out.close()
            await stream.aclose()

    # ---- Runs ----

    async def start_run(self, minutes: float, record: bool) -> dict:
        if self.run is not None:
            await self.stop_run()
        started = time.time()
        run_id = datetime.fromtimestamp(started).strftime("%Y-%m-%d-%H%M%S")
        folder = self.logs_dir / "runs" / run_id
        folder.mkdir(parents=True, exist_ok=True)
        self.run = {
            "id": run_id,
            "started": started,
            "ends": started + minutes * 60,
            "minutes": minutes,
            "recording": record,
            "voices": self.voices_on,
            "folder": str(folder),
            "samples": {},  # device_id -> list of samples
            "talking": {},  # identity -> seconds the audio server heard them
        }
        if record:
            self.start_recording(folder / "recordings")
        self.run_task = asyncio.create_task(self._watch_run())
        return self.run_view()

    async def _watch_run(self) -> None:
        run = self.run
        while self.run is run and time.time() < run["ends"]:
            await asyncio.sleep(1)
            for identity in self.speaking:
                run["talking"][identity] = run["talking"].get(identity, 0) + 1
        if self.run is run:
            await self.stop_run(finished=True)

    async def stop_run(self, finished: bool = False) -> dict | None:
        run = self.run
        if run is None:
            return self.last_run
        self.run = None
        if self.run_task and not finished:
            self.run_task.cancel()
        if run["recording"]:
            await self.stop_recording()
        ended = time.time() if not finished else run["ends"]
        summary = self._summarise(run, ended)
        folder = Path(run["folder"])
        (folder / "summary.json").write_text(json.dumps(summary, indent=2))
        (folder / "report.md").write_text(self._report_text(summary))
        with open(folder / "samples.jsonl", "w") as f:
            for device_id, samples in run["samples"].items():
                for sample in samples:
                    f.write(json.dumps({"device": device_id, **sample}) + "\n")
        self.last_run = summary
        return summary

    def _record_sample(self, device_id: str, device: dict, now: float) -> None:
        report = device["report"]
        self.run["samples"].setdefault(device_id, []).append(
            {
                "t": round(now, 2),
                "name": report.get("name"),
                "phase": report.get("phase"),
                "channel": report.get("channel"),
                "app": report.get("app_state"),
                "locked": report.get("locked"),
                "battery": report.get("battery"),
                "route": report.get("route_in"),
                "quality": report.get("quality"),
                "drops": report.get("drops"),
                "joins": report.get("joins"),
                "sending": device["sent"]["flowing"],
                "hearing": {
                    identity: {
                        "voice": h["voice"],
                        "flowing": h["flowing"],
                        "packets": h["packets"],
                        "lost": h["lost"],
                        "concealed": h["concealed_fraction"],
                        "level_db": h["level_db"],
                    }
                    for identity, h in device["hearing"].items()
                },
            }
        )

    @staticmethod
    def _longest_gap(times: list[float], start: float, end: float) -> float:
        """The longest stretch between `start` and `end` with none of `times` in it."""
        edges = [start, *sorted(t for t in times if start <= t <= end), end]
        return max(b - a for a, b in zip(edges, edges[1:]))

    def _summarise(self, run: dict, ended: float) -> dict:
        started = run["started"]
        length = max(ended - started, 1)
        phones = []
        for device_id, samples in run["samples"].items():
            times = [s["t"] for s in samples]
            connected = [s for s in samples if s["phase"] == "connected"]
            fraction = lambda items: round(len(items) / len(samples), 4) if samples else 0.0  # noqa: E731
            batteries = [s["battery"] for s in samples if s["battery"] is not None]
            drops = [s["drops"] for s in samples if s["drops"] is not None]

            sources: dict[str, dict] = {}
            for identity in {i for s in samples for i in s["hearing"]}:
                seen = [(s["t"], s["hearing"][identity]) for s in samples if identity in s["hearing"]]
                got = sum(h["packets"] or 0 for _, h in seen)
                lost = sum(h["lost"] or 0 for _, h in seen)
                concealed = [h["concealed"] for _, h in seen if h["concealed"] is not None]
                sources[identity] = {
                    "voice": seen[0][1]["voice"],
                    "longest_gap": round(self._longest_gap([t for t, h in seen if h["flowing"]], started, ended), 1),
                    "flowing": round(sum(1 for _, h in seen if h["flowing"]) / len(seen), 4),
                    "loss": round(lost / (got + lost), 4) if got + lost else None,
                    "concealed": round(sum(concealed) / len(concealed), 4) if concealed else None,
                }

            problems = []
            report_gap = round(self._longest_gap(times, started, ended), 1)
            if report_gap > MAX_REPORT_GAP:
                problems.append(f"stopped reporting for {report_gap:.0f} s")
            if fraction(connected) < MIN_CONNECTED:
                problems.append(f"on the boat only {fraction(connected):.0%} of the time")
            if drops and drops[-1] > drops[0]:
                problems.append(f"lost the boat {drops[-1] - drops[0]} times")
            voices = {i: s for i, s in sources.items() if s["voice"]}
            if run["voices"] and not voices:
                problems.append("never heard a test voice")
            for identity, source in voices.items():
                if source["longest_gap"] > MAX_HEARING_GAP:
                    problems.append(f"heard nothing from a test voice for {source['longest_gap']:.0f} s")

            phones.append(
                {
                    "device_id": device_id,
                    "name": samples[-1]["name"],
                    "passed": not problems,
                    "problems": problems,
                    "reports": len(samples),
                    "longest_report_gap": report_gap,
                    "connected": fraction(connected),
                    "locked": fraction([s for s in samples if s["locked"]]),
                    "in_background": fraction([s for s in samples if s["app"] != "active"]),
                    "sending": fraction([s for s in samples if s["sending"]]),
                    "talking_seconds": run["talking"].get(device_id, 0),
                    "drops": (drops[-1] - drops[0]) if drops else None,
                    "battery_start": batteries[0] if batteries else None,
                    "battery_end": batteries[-1] if batteries else None,
                    "routes": sorted({s["route"] for s in samples if s["route"]}),
                    "sources": sources,
                }
            )
        return {
            "id": run["id"],
            "started": started,
            "ended": ended,
            "seconds": round(length),
            "planned_minutes": run["minutes"],
            "voices": run["voices"],
            "recording": run["recording"],
            "folder": run["folder"],
            "passed": bool(phones) and all(p["passed"] for p in phones),
            "phones": sorted(phones, key=lambda p: (p["name"] or "").lower()),
        }

    @staticmethod
    def _report_text(summary: dict) -> str:
        when = datetime.fromtimestamp(summary["started"]).strftime("%Y-%m-%d %H:%M")
        lines = [
            f"# Vela test run {summary['id']}",
            "",
            f"Started {when}, ran {summary['seconds'] // 60} min {summary['seconds'] % 60} s"
            f" of {summary['planned_minutes']:g} planned.",
            f"Test voices {'on' if summary['voices'] else 'off'}. Recording {'on' if summary['recording'] else 'off'}.",
            "",
            f"**Result: {'pass' if summary['passed'] else 'fail' if summary['phones'] else 'no phones reported'}**",
            "",
            "| Phone | Result | On the boat | Locked | Sending | Longest report gap | Lost the boat | Battery |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for p in summary["phones"]:
            battery = (
                f"{p['battery_start']:.0%} to {p['battery_end']:.0%}" if p["battery_start"] is not None else "unknown"
            )
            lines.append(
                f"| {p['name']} | {'Pass' if p['passed'] else 'Fail: ' + '; '.join(p['problems'])} "
                f"| {p['connected']:.1%} | {p['locked']:.0%} | {p['sending']:.0%} "
                f"| {p['longest_report_gap']:.0f} s | {p['drops'] if p['drops'] is not None else 'unknown'} | {battery} |"
            )
        lines += ["", "## What each phone heard", "", "| Phone | From | Packets flowing | Longest gap | Lost | Patched over |", "|---|---|---|---|---|---|"]
        names = {p["device_id"]: p["name"] for p in summary["phones"]}
        for p in summary["phones"]:
            for identity, s in sorted(p["sources"].items()):
                source = "a test voice" if s["voice"] else names.get(identity, identity[:8])
                loss = f"{s['loss']:.2%}" if s["loss"] is not None else "unknown"
                patched = f"{s['concealed']:.2%}" if s["concealed"] is not None else "unknown"
                lines.append(
                    f"| {p['name']} | {source} | {s['flowing']:.1%} | {s['longest_gap']:.0f} s | {loss} | {patched} |"
                )
        lines += [
            "",
            f"A phone passes if it never stopped reporting for more than {MAX_REPORT_GAP:.0f} s, was on the boat"
            f" at least {MIN_CONNECTED:.0%} of the time, never lost the boat, and never went more than"
            f" {MAX_HEARING_GAP:.0f} s without packets from a test voice.",
            "\"Patched over\" is the share of audio the phone had to invent to cover missing packets.",
            "",
        ]
        return "\n".join(lines)

    # ---- What the test page shows ----

    def run_view(self) -> dict | None:
        if self.run is None:
            return None
        return {
            "id": self.run["id"],
            "started": self.run["started"],
            "ends": self.run["ends"],
            "minutes": self.run["minutes"],
            "recording": self.run["recording"],
        }

    def view(self) -> dict:
        now = time.time()
        phones = []
        for device_id, device in self.devices.items():
            report = device.get("report") or {}
            age = now - device["received"] if "received" in device else None
            hearing = []
            for identity, h in sorted(device["hearing"].items(), key=lambda item: item[1]["name"].lower()):
                hearing.append(
                    {
                        "identity": identity,
                        "name": h["name"],
                        "voice": h["voice"],
                        "flowing": h["flowing"],
                        "level_db": h["level_db"],
                        "heard_ago": round(now - h["heard_at"], 1) if "heard_at" in h else None,
                        "packets_ago": round(now - h["packets_at"], 1) if "packets_at" in h else None,
                        "loss": (h["lost"] / (h["packets"] + h["lost"])) if h["packets"] and h["lost"] else 0.0,
                        "concealed": h["concealed_fraction"],
                    }
                )
            phones.append(
                {
                    "device_id": device_id,
                    "name": report.get("name", device_id[:8]),
                    "age": round(age, 1) if age is not None else None,
                    "stale": age is None or age > STALE_AFTER,
                    "phase": report.get("phase"),
                    "channel": report.get("channel"),
                    "mode": report.get("mode"),
                    "muted": report.get("muted"),
                    "headset_muted": report.get("headset_muted"),
                    "mic_unavailable": report.get("mic_unavailable"),
                    "app_state": report.get("app_state"),
                    "locked": report.get("locked"),
                    "battery": report.get("battery"),
                    "charging": report.get("charging"),
                    "route_in": report.get("route_in"),
                    "route_out": report.get("route_out"),
                    "quality": report.get("quality"),
                    "mic_level_db": report.get("mic_level_db"),
                    "version": report.get("version"),
                    "sending": device["sent"].get("flowing", False),
                    "talking": device_id in self.speaking,
                    "hearing": hearing,
                    "commands_waiting": len(self.commands.get(device_id, [])),
                }
            )
        return {
            "now": now,
            "voices": self.voices_on,
            "recording": self.recording_dir is not None,
            "run": self.run_view(),
            "last_run": self.last_run,
            "phones": sorted(phones, key=lambda p: p["name"].lower()),
        }

    async def shutdown(self) -> None:
        if self.run is not None:
            await self.stop_run()
        await self.stop_voices()
        await self.stop_recording()
