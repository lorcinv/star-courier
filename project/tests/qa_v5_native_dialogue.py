#!/usr/bin/env python3
"""Native-input integrated dialogue evidence, with measured Master-bus A/V sync.

Requires explicit exclusive GUI/source-ready release from the coordinating QA
task. Run with --ready only after that release. One JSON command per stdin line
for inspected-coordinate XTest input; --replay accepts the saved command list.

Extra commands: {"capture_start":"name"}, {"capture_stop":true},
{"mark":"human concerned"}, {"check_saved":{"test":"...","path":[...],
"equals":...}}. Game state is observed only by reading game-written saves. The
audio entry loads the unchanged main scene and records its real Master mixer.
No game APIs, injected engine input, altered saves, fixed FPS, or speedup.
"""
import argparse
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
import wave

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ["project.godot", "scenes/main.tscn", "scripts/main.gd",
    "scripts/economy.gd", "scripts/courier_stories.gd", "scripts/dialogue_panel.gd",
    "scripts/world_view_2d.gd", "scripts/npc_sprite_2d.gd", "scripts/game_hud.gd",
    "tools/qa_audio_game.gd", "tools/qa_native_regression.py",
    "tests/qa_v5_native_dialogue.py"]


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def hashes():
    files = list(SOURCES)
    for directory in ["assets/2d_v5/dialogue", "assets/2d_v5/npcs", "assets/audio"]:
        files += [str(p.relative_to(ROOT)) for p in (ROOT/directory).rglob("*")
                  if p.is_file() and not p.name.endswith(".import")]
    return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sorted(files)}


def pcm_stats(path):
    with wave.open(str(path), "rb") as wav:
        rate, channels, width, frames = wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getnframes()
        if width != 2:
            raise AssertionError("Expected actual signed 16-bit Godot PCM")
        raw = np.frombuffer(wav.readframes(frames), dtype="<i2").astype(np.float64)
    samples = raw / 32768.0
    peak = float(np.max(np.abs(samples))) if len(samples) else 0
    rms = float(np.sqrt(np.mean(samples*samples))) if len(samples) else 0
    return {"rate": rate, "channels": channels, "frames": frames,
            "duration_seconds": frames/rate, "peak": peak, "rms": rms,
            "peak_dbfs": 20*float(np.log10(max(peak, 1e-15))),
            "rms_dbfs": 20*float(np.log10(max(rms, 1e-15))),
            "clipped_samples": int(np.count_nonzero((raw <= -32768) | (raw >= 32767)))}


