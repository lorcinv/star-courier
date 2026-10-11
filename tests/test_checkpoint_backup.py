"""Offline temporary-fixture tests. Never reads or mutates production repositories."""
import base64
import copy
import importlib.util
import json
import os
import shutil
import zipfile
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).resolve().parents[1] / "tools" / "checkpoint_backup.py"
spec = importlib.util.spec_from_file_location("checkpoint_backup", TOOL)
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


class Remote:
    def __init__(self, parent):
        self.ref = None
        self.blobs = {}
        self.trees = {c.git_hash("tree", b""): []}
        self.commits = {parent: {"sha": parent, "tree": {"sha": c.git_hash("tree", b"")}, "parents": [], "message": "baseline"}}
        self.calls = []

    def reference(self):
        return {"ref": "refs/heads/" + c.BRANCH, "object": {"type": "commit", "sha": self.ref}}

    def receipt(self, action):
        self.calls.append(action["kind"])
        args, tool = action["arguments"], action["tool"]
        if tool == "get_repo":
            result = {"full_name": c.REPOSITORY, "private": True}
        elif tool == "create_branch":
            assert self.ref is None
            self.ref = args["sha"]
            result = self.reference()
        elif tool == "create_blob":
            data = base64.b64decode(args["content"], validate=True)
            sha = c.git_hash("blob", data)
            self.blobs[sha] = data
            result = {"sha": sha}
        elif tool == "create_tree":
            entries = {x["path"]: x for x in self.trees.get(args["base_tree_sha"], [])}
            entries.update({x["path"]: x for x in args["tree_elements"]})
            entries = list(entries.values())
            sha = c.git_tree(entries)
            self.trees[sha] = entries
            result = {"sha": sha}
        elif tool == "create_commit":
            sha = c.git_hash("commit", c.canonical(args))
            result = {"sha": sha, "tree": {"sha": args["tree_sha"]}, "parents": [{"sha": args["parent_sha"]}], "message": args["message"]}
            self.commits[sha] = result
        elif tool == "update_ref":
            assert args["force"] is False
            assert self.ref == args["expected_sha"]
            self.ref = args["sha"]
            result = self.reference()
        elif tool == "fetch":
            url = args["url"]
            if url == f"https://api.github.com/repos/{c.REPOSITORY}":
                result = {"full_name": c.REPOSITORY, "private": True}
            elif "/git/ref/" in url:
                if self.ref is None:
                    return {"status": "not_found", "result": {}}
                result = self.reference()
            elif "/git/commits/" in url:
                result = self.commits[url.rsplit("/", 1)[1]]
            elif "/git/blobs/" in url:
                sha = url.rsplit("/", 1)[1]
                if sha not in self.blobs:
                    return {"status": "not_found", "result": {}}
                result = {"sha": sha, "size": len(self.blobs[sha])}
            elif "/git/trees/" in url:
                sha = url.rsplit("/", 1)[1].split("?")[0]
                if sha not in self.trees:
                    return {"status": "not_found", "result": {}}
                entries = self.recursive(sha) if "?recursive=1" in url else self.trees[sha]
                result = {"sha": sha, "tree": entries, "truncated": False}
            else:
                raise AssertionError(url)
        else:
            raise AssertionError(tool)
        return {"status": "ok", "result": result}

    def recursive(self, sha, prefix=""):
        result = []
        for entry in self.trees[sha]:
            full = {**entry, "path": prefix + entry["path"]}
            result.append(full)
            if entry["type"] == "tree":
                result.extend(self.recursive(entry["sha"], full["path"] + "/"))
        return result


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "source"
        self.source.mkdir()
        self.state = self.base / "state"
        self.parent = "a" * 40
        root = c.git_hash("tree", b"")
        self.metadata = self.base / "baseline.json"
        self.metadata.write_text(json.dumps({"repo": {"full_name": c.REPOSITORY, "private": True},
            "commit": {"sha": self.parent, "tree": {"sha": root}},
            "tree": {"sha": root, "tree": [], "truncated": False}}))
        self.remote = Remote(self.parent)
        self.write("scripts/main.gd", b"extends Node\n")

    def write(self, path, data):
        destination = self.source / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return destination

    def start(self):
        gate = c.Gate(self.state)
        gate.snapshot(self.source, self.metadata, "Fixture checkpoint")
        return gate

    def prepare_drive(self, gate):
        parent = gate.state["parent"]
        base_tree = self.remote.commits[parent]["tree"]["sha"]
        metadata = {"repo": {"full_name": c.REPOSITORY, "private": True},
                    "commit": self.remote.commits[parent],
                    "tree": {"sha": base_tree, "tree": self.remote.recursive(base_tree), "truncated": False}}
        baseline = self.base / (gate.state["snapshot"] + "-baseline.json")
        baseline.write_text(json.dumps(metadata))
        exported = gate.export_drive(baseline, self.base / (gate.state["snapshot"] + "-" + parent + "-delta.zip"))["export"]
        downloaded = self.base / (gate.state["snapshot"] + "-downloaded.zip")
        shutil.copyfile(exported["path"], downloaded)
        return {"snapshot": gate.state["snapshot"], "root_tree_sha": gate.manifest()["root_tree_sha"],
                "archive_sha256": exported["sha256"], "folder_id": c.DRIVE_FOLDER,
                "account": {"email": c.DRIVE_ACCOUNT, "link_id": c.DRIVE_LINK_ID, "profile_id": c.DRIVE_PROFILE_ID},
                "uploaded_file_id": "fixture-drive-file", "readback_metadata": {
                    "id": "fixture-drive-file", "parent_ids": [c.DRIVE_FOLDER], "size": str(exported["size"]),
                    "mime_type": "application/zip", "url": "https://drive.google.com/file/d/fixture-drive-file/view"},
                "download": {"file_id": "fixture-drive-file", "path": str(downloaded)},
                "baseline_coverage": {"commit_sha": parent, "tree_sha": base_tree,
                    "folder_id": c.DRIVE_FOLDER, "account_email": c.DRIVE_ACCOUNT,
                    "index_file_id": "fixture-baseline-index", "readback_verified": True, "tree_verified": True,
                    "archive_sha256": "a" * 64, "recombined_sha256": "a" * 64}}

    def step(self, gate):
        action = gate.next()
        if action["kind"] == "noop":
            return action
        if action["kind"] == "drive_checkpoint_required":
            gate.record_drive(self.prepare_drive(gate))
            return action
        if not action.get("reconciles"):
            gate.dispatch(action["id"])
        receipt = self.remote.receipt(action)
        gate.apply(action["id"], receipt)
        return action

    def finish(self, gate):
        for _ in range(200):
            if gate.status()["development_allowed"]:
                return
            self.step(gate)
            gate = c.Gate(self.state)  # Every step must survive a fresh process.
        self.fail("Fixture did not finish")

    def reach(self, gate, kind):
        for _ in range(200):
            action = gate.next()
            if action["kind"] == kind:
                return action
            self.step(gate)
        self.fail("Did not reach " + kind)

    def test_first_snapshot_exact_remote_tree_and_gate(self):
        gate = self.start()
        self.assertFalse(gate.status()["development_allowed"])
        self.finish(gate)
        gate = c.Gate(self.state)
        self.assertTrue(gate.status()["development_allowed"])
        self.assertEqual(gate.state["durable"]["commit_sha"], self.remote.ref)
        self.assertEqual(sorted(self.remote.recursive(gate.manifest()["root_tree_sha"]), key=lambda x: x["path"]), gate.manifest()["expected_recursive_tree"])
        self.assertEqual(self.remote.calls[-2:], ["verify_recursive_tree", "verify_final_ref"])

    def test_unchanged_is_noop_then_changed_source_reuses_blobs(self):
        self.write("assets/pixel.png", bytes(range(256)))
        self.finish(self.start())
        gate = c.Gate(self.state)
        previous = gate.state["durable"]["commit_sha"]
        snapshot = gate.state["snapshot"]
        calls = len(self.remote.calls)
        self.assertEqual(gate.snapshot(self.source, None, "No edits")["outcome"], "unchanged")
        self.assertEqual(gate.next()["kind"], "noop")
        self.assertEqual(len(self.remote.calls), calls)
        self.assertEqual(snapshot, gate.state["snapshot"])
        self.write("scripts/main.gd", b"extends Node\nvar score = 1\n")
        gate.snapshot(self.source, None, "Changed source")
        self.assertEqual(gate.state["parent"], previous)
        before = self.remote.calls.count("create_blob")
        self.finish(gate)
        self.assertEqual(self.remote.calls.count("create_blob") - before, 2)  # Source + regenerated durable manifest.

    def test_binary_asset_blender_reaper_and_licenses(self):
        self.write("source_art/ship.blend", b"BLENDER\x00\xff\x01")
        self.write("source_art/music.rpp", b"<REAPER_PROJECT\n>\n")
        self.write("licenses/LICENSE", b"Fixture license")
        self.finish(self.start())
        gate = c.Gate(self.state)
        files = {f["path"]: f for f in gate.manifest()["files"]}
        self.assertEqual(self.remote.blobs[files["source_art/ship.blend"]["sha"]], b"BLENDER\x00\xff\x01")
        self.assertIn("source_art/music.rpp", files)
        self.assertIn("licenses/LICENSE", files)

    def test_exclusions_are_explicit_and_not_snapshot_identity(self):
        for path in (".env", "credentials.json", ".godot/cache.bin", "builds/game.pck", "logs/huge.log", "tests/demo.mp4", "source_art/ship.blend1", "source_art/track.reapeaks", "backups/old.gd"):
            self.write(path, b"excluded data")
        gate = self.start()
        self.assertEqual([f["path"] for f in gate.manifest()["files"]], [c.MANIFEST_PATH, "scripts/main.gd"])
        exclusions = c.read_json(self.state / "exclusions.json")
        self.assertEqual(len(exclusions), 9)
        identity = gate.state["snapshot"]
        self.write(".godot/cache.bin", b"new cache data")
        self.assertEqual(c.capture(self.source, self.state)[0], identity)

    def test_secrets_and_symlink_escape_block(self):
        self.write("scripts/config.gd", b'var key = "' + b"ghp_" + b"A" * 40 + b'"')
        with self.assertRaisesRegex(c.Blocked, "Possible secret"):
            self.start()
        (self.source / "scripts/config.gd").unlink()
        outside = self.base / "outside.gd"
        outside.write_bytes(b"must not read")
        (self.source / "scripts/escape.gd").symlink_to(outside)
        with self.assertRaisesRegex(c.Blocked, "Symlink"):
            self.start()
        self.assertFalse((self.state / "objects" / c.digest(outside.read_bytes())).exists())

    def test_unclassified_file_blocks_instead_of_silent_omission(self):
        self.write("source_art/project.weird", b"irreplaceable source")
        with self.assertRaisesRegex(c.Blocked, "Unclassified"):
            self.start()

    def test_interrupted_blob_resume_reads_before_retry(self):
        gate = self.start()
        action = self.reach(gate, "create_blob")
        gate.dispatch(action["id"])
        self.remote.receipt(action)  # Transport receipt is lost after successful write.
        resumed = c.Gate(self.state)
        reconciliation = resumed.next()
        self.assertEqual(reconciliation["kind"], "reconcile_object")
        self.assertFalse(reconciliation["mutating"])
        resumed.apply(reconciliation["id"], self.remote.receipt(reconciliation))
        self.finish(resumed)
        self.assertEqual(self.remote.calls.count("create_blob"), 2)  # Source + durable manifest.

    def test_negative_reconciliation_allows_identical_retry(self):
        gate = self.start()
        action = self.reach(gate, "create_blob")
        gate.dispatch(action["id"])  # Crash before actual call.
        reconciliation = c.Gate(self.state).next()
        gate.apply(reconciliation["id"], self.remote.receipt(reconciliation))
        self.assertEqual(gate.next()["id"], action["id"])
        self.assertFalse(gate.next()["dispatched"])
        self.finish(gate)

    def test_interrupted_update_reconciles_without_second_write(self):
        gate = self.start()
        action = self.reach(gate, "update_ref")
        gate.dispatch(action["id"])
        self.remote.receipt(action)
        resumed = c.Gate(self.state)
        reconciliation = resumed.next()
        self.assertEqual(reconciliation["kind"], "reconcile_ref")
        resumed.apply(reconciliation["id"], self.remote.receipt(reconciliation))
        self.finish(resumed)
        self.assertEqual(self.remote.calls.count("update_ref"), 1)

    def test_uncertain_commit_requires_receipt_sha_then_readback(self):
        gate = self.start()
        action = self.reach(gate, "create_commit")
        gate.dispatch(action["id"])
        receipt = self.remote.receipt(action)
        resumed = c.Gate(self.state)
        self.assertEqual(resumed.next()["kind"], "blocked_uncertain_commit")
        resumed.recover_commit(receipt["result"]["sha"])
        self.assertEqual(resumed.next()["kind"], "verify_commit")
        self.finish(resumed)
        self.assertEqual(self.remote.calls.count("create_commit"), 1)

    def test_wrong_blob_sha_rejected(self):
        gate = self.start()
        action = self.reach(gate, "create_blob")
        gate.dispatch(action["id"])
        with self.assertRaisesRegex(c.Blocked, "SHA mismatch"):
            gate.apply(action["id"], {"status": "ok", "result": {"sha": "b" * 40}})
        self.assertFalse(gate.status()["development_allowed"])

    def test_branch_race_and_exact_recursive_mismatch(self):
        gate = self.start()
        action = self.reach(gate, "verify_lease")
        self.remote.ref = "b" * 40
        gate.dispatch(action["id"])
        with self.assertRaisesRegex(c.Blocked, "Branch race"):
            gate.apply(action["id"], self.remote.receipt(action))
        self.assertNotIn("update_ref", self.remote.calls)

    def test_final_tree_extra_missing_truncated_or_wrong_mode_fail(self):
        gate = self.start()
        action = self.reach(gate, "verify_recursive_tree")
        gate.dispatch(action["id"])
        good = self.remote.receipt(action)
        bad = copy.deepcopy(good)
        bad["result"]["tree"] = []
        with self.assertRaisesRegex(c.Blocked, "exact snapshot"):
            gate.apply(action["id"], bad)
        bad = copy.deepcopy(good)
        bad["result"]["truncated"] = True
        with self.assertRaisesRegex(c.Blocked, "complete"):
            gate.apply(action["id"], bad)
        self.assertFalse(gate.status()["development_allowed"])

    def test_private_repo_and_main_protection(self):
        gate = self.start()
        action = gate.next()
        gate.dispatch(action["id"])
        with self.assertRaisesRegex(c.Blocked, "private"):
            gate.apply(action["id"], {"status": "ok", "result": {"full_name": c.REPOSITORY, "private": False}})
        self.assertEqual(c.BRANCH, "wip/recovery-20261011")
        self.assertNotEqual(c.BRANCH, "main")

    def test_deterministic_hashes_modes_and_bounded_trees(self):
        self.assertEqual(c.git_hash("blob", b"hello\n"), "ce013625030ba8dba906f756967f9e9ca394464a")
        self.assertEqual(c.git_hash("tree", b""), "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
        for index in range(260):
            self.write(f"assets/{index:03d}.txt", b"shared bytes")
        os.chmod(self.source / "scripts/main.gd", 0o755)
        gate = self.start()
        identity = gate.state["snapshot"]
        self.assertEqual(c.capture(self.source, self.base / "another-state")[0], identity)
        self.assertTrue(all(len(op["tree_elements"]) <= c.TREE_BATCH for op in gate.manifest()["tree_operations"]))
        self.finish(gate)
        self.assertEqual(self.remote.calls.count("create_blob"), 3)
        self.assertEqual(c.Gate(self.state).manifest()["files"][-1]["mode"], "100755")

    def test_snapshot_mutation_new_development_and_payload_bounds(self):
        gate = self.start()
        self.write("scripts/new.gd", b"extends Node")
        with self.assertRaisesRegex(c.Blocked, "unfinished"):
            gate.snapshot(self.source, None, "Too early")
        with patch.object(c, "MAX_BLOB_BYTES", 1):
            with self.assertRaisesRegex(c.Blocked, "connector bound"):
                c.Gate(self.base / "small-state").snapshot(self.source, self.metadata, "Too large")
        with self.assertRaisesRegex(c.Blocked, "outside"):
            c.capture(self.source, self.source / "snapshots")

    def test_manifest_tampering_blocks(self):
        gate = self.start()
        path = self.state / "snapshots" / gate.state["snapshot"] / "manifest.json"
        os.chmod(path, 0o644)
        path.write_text("{}")
        with self.assertRaisesRegex(c.Blocked, "manifest"):
            gate.next()

    def test_dispatch_is_required_and_uncertain_read_is_repeatable(self):
        gate = self.start()
        action = gate.next()
        with self.assertRaisesRegex(c.Blocked, "dispatch"):
            gate.apply(action["id"], self.remote.receipt(action))
        gate.dispatch(action["id"])
        gate.apply(action["id"], {"status": "error", "result": {}})
        self.assertFalse(gate.next()["dispatched"])
        self.finish(gate)


    def test_durable_manifest_and_recovery_docs_preserved(self):
        self.write("docs/recovery/inventory.json", b'{"missing": true}')
        self.write("source_art/recovery_inputs/patch.diff", b"diff fixture")
        self.write("source_art/recovery_inputs/input.patch", b"patch fixture")
        gate = self.start()
        files = {f["path"]: f for f in gate.manifest()["files"]}
        self.assertIn("docs/recovery/inventory.json", files)
        self.assertIn("source_art/recovery_inputs/patch.diff", files)
        content = (self.state / "objects" / files[c.MANIFEST_PATH]["sha256"]).read_bytes()
        manifest = json.loads(content)
        self.assertNotIn(c.MANIFEST_PATH, [f["path"] for f in manifest["files"]])
        self.assertEqual(manifest["payload_tree_sha"], c.build_trees(manifest["files"])[0])
        identity = gate.state["snapshot"]
        self.write(c.MANIFEST_PATH, content)  # Exactly how a fresh executor restores the branch.
        self.assertEqual(c.capture(self.source, self.base / "fresh-state")[0], identity)
        self.finish(gate)

    def test_real_mcp_fetch_wrappers_and_normalized_repo(self):
        gate = self.start()
        action = gate.next()
        gate.dispatch(action["id"])
        raw = {"repository_full_name": c.REPOSITORY, "visibility": "private"}
        wrapper = {"structuredContent": {"content": json.dumps(raw)},
                   "content": [{"type": "text", "text": json.dumps(raw)}]}
        gate.apply(action["id"], {"status": "ok", "result": wrapper})
        self.assertTrue(gate.state["repo_verified"])
        with self.assertRaisesRegex(c.Blocked, "ambiguous"):
            c.unwrap_result({"structuredContent": {"sha": "a" * 40},
                             "content": [{"type": "text", "text": json.dumps({"sha": "b" * 40})}]})



    def test_fresh_executor_unchanged_backup_reads_but_never_writes(self):
        self.finish(self.start())
        original = c.Gate(self.state)
        manifest_file = next(f for f in original.manifest()["files"] if f["path"] == c.MANIFEST_PATH)
        self.write(c.MANIFEST_PATH, (self.state / "objects" / manifest_file["sha256"]).read_bytes())
        baseline = {"repo": {"full_name": c.REPOSITORY, "private": True},
                    "commit": self.remote.commits[self.remote.ref],
                    "tree": {"sha": original.manifest()["root_tree_sha"],
                             "tree": original.manifest()["expected_recursive_tree"], "truncated": False}}
        self.metadata.write_text(json.dumps(baseline))
        self.state = self.base / "fresh-executor-state"
        gate = self.start()
        calls = len(self.remote.calls)
        self.finish(gate)
        new_calls = self.remote.calls[calls:]
        self.assertFalse(any(name.startswith("create_") or name == "update_ref" for name in new_calls))
        self.assertEqual(c.Gate(self.state).state["snapshot"], original.state["snapshot"])

    def test_receipt_reconciliation_survives_crash_before_state_save(self):
        gate = self.start()
        action = self.reach(gate, "create_blob")
        gate.dispatch(action["id"])
        receipt = self.remote.receipt(action)
        with patch.object(gate, "save", side_effect=OSError("simulated process loss")):
            with self.assertRaises(OSError):
                gate.apply(action["id"], receipt)
        resumed = c.Gate(self.state)
        reconcile = resumed.next()
        resumed.apply(reconcile["id"], self.remote.receipt(reconcile))
        self.finish(resumed)



    def test_source_edits_during_upload_never_open_gate(self):
        gate = self.start()
        action = self.reach(gate, "verify_final_ref")
        self.write("scripts/main.gd", b"unbacked later edits")
        gate.dispatch(action["id"])
        with self.assertRaisesRegex(c.Blocked, "Source changed while backup"):
            gate.apply(action["id"], self.remote.receipt(action))
        self.assertFalse(gate.status()["development_allowed"])

    def test_final_branch_race_never_opens_gate(self):
        gate = self.start()
        action = self.reach(gate, "verify_final_ref")
        self.remote.ref = "b" * 40
        gate.dispatch(action["id"])
        with self.assertRaisesRegex(c.Blocked, "Branch race during final"):
            gate.apply(action["id"], self.remote.receipt(action))
        self.assertFalse(gate.status()["development_allowed"])



    def test_drive_first_blocks_every_git_mutation_until_verified(self):
        gate = self.start()
        self.step(gate)  # Read repository.
        self.step(gate)  # Read absent branch.
        self.assertEqual(gate.next()["kind"], "drive_checkpoint_required")
        self.assertFalse(any(name.startswith("create_") or name == "update_ref" for name in self.remote.calls))
        self.assertFalse(gate.status()["development_allowed"])
        gate.record_drive(self.prepare_drive(gate))
        self.assertTrue(gate.drive_verified())
        self.assertFalse(gate.status()["development_allowed"])
        self.assertEqual(gate.next()["kind"], "create_branch")
        self.finish(gate)
        self.assertIsNotNone(c.Gate(self.state).status()["github_durable"])
        self.assertIsNotNone(c.Gate(self.state).status()["drive_durable"])

    def test_drive_wrong_account_folder_or_snapshot_block(self):
        gate = self.start()
        good = self.prepare_drive(gate)
        for key, bad in (("folder_id", "wrong-folder"), ("snapshot", "wrong-snapshot"), ("root_tree_sha", "b" * 40)):
            receipt = copy.deepcopy(good)
            receipt[key] = bad
            with self.assertRaises(c.Blocked):
                gate.record_drive(receipt)
        receipt = copy.deepcopy(good)
        receipt["account"]["email"] = "wrong@example.com"
        with self.assertRaisesRegex(c.Blocked, "authorized account"):
            gate.record_drive(receipt)
        receipt = copy.deepcopy(good)
        receipt["readback_metadata"]["parent_ids"] = ["old-wrong-folder"]
        with self.assertRaisesRegex(c.Blocked, "parent"):
            gate.record_drive(receipt)
        self.assertFalse(gate.drive_verified())

    def test_drive_actual_download_and_optional_server_md5_must_match(self):
        gate = self.start()
        receipt = self.prepare_drive(gate)
        bad = copy.deepcopy(receipt)
        bad["readback_metadata"]["md5Checksum"] = "0" * 32
        with self.assertRaisesRegex(c.Blocked, "MD5"):
            gate.record_drive(bad)
        bad = copy.deepcopy(receipt)
        bad["download"]["path"] = gate.state["drive_export"]["path"]
        with self.assertRaisesRegex(c.Blocked, "distinct"):
            gate.record_drive(bad)
        Path(receipt["download"]["path"]).write_bytes(b"wrong remote bytes")
        with self.assertRaisesRegex(c.Blocked, "Downloaded Drive bytes"):
            gate.record_drive(receipt)
        self.assertFalse(gate.drive_verified())

    def test_deterministic_delta_export_has_deletions_modes_and_exact_tree(self):
        self.finish(self.start())
        old = c.Gate(self.state)
        old_parent = old.state["durable"]["commit_sha"]
        (self.source / "scripts/main.gd").unlink()
        self.write("scripts/replacement.gd", b"extends Node\n")
        os.chmod(self.source / "scripts/replacement.gd", 0o755)
        old.snapshot(self.source, None, "Replacement")
        receipt = self.prepare_drive(old)
        exported = old.state["drive_export"]
        baseline = self.base / (old.state["snapshot"] + "-baseline.json")
        other = old.export_drive(baseline, self.base / "another-delta.zip")["export"]
        self.assertEqual(exported["sha256"], other["sha256"])
        with zipfile.ZipFile(other["path"]) as archive:
            index = json.loads(archive.read("checkpoint.json"))
            self.assertEqual(index["baseline_commit_sha"], old_parent)
            self.assertEqual(index["deleted_files"], ["scripts/main.gd"])
            self.assertEqual(index["expected_recursive_tree"], old.manifest()["expected_recursive_tree"])
            replacement = next(f for f in index["changed_files"] if f["path"] == "scripts/replacement.gd")
            self.assertEqual(replacement["mode"], "100755")
            self.assertEqual(archive.getinfo("files/scripts/replacement.gd").date_time, (1980, 1, 1, 0, 0, 0))

    def test_drive_requires_recoverable_baseline_and_same_tree(self):
        gate = self.start()
        receipt = self.prepare_drive(gate)
        receipt["baseline_coverage"]["tree_verified"] = False
        with self.assertRaisesRegex(c.Blocked, "recoverable baseline"):
            gate.record_drive(receipt)
        self.assertFalse(gate.status()["development_allowed"])

    def test_v1_git_only_success_cannot_open_v2_gate(self):
        self.finish(self.start())
        state = c.read_json(self.state / "checkpoint.json")
        state.pop("gate_policy_version")
        state.pop("github_durable")
        state.pop("drive_durable")
        state.pop("drive_export")
        c.atomic_json(self.state / "checkpoint.json", state)
        migrated = c.Gate(self.state)
        self.assertIsNotNone(migrated.state["github_durable"])
        self.assertFalse(migrated.status()["development_allowed"])
        self.assertEqual(migrated.next()["kind"], "drive_checkpoint_required")


if __name__ == "__main__":
    unittest.main()
