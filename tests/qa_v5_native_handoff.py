#!/usr/bin/env python3
"""Native-only courier handoff and persisted-cargo acceptance driver.

Do not launch until the lead freezes production/assets and grants the GUI slot.
Pass --ready to acknowledge that release. Reuses the actual XTest/Xorg driver
and real Godot Master tap from qa_v5_native_dialogue, without game APIs, state
injection, edited saves, fixed FPS, or speedup. Each capture needs a fresh game
process because the bounded Master tap records once per launch.

Commands are native-driver JSON lines plus capture_start/capture_stop, mark,
check_saved, ledger_baseline, check_ledger, and check_contract. Save observations
are read-only copies of files written by the actual game. Check failures remain
in the event log and summary; they do not silently become successes.
"""
import argparse
import hashlib
import json
import os
import pathlib
import sys
import time

import qa_v5_native_dialogue as dialogue

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_OUT = ROOT / "docs/qa/v5/robot-handoff-native"
LEDGER_KEYS = ["credits", "inventory", "deliveries", "jobs_today", "settled_ids",
               "last_settlement", "history", "research", "design", "launcher"]


def hashes():
    files = [ROOT / "project.godot"]
    for folder in ["scripts", "scenes", "assets/2d_v5", "assets/audio", "assets/fonts"]:
        files.extend(p for p in (ROOT/folder).rglob("*")
                     if p.is_file() and p.suffix not in [".import", ".uid"])
    files.extend(ROOT/p for p in ["tools/qa_audio_game.gd", "tools/qa_native_regression.py",
        "tests/qa_v5_native_dialogue.py", "tests/qa_v5_native_handoff.py"])
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(files))}


def ledger(saved):
    result = {k:saved.get(k) for k in LEDGER_KEYS}
    result["contract_rewards"] = {c["contract_id"]: c.get("reward")
                                  for c in saved.get("contracts", [])}
    return result


class NativeHandoff(dialogue.NativeDialogue):
    def __init__(self):
        os.environ.setdefault("SC_QA_RUN", "v5-native-handoff-"+str(int(time.time())))
        os.environ.setdefault("SC_QA_DISPLAY", "430")
        os.environ.setdefault("SC_QA_OUT", "docs/qa/v5/robot-handoff-native")
        os.environ.setdefault("SC_QA_RESOLUTION", "1280x800")
        target = (ROOT / os.environ["SC_QA_OUT"]).resolve()
        if not target.is_relative_to(BASE_OUT.resolve()):
            raise ValueError("Handoff evidence must stay under "+str(BASE_OUT))
        if int(os.environ["SC_QA_DISPLAY"]) < 430:
            raise ValueError("Use a fresh dedicated display >=430")
        dialogue.hashes = hashes
        self.baselines = {}
        self.captured_this_process = False
        super().__init__()
        self._rename_metadata()

    def _rename_metadata(self):
        for suffix in ["source-metadata.json", "validation-summary.json", "command-events.jsonl"]:
            old = self.out/("dialogue-"+suffix)
            if old.exists():
                old.replace(self.out/("handoff-"+suffix))

    def execute(self, command):
        original = dict(command)
        begin = time.time()
        if "capture_start" in command:
            if self.captured_this_process:
                raise RuntimeError("Actual Master tap records once per process; native close/restart first")
            self.start_capture(command.pop("capture_start"))
            self.captured_this_process = True
        if "mark" in command:
            self.marks.append({"label": command.pop("mark"), "unix_seconds": time.time()})
        checks = {k: command.pop(k) for k in ["check_saved", "ledger_baseline", "check_ledger", "check_contract"] if k in command}
        stop = command.pop("capture_stop", False)
        result = self.send(command)
        if "start" in command:
            self.captured_this_process = False
        if checks:
            saved = self.send({"state":True,"sleep":0})["state"]
            results = []
            if "ledger_baseline" in checks:
                key = str(checks["ledger_baseline"])
                self.baselines[key] = ledger(saved)
                dialogue.dump(self.out/(key+"-ledger-baseline.json"), self.baselines[key])
                result["ledger_baseline"] = key
            if "check_ledger" in checks:
                key = str(checks["check_ledger"])
                observed = ledger(saved)
                expected = self.baselines[key]
                results.append({"test":"ledger unchanged from "+key,
                    "passed":observed==expected,
                    "changed_fields":[k for k in expected if expected[k]!=observed[k]],
                    "observed":observed})
            if "check_contract" in checks:
                spec = checks["check_contract"]
                actual = next((x for x in saved.get("contracts",[]) if x.get("contract_id")==spec["id"]),None)
                values = {k:actual.get(k) if actual else None for k in spec["equals"]}
                results.append({"test":spec["test"], "passed":values==spec["equals"], "observed":values})
            if "check_saved" in checks:
                spec = checks["check_saved"]
                value = saved
                missing = None
                try:
                    for key in spec["path"]:value=value[key]
                except (KeyError, IndexError, TypeError):
                    value=None;missing=spec["path"]
                results.append({"test":spec["test"], "passed":missing is None and value==spec["equals"],
                                "observed":value,"missing_path":missing})
            self.checks.extend(results)
            result["checks"] = results
        if stop:
            result["capture"] = self.stop_capture()
        event = {"begin_unix_seconds":begin,"end_unix_seconds":time.time(),"command":original,"result":result}
        self.commands.append(event)
        with (self.out/"handoff-command-events.jsonl").open("a") as stream:
            stream.write(json.dumps(event,ensure_ascii=False)+"\n")
        return result

    def close(self):
        super().close()
        self._rename_metadata()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready",action="store_true",help="Lead explicitly released frozen production/assets and this GUI slot")
    parser.add_argument("--replay",type=pathlib.Path)
    args=parser.parse_args()
    if not args.ready:parser.error("Wait for explicit freeze/GUI-slot release, then pass --ready")
    capture=NativeHandoff()
    try:
        print(json.dumps(capture.ready,ensure_ascii=False),flush=True)
        commands=json.loads(args.replay.read_text()) if args.replay else (json.loads(line) for line in sys.stdin)
        for original in commands:
            try:
                result=capture.execute(dict(original))
            except Exception as exc:
                result={"harness_error":repr(exc),"command":original}
                with (capture.out/"harness-errors.jsonl").open("a") as stream:
                    stream.write(json.dumps(result,ensure_ascii=False)+"\n")
                print(json.dumps(result,ensure_ascii=False),flush=True)
                raise
            print(json.dumps(result,ensure_ascii=False),flush=True)
            if original.get("quit"):break
    finally:capture.close()


if __name__=="__main__":main()