class NativeDialogue:
    def __init__(self):
        env = dict(os.environ)
        env.setdefault("SC_QA_RUN", "v5-native-dialogue-"+str(int(time.time())))
        env.setdefault("SC_QA_DISPLAY", "394")
        env.setdefault("SC_QA_OUT", "docs/qa/v5/dialogue-integrated")
        env.setdefault("SC_QA_XORG_CONFIG", str(ROOT/"tests/xorg_v5_hud_4k.conf"))
        env.setdefault("SC_QA_RESOLUTION", "1280x800")
        env["SC_QA_ENTRY_SCRIPT"] = "res://tools/qa_audio_game.gd"
        self.out = ROOT/env["SC_QA_OUT"]
        self.out.mkdir(parents=True, exist_ok=True)
        self.audio_path = self.out/"master-recording.wav"
        env["SC_QA_AUDIO_OUTPUT"] = str(self.audio_path)
        self.env = env
        self.started_hashes = hashes()
        self.checks, self.marks, self.commands, self.captures = [], [], [], []
        self.capture = None
        self.child = subprocess.Popen([sys.executable, str(ROOT/"tools/qa_native_regression.py")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, env=env)
        self.ready = self.receive()
        dump(self.out/"dialogue-source-metadata.json", {
            "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "sha256": self.started_hashes, "runtime": env["SC_QA_RUN"],
            "method": "Native Godot main scene, XTest input, game-written save read only, actual Master PCM",
            "fixed_fps": False, "speedup": False, "human_play_claim": False})

    def receive(self):
        line = self.child.stdout.readline()
        if not line:
            raise RuntimeError("Native child exited before replying")
        result = json.loads(line)
        if result.get("error"):
            raise RuntimeError(result["error"])
        if result.get("screenshot"):
            actual = Image.open(result["screenshot"]).size
            geom = result["geometry"]
            if actual != (geom["width"], geom["height"]):
                raise AssertionError("Xorg screenshot is clipped: "+str(actual))
            result["verified_capture_pixels"] = actual
        return result

    def send(self, command):
        self.child.stdin.write(json.dumps(command)+"\n")
        self.child.stdin.flush()
        return self.receive()

    def execute(self, command):
        original = dict(command)
        begin = time.time()
        if "capture_start" in command:
            self.start_capture(command.pop("capture_start"))
        if "mark" in command:
            self.marks.append({"label": command.pop("mark"), "unix_seconds": time.time()})
        spec = command.pop("check_saved", None)
        stop = command.pop("capture_stop", False)
        result = self.send(command)
        if spec:
            saved = self.send({"state": True, "sleep": 0})["state"]
            value = saved
            for key in spec["path"]:
                value = value[key]
            check = {"test": spec["test"], "passed": value == spec["equals"], "observed": value}
            self.checks.append(check)
            result["check"] = check
        if stop:
            result["capture"] = self.stop_capture()
        event = {"begin_unix_seconds": begin, "end_unix_seconds": time.time(),
                 "command": original, "result": result}
        self.commands.append(event)
        with (self.out/"dialogue-command-events.jsonl").open("a") as f:
            f.write(json.dumps(event, ensure_ascii=False)+"\n")
        return result

    def start_capture(self, name):
        if self.capture:
            raise RuntimeError("Capture already active")
        if not name.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Use a simple capture name")
        geom = self.send({"sleep": 0})["geometry"]
        log = (self.out/(name+"-ffmpeg.log")).open("w")
        raw = self.out/(name+"-wallclock.mkv")
        cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "warning", "-y",
            "-use_wallclock_as_timestamps", "1", "-f", "x11grab", "-framerate", "24",
            "-video_size", str(geom["width"])+"x"+str(geom["height"]),
            "-i", "localhost:"+self.env["SC_QA_DISPLAY"]+".0+"+str(geom["x"])+","+str(geom["y"]),
            "-copyts", "-fps_mode", "passthrough", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", "18", "-pix_fmt", "yuv420p", str(raw)]
        started = time.time()
        recorder = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        time.sleep(.5)
        if recorder.poll() is not None:
            raise RuntimeError("ffmpeg exited; inspect "+str(log.name))
        self.capture = {"name": name, "raw": raw, "recorder": recorder,
                        "log": log, "process_started_unix": started, "geometry": geom}
        # Must be outside dialogue: the real modal intentionally consumes keys.
        self.send({"key": "F8", "sleep": .1})

    def stop_capture(self):
        if not self.capture:
            raise RuntimeError("No active capture")
        cap = self.capture
        self.send({"key": "F8", "sleep": .25})
        cap["recorder"].send_signal(signal.SIGINT)
        cap["recorder"].wait(timeout=25)
        cap["log"].close()
        self.capture = None
        lines = (self.out/"game.log").read_text().splitlines()
        starts = [json.loads(s.split("QA_AUDIO_START ", 1)[1]) for s in lines if "QA_AUDIO_START " in s]
        saves = [json.loads(s.split("QA_AUDIO_SAVED ", 1)[1]) for s in lines if "QA_AUDIO_SAVED " in s]
        if not starts or not saves or not self.audio_path.exists():
            raise RuntimeError("Actual Master PCM missing; close dialogue before F8")
        saved_audio = self.out/(cap["name"]+"-master.wav")
        self.audio_path.replace(saved_audio)
        probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-read_intervals", "%+#1",
            "-select_streams", "v:0", "-show_packets", "-of", "json", str(cap["raw"])], text=True))
        first_pts = float(probe["packets"][0]["pts_time"])
        audio_start = float(starts[-1]["unix_seconds"])
        offset = audio_start-first_pts
        if abs(offset) > 5:
            raise AssertionError("Wall-clock timestamp contract failed: "+str(offset))
        video = self.out/(cap["name"]+".mp4")
        delay = max(0, round(offset*1000))
        filter_audio = "adelay="+str(delay)+":all=1,apad" if offset >= 0 else "atrim=start="+str(-offset)+",asetpts=PTS-STARTPTS,apad"
        subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "warning", "-y", "-i", str(cap["raw"]),
            "-i", str(saved_audio), "-filter_complex", "[0:v]setpts=PTS-STARTPTS[v];[1:a]"+filter_audio+"[a]",
            "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(video)], check=True)
        result = {"video": str(video), "actual_master_pcm": str(saved_audio),
            "raw_video": str(cap["raw"]), "video_first_frame_unix": first_pts,
            "audio_start_unix": audio_start, "audio_delay_seconds": offset,
            "audio_saved": saves[-1], "pcm": pcm_stats(saved_audio),
            "geometry": cap["geometry"], "capture_fps": 24,
            "timing_limit": "Video timestamp granularity 1 ms; nominal frames 41.7 ms. Godot tap timing is mixer-start log, not hardware loopback; buffer latency is not independently measured.",
            "subjective_listening_claim": False}
        self.captures.append(result)
        dump(self.out/(cap["name"]+"-capture-metadata.json"), result)
        return result

    def close(self):
        if self.capture:
            self.capture["recorder"].send_signal(signal.SIGINT)
            self.capture["recorder"].wait(timeout=25)
            self.capture["log"].close()
        self.child.stdin.close()
        try:
            self.child.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.child.terminate()
            self.child.wait(timeout=5)
        final_hashes = hashes()
        dump(self.out/"dialogue-validation-summary.json", {
            "method": "Automated native XTest; actual main scene; read-only game-written saves; actual Master PCM",
            "source_unchanged_during_capture": final_hashes == self.started_hashes,
            "changed_sources": [p for p, h in final_hashes.items() if self.started_hashes.get(p) != h],
            "checks": self.checks, "marks": self.marks, "captures": self.captures})
        dump(self.out/"native-replay.json", [e["command"] for e in self.commands])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready", action="store_true", help="Confirm explicit source/GUI release has arrived")
    parser.add_argument("--replay", type=pathlib.Path)
    args = parser.parse_args()
    if not args.ready:
        parser.error("Wait for explicit GUI/source-ready release, then pass --ready")
    c = NativeDialogue()
    try:
        print(json.dumps(c.ready, ensure_ascii=False), flush=True)
        commands = json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for command in commands:
            result = c.execute(command)
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if command.get("quit"):
                break
    finally:
        c.close()


if __name__ == "__main__":
    main()
