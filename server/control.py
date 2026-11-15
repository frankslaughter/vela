"""Vela control service.

Advertises the boat over Bonjour, mints LiveKit tokens for phones that ask to
join, and serves the roster. Everything it needs to know comes from
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
from fastapi.responses import FileResponse
from livekit import api
from pydantic import BaseModel, Field

HERE = Path(__file__).resolve().parent
SETTINGS_PATH = Path(os.environ.get("VELA_SETTINGS", HERE / "settings.toml"))

# Permanent: the contract between the apps and the base station.
SERVICE_TYPE = "_vela._tcp"

TOKEN_LIFETIME = timedelta(hours=24)
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def load_settings() -> dict:
    with open(SETTINGS_PATH, "rb") as f:
        s = tomllib.load(f)
    channels = s.get("channels") or ["all"]
    return {
        "boat_name": s.get("boat_name", "Unnamed Boat"),
        "assistant_name": s.get("assistant_name", "Vela"),
        "channels": channels,
        "control_port": s.get("control", {}).get("port", 7890),
        "livekit_port": s.get("livekit", {}).get("port", 7880),
        # Media ports. The defaults are LiveKit's own; they only need naming to move them.
        "livekit_tcp_port": s.get("livekit", {}).get("rtc_tcp_port", 7881),
        "livekit_udp_port": s.get("livekit", {}).get("rtc_udp_port", 7882),
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
    try:
        yield
    finally:
        advertiser.stop()
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
        .with_grants(api.VideoGrants(room_join=True, room=channel))
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
        mics = [t for t in p.tracks if t.source == api.TrackSource.MICROPHONE]
        people.append(
            {
                "identity": p.identity,
                "name": p.name or p.identity,
                # No published mic counts as muted: nothing of theirs can be heard.
                "muted": not mics or all(t.muted for t in mics),
                "joined_at": p.joined_at,
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
        "channels": [{"name": c, "people": people} for c, people in zip(SETTINGS["channels"], lists)],
    }


@app.get("/")
async def roster_page() -> FileResponse:
    return FileResponse(HERE / "roster.html")
