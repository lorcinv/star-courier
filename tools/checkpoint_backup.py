#!/usr/bin/env python3
"""Credential-free Star Courier checkpoint planner. Python standard library only.

No GitHub call is made here. An authorized operator dispatches emitted actions
through the supported GitHub connector, then supplies the actual JSON receipts.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tempfile
import zipfile
from urllib.parse import quote

REPOSITORY = "lorcinv/star-courier"
BRANCH = "wip/recovery-20261011"
VERSION = 1
MANIFEST_PATH = "docs/checkpoints/backup-manifest.json"
GATE_POLICY_VERSION = 2
DRIVE_ACCOUNT = "lk520222333@gmail.com"
DRIVE_LINK_ID = "link_6acb98a04ab8819188482234fc6ef229"
DRIVE_PROFILE_ID = "118419590976145726901"
DRIVE_FOLDER = "1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ"
MAX_DRIVE_EXPORT = 100 * 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 2 * 1024 * 1024 * 1024
MAX_BLOB_BYTES = 16 * 1024 * 1024
MAX_PAYLOAD_BYTES = 24 * 1024 * 1024
TREE_BATCH = 128
MAX_TREE_PAYLOAD = 128 * 1024
MAX_FILES = 20_000
EXCLUDED_DIRS = {
    ".git", ".godot", ".import", ".aws", ".ssh", ".gnupg", ".secrets",
    ".venv", "venv", "node_modules", "__pycache__", ".pytest_cache",
    ".mypy_cache", ".ruff_cache", "build", "builds", "dist", "exports",
    "cache", "caches", "logs", "videos", "recordings", "backups", "backup",
    ".checkpoints", ".backup-state",
}
ALLOWED_SUFFIXES = {
    ".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".godot", ".cfg",
    ".uid", ".import", ".json", ".md", ".txt", ".py", ".sh", ".bat",
    ".ps1", ".conf", ".svg", ".png", ".jpg", ".jpeg", ".webp", ".gif",
    ".wav", ".ogg", ".flac", ".mp3", ".blend", ".rpp", ".glb", ".gltf",
    ".bin", ".otf", ".ttf", ".gpl", ".csv", ".toml", ".yaml", ".yml",
    ".ini", ".xml", ".html", ".css", ".js", ".ts", ".rst", ".license",
    ".diff", ".patch", ".tsv",
}
ALLOWED_NAMES = {".gitignore", ".gitattributes", ".gdignore", ".gitkeep",
                 "license", "licence", "copying", "notice", "authors", "makefile"}
EXCLUDED_SUFFIXES = {".log", ".out", ".mp4", ".mov", ".webm", ".avi", ".mkv",
                     ".zip", ".tar", ".gz", ".7z", ".rar", ".exe", ".pck",
                     ".app", ".dmg", ".apk", ".pyc", ".reapeaks", ".bak",
                     ".tmp", ".swp", ".blend1", ".blend2", ".rpp-bak"}
SECRET_NAMES = re.compile(r"(^\.env($|\.)|(^|[._-])(credentials?|secrets?|tokens?)([._-]|$)|^id_(rsa|ed25519)$)", re.I)
SECRET_CONTENT = [
    re.compile(rb"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
    re.compile(rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{30,}\b"),
]
SHA = re.compile(r"^[0-9a-f]{40}$")


class Blocked(Exception):
    """A closed backup gate; no new development is permitted."""


def require(ok, message):
    if not ok:
        raise Blocked(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_hash(kind, data):
    return hashlib.sha1(kind.encode() + b" " + str(len(data)).encode() + b"\0" + data).hexdigest()


def checked_sha(value):
    require(isinstance(value, str) and SHA.fullmatch(value), "Invalid Git SHA in receipt/metadata")
    return value


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def atomic_json(path, value, immutable=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = canonical(value) + b"\n"
    if immutable and path.exists():
        require(path.read_bytes() == data, f"Immutable file was changed: {path.name}")
        return
    fd, temp = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if immutable:
            os.chmod(temp, 0o444)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value and "\x00" not in value,
            "Unsafe repository path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(x not in ("", ".", "..") for x in value.split("/")),
            "Unsafe repository path")
    require(not any(ord(c) < 32 for c in value), "Control character in repository path")
    value.encode("utf-8")
    return value


def git_tree(entries):
    ordered = sorted(entries, key=lambda e: (e["path"] + ("/" if e["type"] == "tree" else "")).encode("utf-8"))
    data = b"".join((e["mode"].lstrip("0") + " " + e["path"]).encode("utf-8")
                    + b"\0" + bytes.fromhex(e["sha"]) for e in ordered)
    return git_hash("tree", data)


def build_trees(files):
    """Return root SHA, complete recursive tree, bottom-up bounded tree writes."""
    dirs = {"": []}
    for item in files:
        path = safe_path(item["path"])
        parent = str(PurePosixPath(path).parent)
        parent = "" if parent == "." else parent
        dirs.setdefault(parent, []).append({"path": PurePosixPath(path).name,
                                            "mode": item["mode"], "type": "blob", "sha": item["sha"]})
        while parent:
            parent = str(PurePosixPath(parent).parent)
            parent = "" if parent == "." else parent
            dirs.setdefault(parent, [])
    trees, operations, recursive = {}, [], []
    for directory in sorted(dirs, key=lambda p: (-p.count("/") - bool(p), p)):
        entries = sorted(dirs[directory], key=lambda e: e["path"])
        partial = []
        previous = None
        # Empty root needs one tree object unless already known remotely.
        for offset in range(0, max(len(entries), 1), TREE_BATCH):
            chunk = entries[offset:offset + TREE_BATCH]
            partial.extend(chunk)
            sha = git_tree(partial)
            operations.append({"sha": sha, "base_tree_sha": previous, "tree_elements": chunk})
            previous = sha
        for operation in operations[-max((len(entries) + TREE_BATCH - 1) // TREE_BATCH, 1):]:
            operation["final_tree_sha"] = previous
        trees[directory] = previous
        for entry in entries:
            recursive.append({**entry, "path": (directory + "/" if directory else "") + entry["path"]})
        if directory:
            parent = str(PurePosixPath(directory).parent)
            parent = "" if parent == "." else parent
            dirs[parent].append({"path": PurePosixPath(directory).name, "mode": "040000",
                                 "type": "tree", "sha": previous})
    return trees[""], sorted(recursive, key=lambda e: e["path"]), operations


def normalized_tree(result):
    require(isinstance(result, dict) and result.get("truncated") is False,
            "Recursive tree must explicitly be complete (truncated=false)")
    entries = []
    seen = set()
    for raw in result.get("tree", []):
        path = safe_path(raw.get("path"))
        require(path not in seen, "Duplicate path in recursive tree")
        seen.add(path)
        require((raw.get("mode"), raw.get("type")) in
                (("100644", "blob"), ("100755", "blob"), ("040000", "tree")),
                "Symlinks, submodules, or unsupported modes in remote tree")
        entries.append({"path": path, "mode": raw["mode"], "type": raw["type"], "sha": checked_sha(raw.get("sha"))})
    return sorted(entries, key=lambda e: e["path"])


def validate_metadata(metadata):
    require(metadata["repo"].get("full_name") == REPOSITORY and metadata["repo"].get("private") is True,
            "Baseline must identify the authorized private repository")
    commit = checked_sha(metadata["commit"].get("sha"))
    tree = metadata["tree"]
    entries = normalized_tree(tree)
    files = [x for x in entries if x["type"] == "blob"]
    root, calculated, _ = build_trees(files)
    require(calculated == entries and root == checked_sha(tree.get("sha")), "Baseline recursive tree hash mismatch")
    require(metadata["commit"]["tree"]["sha"] == root, "Baseline commit/tree mismatch")
    return commit, root, entries


def excluded(path, is_dir):
    name = PurePosixPath(path).name.lower()
    if path == MANIFEST_PATH:
        return "reserved generated manifest; replaced with verified payload inventory"
    if is_dir and name in EXCLUDED_DIRS:
        return "cache/build/bulk-output/backup directory"
    if SECRET_NAMES.search(name) or name in {".netrc", ".npmrc", ".pypirc"}:
        return "credential/secret filename"
    if not is_dir and (PurePosixPath(name).suffix in EXCLUDED_SUFFIXES or name.endswith("~")):
        return "cache/build/video/archive/duplicate backup"
    return None


def inventory(source):
    found, omitted = {}, []
    def walk(directory, prefix=""):
        with os.scandir(directory) as iterator:
            for entry in sorted(iterator, key=lambda e: e.name):
                path = safe_path(prefix + entry.name)
                info = entry.stat(follow_symlinks=False)
                directory_entry = stat.S_ISDIR(info.st_mode)
                reason = excluded(path, directory_entry)
                if reason:
                    omitted.append({"path": path, "reason": reason})
                    continue
                require(not stat.S_ISLNK(info.st_mode), f"Symlink is not allowed: {path}")
                if directory_entry:
                    walk(Path(entry.path), path + "/")
                else:
                    require(stat.S_ISREG(info.st_mode), f"Non-regular source file: {path}")
                    name = entry.name.lower()
                    require(PurePosixPath(name).suffix in ALLOWED_SUFFIXES or name in ALLOWED_NAMES,
                            f"Unclassified file requires policy review: {path}")
                    require(info.st_size <= MAX_FILE_BYTES, f"File exceeds local snapshot bound: {path}")
                    found[path] = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns,
                                   info.st_ctime_ns, info.st_mode)
    walk(source)
    require(len(found) <= MAX_FILES, "File count exceeds snapshot bound")
    require(sum(x[2] for x in found.values()) <= MAX_TOTAL_BYTES, "Snapshot byte bound exceeded")
    return found, omitted


def unwrap_result(raw):
    """Accept raw GitHub JSON or bounded MCP structuredContent/content wrappers."""
    candidates = {}
    def visit(value, depth=0):
        require(depth <= 8, "Connector wrapper nesting exceeds bound")
        if isinstance(value, str):
            try:
                visit(json.loads(value), depth + 1)
            except json.JSONDecodeError:
                pass
        elif isinstance(value, dict):
            require(not value.get("isError"), "Connector returned isError; do not label the receipt ok")
            if any(key in value for key in ("sha", "ref", "full_name", "repository_full_name", "id")):
                candidates[digest(canonical(value))] = value
                return
            if "structuredContent" in value:
                visit(value["structuredContent"], depth + 1)
            if "content" in value:
                visit(value["content"], depth + 1)
            if value.get("type") == "text" and "text" in value:
                visit(value["text"], depth + 1)
            if value.get("isError"):
                raise Blocked("Connector returned isError; do not label the receipt ok")
        elif isinstance(value, list):
            require(len(value) <= 20, "Connector wrapper list exceeds bound")
            for item in value:
                visit(item, depth + 1)
    visit(raw)
    require(len(candidates) == 1, "Missing or ambiguous GitHub result in connector receipt")
    return next(iter(candidates.values()))


def open_source_file(source, path):
    """Never follow a symlink in any source path component (POSIX executor)."""
    require(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_DIRECTORY"),
            "This safe snapshot reader requires POSIX O_NOFOLLOW/O_DIRECTORY")
    directory = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        parts = path.split("/")
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        return os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
    finally:
        os.close(directory)


def store_object(state_dir, data):
    sha256 = digest(data)
    object_path = Path(state_dir) / "objects" / sha256
    object_path.parent.mkdir(parents=True, exist_ok=True)
    if object_path.exists():
        require(digest(object_path.read_bytes()) == sha256, "Stored snapshot object is corrupt")
    else:
        fd, temp = tempfile.mkstemp(prefix=".object-", dir=object_path.parent)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temp, 0o444)
            os.replace(temp, object_path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    return sha256


def file_hashes(path):
    sha256, md5, size = hashlib.sha256(), hashlib.md5(), 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            sha256.update(chunk)
            md5.update(chunk)
            size += len(chunk)
    return {"sha256": sha256.hexdigest(), "md5": md5.hexdigest(), "size": size}


def capture(source, state_dir):
    source = Path(source).resolve(strict=True)
    state_dir = Path(state_dir).resolve()
    require(source.is_dir(), "Source must be a directory")
    require(source != state_dir and source not in state_dir.parents,
            "State must be outside the source tree (prevents recursive backups)")
    before, omitted = inventory(source)
    files = []
    for path, expected in sorted(before.items()):
        fd = open_source_file(source, path)
        with os.fdopen(fd, "rb") as handle:
            info = os.fstat(handle.fileno())
            require((info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_mode) == expected,
                    f"Source changed during capture: {path}")
            data = handle.read(MAX_FILE_BYTES + 1)
            require(len(data) == expected[2], f"Source changed during capture: {path}")
        require(not any(pattern.search(data) for pattern in SECRET_CONTENT),
                f"Possible secret in source; inspect locally before backup: {path}")
        sha256 = digest(data)
        store_object(state_dir, data)
        files.append({"path": path, "mode": "100755" if expected[5] & 0o111 else "100644",
                      "sha": git_hash("blob", data), "sha256": sha256, "size": len(data)})
    after, _ = inventory(source)
    require(before == after, "Source changed during capture; freeze writers and retry")
    payload_root, payload_entries, _ = build_trees(files)
    durable_manifest = {"version": VERSION, "repository": REPOSITORY, "branch": BRANCH,
                        "generated_manifest_path": MANIFEST_PATH,
                        "scope": "All permitted payload files; this generated manifest excludes itself",
                        "files": list(files), "payload_tree_sha": payload_root,
                        "expected_payload_recursive_tree": payload_entries}
    manifest_data = canonical(durable_manifest) + b"\n"
    manifest_sha256 = store_object(state_dir, manifest_data)
    files.append({"path": MANIFEST_PATH, "mode": "100644", "sha": git_hash("blob", manifest_data),
                  "sha256": manifest_sha256, "size": len(manifest_data)})
    files.sort(key=lambda f: f["path"])
    root, entries, operations = build_trees(files)
    manifest = {"version": VERSION, "repository": REPOSITORY, "branch": BRANCH,
                "files": files, "root_tree_sha": root, "expected_recursive_tree": entries,
                "tree_operations": operations}
    identity = digest(canonical(manifest))
    atomic_json(state_dir / "snapshots" / identity / "manifest.json", manifest, immutable=True)
    atomic_json(state_dir / "exclusions.json", omitted)
    return identity, manifest


class Gate:
    def __init__(self, state_dir):
        self.directory = Path(state_dir)
        self.path = self.directory / "checkpoint.json"
        self.state = read_json(self.path) if self.path.exists() else None
        if self.state:
            require(self.state["version"] == VERSION and self.state["repository"] == REPOSITORY
                    and self.state["branch"] == BRANCH, "Unexpected state version or destination")
            if self.state.get("gate_policy_version") != GATE_POLICY_VERSION:
                # Preserve v1 snapshots/receipts, but never inherit their Git-only open gate.
                self.state["github_durable"] = self.state.get("durable")
                self.state["durable"] = None
                self.state["drive_durable"] = None
                self.state["drive_export"] = None
                self.state["gate_policy_version"] = GATE_POLICY_VERSION

    def save(self):
        atomic_json(self.path, self.state)

    def block(self, message):
        atomic_json(self.directory / "gate.json", {"development_allowed": False, "reason": message})
        if self.state:
            self.state["blocked"] = message
            self.save()

    def manifest(self):
        identity = self.state["snapshot"]
        value = read_json(self.directory / "snapshots" / identity / "manifest.json")
        require(digest(canonical(value)) == identity, "Immutable manifest was changed")
        return value

    def snapshot(self, source, baseline, reason):
        require(reason and len(reason) <= 500, "Checkpoint reason must be 1–500 characters")
        if self.state and self.state.get("blocked"):
            raise Blocked(self.state["blocked"])
        identity, manifest = capture(source, self.directory)
        if self.state and self.state["snapshot"] == identity:
            return self.status("unchanged" if self.state.get("durable") else "resume")
        require(not self.state or self.state.get("durable"),
                "An unfinished checkpoint exists. Resume it before any new development.")
        if self.state:
            previous = self.state
            parent = previous["durable"]["commit_sha"]
            parent_tree = previous["durable"]["tree_sha"]
            known_blobs = set(previous["known_blobs"])
            known_trees = set(previous["known_trees"])
        else:
            require(baseline, "First checkpoint requires verified baseline metadata")
            parent, base_tree, entries = validate_metadata(read_json(baseline))
            parent_tree = base_tree
            known_blobs = {e["sha"] for e in entries if e["type"] == "blob"}
            known_trees = {e["sha"] for e in entries if e["type"] == "tree"} | {base_tree}
        reuse_parent = manifest["root_tree_sha"] == parent_tree
        self.state = {"version": VERSION, "repository": REPOSITORY, "branch": BRANCH,
                      "snapshot": identity, "source": str(Path(source).resolve()), "reason": reason,
                      "parent": parent, "known_blobs": sorted(known_blobs), "known_trees": sorted(known_trees),
                      "repo_verified": False, "branch_verified": False, "branch_absent": False,
                      "candidate_commit": parent if reuse_parent else None, "reuse_parent_commit": reuse_parent,
                      "commit_verified": False, "pre_update_verified": reuse_parent,
                      "updated": reuse_parent, "tree_verified": False, "durable": None,
                      "pending": None, "blocked": None, "receipt_count": 0,
                      "gate_policy_version": GATE_POLICY_VERSION, "github_durable": None,
                      "drive_durable": None, "drive_export": None}
        self.save()
        atomic_json(self.directory / "gate.json", {"development_allowed": False, "reason": "Checkpoint awaiting remote verification"})
        # Reject oversized *new* objects before emitting any remote write.
        for file in manifest["files"]:
            require(file["sha"] in known_blobs or file["size"] <= MAX_BLOB_BYTES,
                    f"New blob exceeds {MAX_BLOB_BYTES} byte connector bound: {file['path']}")
        return self.status("snapshot_ready")

    def status(self, outcome=None):
        require(self.state, "No checkpoint exists")
        failure = read_json(self.directory / "gate.json") if (self.directory / "gate.json").exists() else {}
        allowed = bool(self.state.get("durable")) and not self.state.get("blocked") and failure.get("development_allowed") is True
        return {"outcome": outcome or ("durable" if allowed else "blocked" if self.state.get("blocked") else "pending"),
                "snapshot": self.state["snapshot"], "development_allowed": allowed,
                "durable": self.state.get("durable"), "github_durable": self.state.get("github_durable"),
                "drive_durable": self.state.get("drive_durable"), "blocked": self.state.get("blocked")}

    def action(self, kind, tool, arguments, expected=None, mutating=False):
        value = {"kind": kind, "tool": tool, "arguments": arguments,
                 "expected": expected or {}, "mutating": mutating}
        require(len(canonical(arguments)) <= MAX_PAYLOAD_BYTES, "Connector payload exceeds bound")
        if tool == "create_tree":
            require(len(canonical(arguments)) <= MAX_TREE_PAYLOAD, "Tree payload exceeds bound")
        value["id"] = digest(canonical({"snapshot": self.state["snapshot"], **value}))
        value["dispatched"] = False
        return value

    def fetch(self, kind, endpoint, expected=None):
        return self.action(kind, "fetch", {"url": f"https://api.github.com/repos/{REPOSITORY}/{endpoint}"}, expected)

    def ref_action(self, kind):
        return self.fetch(kind, "git/ref/heads/" + quote(BRANCH, safe="/"), {"ref": "refs/heads/" + BRANCH})

    def next(self):
        require(self.state, "No checkpoint exists")
        require(not self.state.get("blocked"), self.state.get("blocked"))
        if self.state.get("durable"):
            return {"kind": "noop", **self.status("unchanged")}
        if self.state.get("github_durable"):
            return self.drive_required()
        pending = self.state.get("pending")
        if pending:
            if pending["mutating"] and not pending["dispatched"] and not self.drive_verified():
                return self.drive_required()
            if pending["dispatched"] and pending["mutating"]:
                return self.reconcile_action(pending)
            return pending
        m, s = self.manifest(), self.state
        repo = {"repository_full_name": REPOSITORY}
        if not s["repo_verified"]:
            action = self.action("verify_repository", "fetch", {"url": f"https://api.github.com/repos/{REPOSITORY}"})
        elif not s["branch_verified"] and not s["branch_absent"]:
            action = self.ref_action("verify_start_ref")
        elif not self.drive_verified():
            return self.drive_required()
        elif not s["branch_verified"]:
            if s["branch_absent"]:
                action = self.action("create_branch", "create_branch", {**repo, "branch_name": BRANCH, "sha": s["parent"]}, {"sha": s["parent"]}, True)
            else:
                action = self.ref_action("verify_start_ref")
        else:
            missing = next((f for f in m["files"] if f["sha"] not in s["known_blobs"]), None)
            tree = next((t for t in m["tree_operations"] if t["sha"] not in s["known_trees"]
                         and t["final_tree_sha"] not in s["known_trees"]), None)
            if missing:
                require(missing["size"] <= MAX_BLOB_BYTES, "New blob exceeds connector bound")
                data = (self.directory / "objects" / missing["sha256"]).read_bytes()
                require(digest(data) == missing["sha256"] and git_hash("blob", data) == missing["sha"], "Snapshot object is corrupt")
                action = self.action("create_blob", "create_blob", {**repo, "encoding": "base64", "content": base64.b64encode(data).decode("ascii")}, {"sha": missing["sha"], "size": missing["size"]}, True)
            elif tree:
                action = self.action("create_tree", "create_tree", {**repo, "base_tree_sha": tree["base_tree_sha"], "tree_elements": tree["tree_elements"]}, {"sha": tree["sha"]}, True)
            elif not s["candidate_commit"]:
                action = self.action("create_commit", "create_commit", {**repo, "message": self.commit_message(), "parent_sha": s["parent"], "tree_sha": m["root_tree_sha"]}, mutating=True)
            elif not s["commit_verified"]:
                action = self.fetch("verify_commit", "git/commits/" + s["candidate_commit"])
            elif not s["pre_update_verified"]:
                action = self.ref_action("verify_lease")
            elif not s["updated"]:
                action = self.action("update_ref", "update_ref", {**repo, "branch_name": BRANCH, "sha": s["candidate_commit"], "expected_sha": s["parent"], "force": False}, {"sha": s["candidate_commit"]}, True)
            elif not s["tree_verified"]:
                action = self.fetch("verify_recursive_tree", "git/trees/" + m["root_tree_sha"] + "?recursive=1")
            else:
                action = self.ref_action("verify_final_ref")
        self.state["pending"] = action
        self.save()
        return action

    def drive_verified(self):
        receipt = self.state.get("drive_durable")
        return bool(receipt and receipt.get("snapshot") == self.state["snapshot"]
                    and receipt.get("root_tree_sha") == self.manifest()["root_tree_sha"]
                    and receipt.get("folder_id") == DRIVE_FOLDER
                    and receipt.get("account_email") == DRIVE_ACCOUNT)

    def drive_required(self):
        return {"kind": "drive_checkpoint_required", "development_allowed": False,
                "snapshot": self.state["snapshot"], "root_tree_sha": self.manifest()["root_tree_sha"],
                "account_email": DRIVE_ACCOUNT, "folder_id": DRIVE_FOLDER,
                "export": self.state.get("drive_export"),
                "instruction": "Export the frozen delta, obtain authorized Drive upload/download verification, then record-drive. No Git write is allowed yet."}

    def complete_if_both(self):
        if self.state.get("github_durable") and self.drive_verified():
            self.state["durable"] = {**self.state["github_durable"], "drive": self.state["drive_durable"]}
            atomic_json(self.directory / "gate.json", {"development_allowed": True, "durable": self.state["durable"]})
        else:
            atomic_json(self.directory / "gate.json", {"development_allowed": False, "reason": "Both exact destinations are required"})

    def export_drive(self, baseline, output):
        require(self.state and not self.state.get("blocked"), "Gate is blocked or missing")
        manifest = self.manifest()
        base_commit, base_tree, base_entries = validate_metadata(read_json(baseline))
        old_files = {e["path"]: e for e in base_entries if e["type"] == "blob"}
        files = {e["path"]: e for e in manifest["files"]}
        changed = [item for path, item in sorted(files.items())
                   if path not in old_files or any(item[k] != old_files[path][k] for k in ("mode", "sha"))]
        deleted = sorted(set(old_files) - set(files))
        index = {"version": 1, "repository": REPOSITORY, "branch": BRANCH,
                 "snapshot": self.state["snapshot"], "root_tree_sha": manifest["root_tree_sha"],
                 "baseline_commit_sha": base_commit, "baseline_tree_sha": base_tree,
                 "changed_files": changed, "deleted_files": deleted,
                 "expected_recursive_tree": manifest["expected_recursive_tree"]}
        index_bytes = canonical(index) + b"\n"
        require(sum(f["size"] for f in changed) + len(index_bytes) + 1024 * len(changed) <= MAX_DRIVE_EXPORT,
                "Delta exceeds the bounded single-file Drive export; require a reviewed multipart handoff")
        output = Path(output).resolve()
        source = Path(self.state["source"]).resolve()
        require(output != source and source not in output.parents, "Drive export must be outside frozen source")
        output.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".drive-export-", dir=output.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
                def write_member(name, data, mode="100644"):
                    entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                    entry.create_system = 3
                    entry.external_attr = int(mode, 8) << 16
                    archive.writestr(entry, data)
                write_member("checkpoint.json", index_bytes)
                for item in changed:
                    data = (self.directory / "objects" / item["sha256"]).read_bytes()
                    require(digest(data) == item["sha256"] and git_hash("blob", data) == item["sha"], "Snapshot object is corrupt")
                    write_member("files/" + item["path"], data, item["mode"])
            # Verify exact archive membership and payload bytes before handoff.
            with zipfile.ZipFile(temporary) as archive:
                require(archive.namelist() == ["checkpoint.json"] + ["files/" + f["path"] for f in changed], "Delta ZIP membership mismatch")
                require(archive.read("checkpoint.json") == index_bytes, "Delta ZIP index mismatch")
                for item in changed:
                    require(digest(archive.read("files/" + item["path"])) == item["sha256"], "Delta ZIP payload mismatch")
            hashes = file_hashes(temporary)
            require(hashes["size"] <= MAX_DRIVE_EXPORT, "Drive delta ZIP exceeds byte bound")
            if output.exists():
                require(file_hashes(output) == hashes, "Refusing to overwrite a different existing Drive export")
            else:
                os.replace(temporary, output)
                os.chmod(output, 0o444)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        descriptor = {**hashes, "path": str(output), "snapshot": self.state["snapshot"],
                      "root_tree_sha": manifest["root_tree_sha"], "baseline_commit_sha": base_commit,
                      "baseline_tree_sha": base_tree, "changed_files": len(changed), "deleted_files": len(deleted),
                      "account_email": DRIVE_ACCOUNT, "link_id": DRIVE_LINK_ID,
                      "profile_id": DRIVE_PROFILE_ID, "folder_id": DRIVE_FOLDER,
                      "archive_readback_verified": True}
        self.state["drive_export"] = descriptor
        atomic_json(str(output) + ".descriptor.json", descriptor, immutable=True)
        self.save()
        return {"outcome": "drive_export_ready", "development_allowed": False, "export": descriptor}

    def record_drive(self, receipt):
        require(self.state and not self.state.get("blocked"), "Gate is blocked or missing")
        exported = self.state.get("drive_export")
        require(exported, "Export the exact checkpoint delta before recording Drive success")
        require(receipt.get("snapshot") == self.state["snapshot"] and receipt.get("root_tree_sha") == self.manifest()["root_tree_sha"],
                "Drive receipt belongs to a different snapshot/root tree")
        account = receipt.get("account", {})
        require(account == {"email": DRIVE_ACCOUNT, "link_id": DRIVE_LINK_ID, "profile_id": DRIVE_PROFILE_ID},
                "Drive receipt is not linked to the explicitly authorized account")
        require(receipt.get("folder_id") == DRIVE_FOLDER, "Drive receipt uses the wrong destination folder")
        metadata = unwrap_result(receipt.get("readback_metadata", {}))
        file_id = receipt.get("uploaded_file_id")
        require(isinstance(file_id, str) and file_id and metadata.get("id") == file_id, "Drive upload/readback file ID mismatch")
        require(metadata.get("parents", metadata.get("parent_ids")) == [DRIVE_FOLDER], "Drive readback parent mismatch")
        require(not metadata.get("trashed"), "Drive readback file is trashed")
        require(int(metadata.get("size", -1)) == exported["size"], "Drive readback size mismatch")
        baseline = receipt.get("baseline_coverage", {})
        require(baseline.get("commit_sha") == exported["baseline_commit_sha"]
                and baseline.get("tree_sha") == exported["baseline_tree_sha"]
                and baseline.get("folder_id") == DRIVE_FOLDER
                and baseline.get("account_email") == DRIVE_ACCOUNT
                and bool(baseline.get("index_file_id"))
                and baseline.get("readback_verified") is True and baseline.get("tree_verified") is True,
                "Delta requires a verified, recoverable baseline in the same approved Drive destination")
        base_hash = baseline.get("archive_sha256", "")
        require(re.fullmatch(r"[0-9a-f]{64}", base_hash) and baseline.get("recombined_sha256") == base_hash,
                "Baseline archive/recombined SHA256 mismatch")
        downloaded = receipt.get("download", {})
        require(downloaded.get("file_id") == file_id, "Downloaded Drive object ID mismatch")
        local = Path(exported["path"]).resolve(strict=True)
        remote_copy = Path(downloaded.get("path", "")).resolve(strict=True)
        require(local != remote_copy and not os.path.samefile(local, remote_copy), "Drive readback must be a distinct downloaded file")
        expected = {key: exported[key] for key in ("sha256", "md5", "size")}
        require(file_hashes(local) == expected, "Frozen Drive export changed after preparation")
        require(file_hashes(remote_copy) == expected, "Downloaded Drive bytes do not match the exact frozen archive")
        remote_md5 = metadata.get("md5Checksum", metadata.get("md5_checksum"))
        require(remote_md5 is None or remote_md5 == exported["md5"], "Drive-reported MD5 mismatch")
        require(receipt.get("archive_sha256") == exported["sha256"], "Drive receipt archive SHA256 mismatch")
        record = {"snapshot": self.state["snapshot"], "root_tree_sha": exported["root_tree_sha"],
                  "account_email": DRIVE_ACCOUNT, "link_id": DRIVE_LINK_ID, "profile_id": DRIVE_PROFILE_ID,
                  "folder_id": DRIVE_FOLDER, "file_id": file_id, **expected,
                  "baseline_index_file_id": baseline["index_file_id"], "download_readback_verified": True,
                  "url": metadata.get("webViewLink", metadata.get("url", metadata.get("display_url")))}
        atomic_json(self.directory / "receipts" / (digest(canonical(receipt)) + ".drive.json"), receipt, immutable=True)
        self.state["drive_durable"] = record
        self.complete_if_both()
        self.save()
        return self.status("drive_receipt_validated")

    def commit_message(self):
        return f"Star Courier checkpoint {self.state['snapshot']}\n\n{self.state['reason']}"

    def dispatch(self, action_id):
        action = self.state.get("pending")
        require(action and action["id"] == action_id, "No matching planned action")
        require(not action["dispatched"], "Action already dispatched: reconcile before retry")
        require(not action["mutating"] or self.drive_verified(), "Verified same-snapshot Drive backup is required before any Git write")
        action["dispatched"] = True
        self.save()
        return {"dispatch_recorded": action_id, "mutating": action["mutating"]}

    def reconcile_action(self, original):
        kind = original["kind"]
        if kind in ("create_branch", "update_ref"):
            action = self.ref_action("reconcile_ref")
        elif kind in ("create_blob", "create_tree"):
            family = "blobs/" if kind == "create_blob" else "trees/"
            action = self.fetch("reconcile_object", "git/" + family + original["expected"]["sha"], original["expected"])
        else:
            return {"kind": "blocked_uncertain_commit", "development_allowed": False,
                    "original_action_id": original["id"],
                    "instruction": "Recover the commit SHA from the original connector receipt, then use recover-commit. Do not repeat create_commit."}
        action["reconciles"] = original["id"]
        action["id"] = digest(canonical({"original": original["id"], "reconciliation": action}))
        # Read-only reconciliation is intentionally repeatable. The original write remains in flight.
        return action

    @staticmethod
    def ref_sha(result):
        require(result.get("ref") == "refs/heads/" + BRANCH, "Receipt targets the wrong branch")
        require(result.get("object", {}).get("type") == "commit", "Branch does not point to a commit")
        return checked_sha(result["object"].get("sha"))

    def validate_commit(self, result):
        require(result.get("sha") == self.state["candidate_commit"], "Commit SHA mismatch")
        require(result.get("tree", {}).get("sha") == self.manifest()["root_tree_sha"], "Commit tree mismatch")
        if self.state["reuse_parent_commit"]:
            return
        require([x.get("sha") for x in result.get("parents", [])] == [self.state["parent"]], "Commit parent mismatch")
        require(result.get("message", "").rstrip("\n") == self.commit_message(), "Commit checkpoint message mismatch")

    def apply(self, action_id, receipt):
        require(self.state and not self.state.get("blocked"), "Gate is blocked or missing")
        pending = self.state.get("pending")
        require(pending, "No pending action")
        reconciliation = None
        if action_id != pending["id"]:
            reconciliation = self.reconcile_action(pending)
            require(reconciliation.get("id") == action_id, "Receipt does not match the pending action")
        else:
            require(pending["dispatched"], "Record dispatch before executing/applying a connector call")
        require(isinstance(receipt, dict) and receipt.get("status") in ("ok", "not_found", "uncertain", "error", "denied"), "Invalid receipt status")
        status = receipt["status"]
        if status == "denied":
            raise Blocked("Connector denied the action; stop and request authorized resolution")
        if status in ("uncertain", "error"):
            # Writes stay dispatched. Read-only calls can be planned again safely.
            if not pending["mutating"]:
                pending["dispatched"] = False
            self.save()
            return {"outcome": "reconciliation_required" if pending["mutating"] else "read_retry_required", "development_allowed": False}
        result = unwrap_result(receipt.get("result", {})) if status == "ok" else {}
        if reconciliation:
            self.apply_reconciliation(pending, status, result)
        else:
            self.apply_success(pending, status, result)
        self.state["receipt_count"] += 1
        record = {"action_id": action_id, "kind": (reconciliation or pending)["kind"],
                  "status": status, "result": result}
        atomic_json(self.directory / "receipts" / (digest(canonical(record)) + ".json"), record, immutable=True)
        self.save()
        return self.status("receipt_validated")

    def apply_reconciliation(self, action, status, result):
        kind = action["kind"]
        if kind in ("create_blob", "create_tree"):
            if status == "not_found":
                action["dispatched"] = False  # Authoritative negative read permits identical retry.
                return
            require(result.get("sha") == action["expected"]["sha"], "Reconciled object SHA mismatch")
            if kind == "create_blob":
                require(result.get("size") == action["expected"]["size"], "Reconciled blob size mismatch")
            key = "known_blobs" if kind == "create_blob" else "known_trees"
            self.state[key] = sorted(set(self.state[key]) | {result["sha"]})
        elif kind in ("create_branch", "update_ref"):
            if status == "not_found":
                require(kind == "create_branch", "Backup branch disappeared during update")
                action["dispatched"] = False
                return
            head = self.ref_sha(result)
            expected = action["expected"]["sha"]
            if head == expected:
                if kind == "create_branch":
                    self.state["branch_verified"] = True
                    self.state["branch_absent"] = False
                else:
                    self.state["updated"] = True
            elif kind == "update_ref" and head == self.state["parent"]:
                action["dispatched"] = False
                return
            else:
                raise Blocked("Branch race: remote head changed; do not force or overwrite it")
        self.state["pending"] = None

    def apply_success(self, action, status, result):
        kind, s = action["kind"], self.state
        if status == "not_found":
            require(kind == "verify_start_ref", "Unexpected missing remote resource")
            s["branch_absent"] = True
        elif kind == "verify_repository":
            raw_private = result.get("full_name") == REPOSITORY and result.get("private") is True
            normalized_private = result.get("repository_full_name") == REPOSITORY and result.get("visibility") == "private"
            require(raw_private or normalized_private, "Destination is not the authorized private repository")
            s["repo_verified"] = True
        elif kind == "verify_start_ref":
            require(self.ref_sha(result) == s["parent"], "Branch race: initial head differs from verified parent")
            s["branch_verified"] = True
        elif kind == "create_branch":
            # Always read back: connector write responses may be normalized.
            if result.get("ref"):
                require(self.ref_sha(result) == s["parent"], "Created branch SHA mismatch")
            s["branch_absent"] = False
        elif kind in ("create_blob", "create_tree"):
            require(result.get("sha") == action["expected"]["sha"], "Created Git object SHA mismatch")
            key = "known_blobs" if kind == "create_blob" else "known_trees"
            s[key] = sorted(set(s[key]) | {result["sha"]})
        elif kind == "create_commit":
            s["candidate_commit"] = checked_sha(result.get("sha"))
        elif kind == "verify_commit":
            self.validate_commit(result)
            s["commit_verified"] = True
        elif kind == "verify_lease":
            require(self.ref_sha(result) == s["parent"], "Branch race: head changed before compare-and-swap")
            s["pre_update_verified"] = True
        elif kind == "update_ref":
            if result.get("ref"):
                require(self.ref_sha(result) == s["candidate_commit"], "Updated branch SHA mismatch")
            s["updated"] = True
        elif kind == "verify_recursive_tree":
            manifest = self.manifest()
            require(result.get("sha") == manifest["root_tree_sha"], "Remote root tree SHA mismatch")
            require(normalized_tree(result) == manifest["expected_recursive_tree"], "Remote recursive tree is not the exact snapshot")
            s["tree_verified"] = True
        elif kind == "verify_final_ref":
            require(self.ref_sha(result) == s["candidate_commit"], "Branch race during final verification")
            current, _ = capture(s["source"], self.directory)
            require(current == s["snapshot"], "Source changed while backup was pending; freeze writers and reconcile before development")
            s["github_durable"] = {"commit_sha": s["candidate_commit"], "tree_sha": self.manifest()["root_tree_sha"],
                            "url": f"https://github.com/{REPOSITORY}/commit/{s['candidate_commit']}",
                            "snapshot": s["snapshot"], "exact_recursive_tree_verified": True}
            self.complete_if_both()
        else:
            raise Blocked("Unknown action kind")
        s["pending"] = None

    def recover_commit(self, sha):
        action = self.state.get("pending")
        require(action and action["kind"] == "create_commit" and action["dispatched"],
                "No uncertain create_commit to reconcile")
        self.state["candidate_commit"] = checked_sha(sha)
        self.state["pending"] = None
        self.save()
        return {"outcome": "read_only_commit_verification_required", "development_allowed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, help="Local state directory, outside the source tree")
    commands = parser.add_subparsers(dest="command", required=True)
    snapshot = commands.add_parser("snapshot")
    snapshot.add_argument("--source", required=True)
    snapshot.add_argument("--baseline", help="Verified full repo/commit/recursive-tree JSON; required once")
    snapshot.add_argument("--reason", required=True)
    nxt = commands.add_parser("next")
    nxt.add_argument("--out", help="Write bounded action JSON to a file; avoids printing large base64 payloads")
    dispatch = commands.add_parser("dispatch")
    dispatch.add_argument("--action-id", required=True)
    apply_result = commands.add_parser("apply-result")
    apply_result.add_argument("--action-id", required=True)
    apply_result.add_argument("--receipt", required=True)
    recover = commands.add_parser("recover-commit")
    recover.add_argument("--sha", required=True)
    export = commands.add_parser("export-drive")
    export.add_argument("--baseline", required=True)
    export.add_argument("--out", required=True)
    drive = commands.add_parser("record-drive")
    drive.add_argument("--receipt", required=True)
    commands.add_parser("status")
    gate = None
    args = parser.parse_args(argv)
    try:
        gate = Gate(args.state)
        if args.command == "snapshot":
            result = gate.snapshot(args.source, args.baseline, args.reason)
        elif args.command == "next":
            result = gate.next()
            if args.out:
                atomic_json(args.out, result)
                result = {"kind": result["kind"], "action_id": result.get("id"),
                          "action_file": str(Path(args.out).resolve()), "development_allowed": bool(result.get("development_allowed")),
                          "payload_bytes": len(canonical(result))}
        elif args.command == "dispatch":
            result = gate.dispatch(args.action_id)
        elif args.command == "apply-result":
            result = gate.apply(args.action_id, read_json(args.receipt))
        elif args.command == "recover-commit":
            result = gate.recover_commit(args.sha)
        elif args.command == "export-drive":
            result = gate.export_drive(args.baseline, args.out)
        elif args.command == "record-drive":
            result = gate.record_drive(read_json(args.receipt))
        else:
            result = gate.status()
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (Blocked, OSError, ValueError, KeyError, TypeError) as error:
        message = str(error)
        if gate:
            gate.block(message)
        print(json.dumps({"outcome": "blocked", "development_allowed": False, "reason": message}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
