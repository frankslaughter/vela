"""Vela control service.

Advertises the boat over Bonjour, mints LiveKit tokens for phones that ask to
join, listens for who is talking, and serves the roster. Everything it needs to know comes from
settings.toml; nothing here refers to a machine by address.
"""

from __future__ import annotations

import asyncio
import os
import re
import subprocess
import time
import tomllib
from contextlib import asynccontextmanager
from datetime import timedelta
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, PlainTextResponse
from livekit import api, rtc
from pydantic import BaseModel, Field

from testbench import VOICE_PREFIX, TestBench

HERE = Path(__file__).resolve().parent
SETTINGS_PATH = Path(os.environ.get("VELA_SETTINGS", HERE / "settings.toml"))

# Permanent: the contract between the apps and the base station.
SERVICE_TYPE = "_vela._tcp"

TOKEN_LIFETIME = timedelta(hours=24)
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")
# The control service's own seat in each channel. Phones never see it.
MONITOR_IDENTITY = "vela-monitor"


# Each connection to the audio server gets a UDP port of its own from this range. With one port
# shared by every phone, the Mac discarded about a fifth of one phone's audio whenever the port
# had just been used to talk to another: found by a capture on 2026-11-19, docs/stage-2-log.md.
# A connection holds about twenty ports, one for each of the Mac's addresses, and a phone makes
# two connections. Counted on 2026-11-19: 84 ports for the control service's four seats. So six
# phones and the seats need about 350, and the range leaves plenty of room.
DEFAULT_UDP_PORT_RANGE = (20000, 21999)


def udp_ports(livekit: dict) -> tuple[int | None, tuple[int, int] | None]:
    """The single UDP port, or the range of them. A range unless settings.toml asks for the single port."""
    wanted = livekit.get("rtc_udp_port_range")
    if wanted is None:
        if "rtc_udp_port" in livekit:
            return int(livekit["rtc_udp_port"]), None
        return None, DEFAULT_UDP_PORT_RANGE
    if not (isinstance(wanted, list) and len(wanted) == 2 and all(isinstance(p, int) for p in wanted)
            and 1024 <= wanted[0] < wanted[1] <= 65535):
        raise SystemExit("settings.toml: rtc_udp_port_range must be two port numbers, the lower first")
    return None, (wanted[0], wanted[1])


def load_settings() -> dict:
    with open(SETTINGS_PATH, "rb") as f:
        s = tomllib.load(f)
    channels = s.get("channels") or ["all"]
    udp_port, udp_port_range = udp_ports(s.get("livekit", {}))
    return {
        "boat_name": s.get("boat_name", "Unnamed Boat"),
        "assistant_name": s.get("assistant_name", "Vela"),
        "channels": channels,
        "control_port": s.get("control", {}).get("port", 7890),
        "livekit_port": s.get("livekit", {}).get("port", 7880),
        # Media ports. The defaults are LiveKit's own; they only need naming to move them.
        "livekit_tcp_port": s.get("livekit", {}).get("rtc_tcp_port", 7881),
        "livekit_udp_port": udp_port,
        "livekit_udp_port_range": udp_port_range,
        "api_key": s.get("livekit", {}).get("api_key", "devkey"),
        "api_secret": s.get("livekit", {}).get("api_secret", "secret"),
    }


SETTINGS = load_settings()


def local_host_name() -> str:
    """The Mac's Bonjour name, for example MacBook-Pro.local."""
    name = subprocess.run(
        ["scutil", "--get", "LocalHostName"], capture_output=True, text=True, check=True
    ).stdout.strip()
    return f"{name}.local"


class Advertiser:
    """Registers the boat with macOS's own Bonjour responder.

    The system follows the Mac across networks and address changes, so the
    service never has to know an address.
    """

    def __init__(self) -> None:
        self.process: subprocess.Popen | None = None

    def start(self) -> None:
        host = local_host_name()
        self.process = subprocess.Popen(
            [
                "dns-sd", "-R", SETTINGS["boat_name"], SERVICE_TYPE, "local",
                str(SETTINGS["control_port"]),
                f"boat={SETTINGS['boat_name']}",
                f"host={host}",
                f"port={SETTINGS['control_port']}",
                "v=1",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def stop(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()


advertiser = Advertiser()
bench = TestBench(SETTINGS, HERE / "logs")


class ActivityMonitor:
    """Knows who is talking, by sitting in every channel as a hidden participant.

    LiveKit's server API lists people and their mute state, but not speech. Someone in a
    room is told which of the people they are listening to are speaking, so the control
    service takes a seat: hidden from the phones, publishing nothing. It has to subscribe
    to everyone's microphone to be told about them; the audio it receives is not used.
    """

    def __init__(self) -> None:
        self.speaking: dict[str, str] = {}  # identity -> channel
        self.last_spoke: dict[str, float] = {}  # identity -> time
        self.listening: dict[str, bool] = {}  # channel -> seat taken
        self.tasks: list[asyncio.Task] = []

    def start(self) -> None:
        self.tasks = [asyncio.create_task(self._watch(c)) for c in SETTINGS["channels"]]

    async def stop(self) -> None:
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)

    def snapshot(self) -> dict:
        return {
            "listening": bool(self.listening) and all(self.listening.values()),
            "speaking": sorted(self.speaking),
            "last_spoke": self.last_spoke,
        }

    def _set_speakers(self, channel: str, identities: set[str]) -> None:
        now = time.time()
        for identity in [i for i, c in self.speaking.items() if c == channel and i not in identities]:
            del self.speaking[identity]
            self.last_spoke[identity] = now  # when they stopped
        for identity in identities:
            self.speaking[identity] = channel
            self.last_spoke[identity] = now

    async def _watch(self, channel: str) -> None:
        url = f"ws://127.0.0.1:{SETTINGS['livekit_port']}"
        while True:
            room = rtc.Room()
            gone = asyncio.Event()
            room.on("disconnected", lambda *_: gone.set())
            # The test bench records from these when a recording is on.
            room.on(
                "track_subscribed",
                lambda track, _publication, participant: bench.track_added(
                    channel, participant.identity, participant.name or participant.identity, track
                )
                if track.kind == rtc.TrackKind.KIND_AUDIO
                else None,
            )
            room.on(
                "track_unsubscribed",
                lambda _track, _publication, participant: bench.track_removed(channel, participant.identity),
            )
            room.on(
                "active_speakers_changed",
                lambda speakers: self._set_speakers(channel, {p.identity for p in speakers}),
            )
            token = (
                api.AccessToken(SETTINGS["api_key"], SETTINGS["api_secret"])
                .with_identity(MONITOR_IDENTITY)
                .with_grants(
                    api.VideoGrants(
                        room_join=True, room=channel, hidden=True,
                        can_publish=False, can_publish_data=False,
                    )
                )
                .with_ttl(TOKEN_LIFETIME)
                .to_jwt()
            )
            try:
                await room.connect(url, token, rtc.RoomOptions(auto_subscribe=True))
                self.listening[channel] = True
                await gone.wait()
            except asyncio.CancelledError:
                await room.disconnect()
                raise
            except Exception:
                pass  # the audio server is down or restarting; try again shortly
            self.listening[channel] = False
            self._set_speakers(channel, set())
            for key in [k for k in bench.tracks if k[0] == channel]:
                bench.track_removed(*key)
            await asyncio.sleep(2)


monitor = ActivityMonitor()
bench.speaking = monitor.speaking  # the same dictionary: the bench reads who is talking
bench.last_spoke = monitor.last_spoke  # and when each was last heard, so a test voice can check it is
bench.is_listening = lambda: monitor.snapshot()["listening"]

# device_id -> what we last knew about that phone. In memory only for now.
devices: dict[str, dict] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    advertiser.start()
    app.state.livekit = api.LiveKitAPI(
        f"http://127.0.0.1:{SETTINGS['livekit_port']}",
        SETTINGS["api_key"],
        SETTINGS["api_secret"],
    )
    monitor.start()
    try:
        yield
    finally:
        advertiser.stop()
        await bench.shutdown()
        await monitor.stop()
        await app.state.livekit.aclose()


app = FastAPI(title="Vela control", lifespan=lifespan)


class JoinRequest(BaseModel):
    device_id: str = Field(description="Stable per-install identifier chosen by the app")
    name: str = Field(description="Display name the person typed")
    channel: str | None = Field(default=None, description="Channel to join; default is the first")


def request_host(request: Request) -> str:
    """The name the phone used to reach us, so the LiveKit URL uses the same one."""
    host = request.headers.get("host", "")
    if host.startswith("["):  # bracketed IPv6 literal
        return host[: host.index("]") + 1]
    return host.rsplit(":", 1)[0] if ":" in host else host


@app.get("/api/info")
async def info() -> dict:
    return {
        "boat": SETTINGS["boat_name"],
        "assistant": SETTINGS["assistant_name"],
        "channels": SETTINGS["channels"],
    }


@app.post("/api/join")
async def join(body: JoinRequest, request: Request) -> dict:
    if not DEVICE_ID_PATTERN.match(body.device_id):
        raise HTTPException(400, "device_id must be 8-64 letters, digits or hyphens")
    name = " ".join(body.name.split())[:24]
    if not name:
        raise HTTPException(400, "name is required")
    channel = body.channel if body.channel in SETTINGS["channels"] else SETTINGS["channels"][0]

    # A token is no use if the audio server is down, and the phone's own error for that is obscure.
    try:
        await asyncio.wait_for(request.app.state.livekit.room.list_rooms(api.ListRoomsRequest()), timeout=2)
    except Exception:
        raise HTTPException(503, "The boat's audio server is not answering. Restart Vela on the base station.")

    token = (
        api.AccessToken(SETTINGS["api_key"], SETTINGS["api_secret"])
        .with_identity(body.device_id)
        .with_name(name)
        # A phone sets its own attributes to report a mute made on the headset itself.
        .with_grants(api.VideoGrants(room_join=True, room=channel, can_update_own_metadata=True))
        .with_ttl(TOKEN_LIFETIME)
        .to_jwt()
    )
    devices[body.device_id] = {"name": name, "channel": channel, "joined": time.time()}

    return {
        "boat": SETTINGS["boat_name"],
        "assistant": SETTINGS["assistant_name"],
        "channels": SETTINGS["channels"],
        "channel": channel,
        "identity": body.device_id,
        "name": name,
        "livekit_url": f"ws://{request_host(request)}:{SETTINGS['livekit_port']}",
        "token": token,
    }


async def channel_roster(lk: api.LiveKitAPI, channel: str) -> list[dict]:
    try:
        res = await lk.room.list_participants(api.ListParticipantsRequest(room=channel))
    except api.TwirpError as e:
        if e.code == "not_found":  # nobody has joined this channel yet
            return []
        raise
    people = []
    for p in res.participants:
        if p.identity == MONITOR_IDENTITY or p.permission.hidden:
            continue  # our own listening seat
        mics = [t for t in p.tracks if t.source == api.TrackSource.MICROPHONE]
        # The phone's own report on its microphone: "headset-muted" when the headset is sending
        # silence, a mute on its boom; "off" when the microphone is not delivering audio at all.
        mic = p.attributes.get("mic")
        headset_muted = mic == "headset-muted"
        people.append(
            {
                "identity": p.identity,
                "name": p.name or p.identity,
                # No published mic counts as muted: nothing of theirs can be heard.
                "muted": headset_muted or mic == "off" or not mics or all(t.muted for t in mics),
                "headset_muted": headset_muted,
                "mic_off": mic == "off",
                # A test voice from the Mac, not a person.
                "voice": p.identity.startswith(VOICE_PREFIX),
                "joined_at": p.joined_at,
                "speaking": p.identity in monitor.speaking,
                "last_spoke": monitor.last_spoke.get(p.identity),
                "attributes": dict(p.attributes),
            }
        )
    return sorted(people, key=lambda x: x["name"].lower())


@app.get("/api/roster")
async def roster(request: Request) -> dict:
    lk: api.LiveKitAPI = request.app.state.livekit
    try:
        lists = await asyncio.gather(*(channel_roster(lk, c) for c in SETTINGS["channels"]))
    except Exception as e:  # LiveKit not running, most likely
        return {"boat": SETTINGS["boat_name"], "ok": False, "error": str(e) or type(e).__name__, "channels": []}
    return {
        "boat": SETTINGS["boat_name"],
        "ok": True,
        # False while the control service has no listening seat, so speech is unknown.
        "listening": monitor.snapshot()["listening"],
        "channels": [{"name": c, "people": people} for c, people in zip(SETTINGS["channels"], lists)],
    }


@app.get("/api/activity")
async def activity() -> dict:
    """Who is talking right now. Answered from memory, so it can be asked several times a second."""
    return monitor.snapshot()


@app.get("/")
async def roster_page() -> FileResponse:
    # no-cache: the browser must ask each time whether the page has changed, or it shows an old one after an update.
    return FileResponse(HERE / "roster.html", headers={"Cache-Control": "no-cache"})


# ---- Test bench: one person testing several phones. See testbench.py. ----


class LogLines(BaseModel):
    device_id: str
    name: str = "phone"
    lines: list[str] = Field(max_length=2000)


class VoicesRequest(BaseModel):
    on: bool


class RunRequest(BaseModel):
    minutes: float = Field(default=30, gt=0, le=600)
    record: bool = False


class CommandRequest(BaseModel):
    device_id: str
    action: str


def checked_device_id(device_id: str) -> str:
    if not DEVICE_ID_PATTERN.match(device_id):
        raise HTTPException(400, "device_id must be 8-64 letters, digits or hyphens")
    return device_id


@app.post("/api/report")
async def report(body: dict, request: Request) -> dict:
    """A phone in test mode says what it is sending and hearing. The reply carries its commands."""
    checked_device_id(str(body.get("device_id", "")))
    # Where the report came from is where the bench pings during a run. Nothing is stored.
    address = request.client.host if request.client else None
    return {"commands": bench.accept_report(body, address)}


@app.post("/api/log")
async def phone_log(body: LogLines) -> dict:
    bench.append_log(checked_device_id(body.device_id), body.name, body.lines)
    return {"ok": True}


@app.get("/api/test")
async def test_state() -> dict:
    return {"boat": SETTINGS["boat_name"], "channels": SETTINGS["channels"], **bench.view()}


@app.post("/api/test/voices")
async def test_voices(body: VoicesRequest) -> dict:
    if body.on:
        bench.start_voices()
    else:
        await bench.stop_voices()
    return {"voices": bench.voices_on}


@app.post("/api/test/run")
async def test_run(body: RunRequest) -> dict:
    return {"run": await bench.start_run(body.minutes, body.record)}


@app.post("/api/test/run/stop")
async def test_run_stop() -> dict:
    return {"last_run": await bench.stop_run()}


@app.post("/api/test/command")
async def test_command(body: CommandRequest) -> dict:
    try:
        bench.queue_command(checked_device_id(body.device_id), body.action)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


@app.get("/api/test/log/{device_id}", response_class=PlainTextResponse)
async def test_log(device_id: str) -> str:
    return bench.read_log(checked_device_id(device_id))


@app.get("/test")
async def test_page() -> FileResponse:
    return FileResponse(HERE / "test.html", headers={"Cache-Control": "no-cache"})
