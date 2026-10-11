# Star Courier recovery checkpoint policy: Drive first, then GitHub

## Destination and stop rule

The exact authorized destinations are:

1. **Google Drive first**: account `lk520222333@gmail.com`, connection
   `link_6acb98a04ab8819188482234fc6ef229`, profile `118419590976145726901`, folder
   `1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ`.
2. **GitHub second**: the existing private `lorcinv/star-courier` repository,
   branch `wip/recovery-20261011`.

The old Drive folder from a different account does not count. No other account
or folder is accepted. The root's explicitly authorized correct-account uploader
owns Drive transport. This script neither uploads nor authenticates to Drive.

The tool hardcodes these verified destinations and never writes `main`,
force-pushes, merges, deploys, installs credentials, or makes network requests.
An authorized operator performs emitted GitHub calls with the supported connector.
**Before a verified same-snapshot Drive receipt, the tool may emit repository/ref
reads but never a Git branch, blob, tree, commit, or ref mutation.** `dispatch`
also enforces this condition, including a mutation planned by the old tool.

Run a checkpoint at each new-art or feature milestone, before a pause or session
handoff, and when the existing 30-minute oversight task finds unbacked changes.
Only one publisher may own a checkpoint at a time. That schedule is oversight;
this tool itself neither schedules jobs nor runs unattended network transport.

**Freeze source writers before capture and keep them frozen through completion.**
If a backup is pending, denied, uncertain, failed, or mismatched, stop new
art/feature/development work. Diagnose and finish or reconcile the backup first.
The current recovery is incomplete; successful backup does not certify that the
game is runnable and does not authorize reconstruction or feature changes.

A local snapshot, upload response, commit creation response, or ref-update
response is **not durable success**. Success requires all of these:

0. The same frozen snapshot is durably preserved on the exact approved Drive
   account/folder first, including a verified restorable baseline and its delta.
   A downloaded copy of the actual uploaded delta must match its local SHA-256,
   MD5, and byte count. Only then may any Git mutation begin.
1. The authorized repository is verified private through a fresh connector read.
2. The new commit's SHA, parent, message, and root tree match the checkpoint.
3. The branch changes through `update_ref` with the exact `expected_sha` and
   `force: false`; an absent branch is created from the verified baseline first.
4. A fresh complete recursive remote tree (`truncated: false`) equals every
   expected file/subtree path, mode, type, and SHA, with no extra or missing entry.
5. A final branch read points to that exact commit and the frozen local source
   still matches the captured snapshot.
6. `status` separately records `drive_durable` and `github_durable`, and reports
   `development_allowed: true` only when both cover the same snapshot/root tree.
   Git-only success cannot open the combined gate.

The gate is an operator workflow, not an OS sandbox that prevents arbitrary
editors from writing. Never treat a command's zero exit code as an open gate;
most successful planning commands intentionally report a closed gate.

## Files preserved and omitted

Preserve permitted game/source scripts and configuration, runtime art/audio,
editable Blender `.blend` files, REAPER `.rpp` projects and audio stems, licenses,
documentation, tests, source `.patch`/`.diff` inputs, and provenance. In particular,
`docs/recovery` and `source_art/recovery_inputs` are included. Godot `.uid` and
per-asset `.import` sidecars are included; Godot's cache directories are not.

The explicit allowlist and exclusions live in `tools/checkpoint_backup.py`.
Unrecognized file types block capture for review instead of silently disappearing.
Excluded files/directories are enumerated in local `exclusions.json`; a listed
directory means its entire subtree. Review this audit on the first run and after
policy or source-layout changes. It intentionally does not follow symlinks.

Exclude caches, credentials and secret-named files, build/export directories,
bulk logs, videos, archives, editor backup copies (`.blend1`, `.rpp-bak`, etc.),
REAPER peak caches, and duplicate backup stores. No `.gitignore` rule can silently
remove permitted art. The scanner blocks symlinks, special files, and several
recognizable embedded private-key/token formats. This is a safeguard, not a
proof that arbitrary source contains no secret; inspect suspicious content
locally and never transmit credentials to make a backup work.

The generated `docs/checkpoints/backup-manifest.json` is a reserved path. Its
previous source copy is ignored and deterministically regenerated from every
permitted payload file except itself. The resulting manifest blob is then
included in the final tree. It contains SHA-256, Git blob SHA, size, executable
mode, and the complete payload tree without a hash self-cycle. There are no
wall-clock timestamps or transient run metadata in that file. A restored clone
with identical files produces the identical manifest and no empty commit.

The first recovered-source preflight, before installing this mechanism, found
2,253 permitted files (399,262,223 bytes); only `builds/` and five `.reapeaks`
files were excluded. This is a historical audit, not the expected count of future
checkpoints. The actual checkpoint's generated manifest is authoritative.

## Bounds and local storage

Python 3 on a POSIX executor, standard library only. No token, password, `.git`
configuration, remote shell, undocumented API, or generic HTTP client is used.

- Maximum 20,000 payload files, 64 MiB per local file, 2 GiB total payload
- Maximum **new** blob 16 MiB; already verified Git blobs are reused by SHA
- Maximum one blob per connector action, 24 MiB serialized connector arguments
- At most 128 direct tree entries and 128 KiB arguments per tree action
- Large directories are built in bounded partial trees, bottom-up
- Existing complete remote subtrees and blobs are reused
- Drive delta ZIP maximum 100 MiB; larger deltas require a reviewed multipart handoff
- No parallel publisher; no unbounded retry loop

An over-limit file blocks the gate. Do not split, compress, omit, or invent an
alternate upload route automatically. Obtain a supported, reviewed path instead.
These are local safety bounds, not claims about the connector's service limits.

State must be **outside** the dedicated game source directory. State contains
read-only content-addressed `objects/`, immutable `snapshots/<id>/manifest.json`,
validated content-addressed `receipts/`, `checkpoint.json`, `gate.json`, and
`exclusions.json`. They are local resume aids and are never proof of off-machine
storage. Snapshot objects are copied, never hard-linked to mutable source files.
Full source metadata is checked before/after capture; every path component is
opened without following symlinks. Keep the old state until remote verification
finishes. Do not hand-edit a receipt or state file to make the gate pass.

## Exact operator loop

The first baseline JSON must have decoded `repo`, `commit`, and `tree` objects.
`repo` must identify the authorized private repository. `commit.tree.sha` must
match `tree.sha`. `tree` must be a complete recursive Git tree with
`truncated: false`. The tool independently recomputes that tree hash.

For the first recovery publication, use the existing verified
`recovery/git-baseline-metadata.json`. For a new executor restoring the private
WIP branch, fetch that branch's actual head, Git commit, repository metadata, and
complete recursive tree through the supported connector; use those as the new
baseline, not stale `main` metadata. Restore exact modes and bytes and inspect
the committed backup manifest. Do not reconstruct missing source.

From the dedicated game source root, with `STATE` outside it:

```sh
python tools/checkpoint_backup.py --state "$STATE" snapshot \
  --source "$SOURCE" --baseline "$BASELINE_JSON" \
  --reason "Initial exact recovered WIP checkpoint"
python tools/checkpoint_backup.py --state "$STATE" next --out "$ACTION_JSON"
```

Before any Git mutation, export and hand off the exact snapshot:

```sh
python tools/checkpoint_backup.py --state "$STATE" export-drive \
  --baseline "$BASELINE_JSON" --out "$STATE/checkpoint-delta.zip"
```

The output includes a descriptor and writes a matching `.descriptor.json`.
The ZIP uses sorted members, stored bytes, fixed 1980 timestamps, and explicit
modes. `checkpoint.json` lists its verified Git baseline commit/tree, all changed
files, deletions, and the complete expected final tree. Payload members are under
`files/`. The generated durable backup manifest is included. The script verifies
membership and every ZIP payload before handoff; it never reads mutable source
for this export. Export and receipt files must stay outside the frozen source.

The baseline is independently validated from complete Git metadata. It may be
an older verified base when reusing an already uploaded delta after a workspace
restart. Use that delta's original baseline to regenerate its identical bytes;
do not upload a second empty backup merely because local state was lost.

The authorized uploader uploads this exact archive to the stated folder, reads
back metadata for the returned file ID, downloads that actual Drive object to a
distinct local file, and verifies the baseline dependency. It supplies the
actual evidence described in the next section. Then run:

```sh
python tools/checkpoint_backup.py --state "$STATE" record-drive \
  --receipt "$DRIVE_RECEIPT_JSON"
```

`drive_checkpoint_required` is a closed gate with instructions, not a connector
operation. After `record-drive` succeeds, resume `next` below. A successful Drive
receipt still does not open development until Git completes exact verification.

Read a connector action JSON. `tool` names the GitHub connector operation and `arguments`
are its exact bounded arguments. For a normal planned action, durably mark its
ID **before** calling the connector:

```sh
python tools/checkpoint_backup.py --state "$STATE" dispatch --action-id "$ID"
```

Call only the indicated supported GitHub connector operation with those
arguments. Save the actual response, without fabricating or changing any SHA:

```json
{"status":"ok","result":{"sha":"actual returned SHA"}}
```

`result` may be decoded API JSON or the real MCP response wrapper. Bounded
`structuredContent`, JSON `content`, and text-content wrappers are unwrapped;
conflicting candidate objects are rejected. Repository verification uses a raw
GitHub REST read, and also validates the connector's normalized private-repo
shape if supplied. Do not print blob payloads into chat.

Then:

```sh
python tools/checkpoint_backup.py --state "$STATE" apply-result \
  --action-id "$ID" --receipt "$RECEIPT_JSON"
python tools/checkpoint_backup.py --state "$STATE" next --out "$ACTION_JSON"
```

Repeat one action at a time until exact verification succeeds. An `ok` status
must represent a real successful response. Only an explicit authoritative 404
may be represented as `{"status":"not_found","result":{}}`. Permission
failures are `denied`; transport outcomes that may have executed are `uncertain`.
Use `error` for a failed read; for a write it is conservatively treated as
uncertain. Do not relabel an MCP `isError` response as `ok`.

Subsequent snapshots use the same state and omit `--baseline`; their parent is
the last exact verified checkpoint. An unchanged run returns `noop`, makes no
remote writes, and does not invent an empty commit. A fresh restored executor
performs read-only verification of the unchanged branch before opening its gate.

## Drive receipt contract

Save actual tool/readback evidence, never invented IDs or an assertion standing
in for a download. `record-drive` takes this JSON shape (placeholder values below
must be replaced with the exact descriptor and returned evidence):

```json
{
  "snapshot": "descriptor snapshot ID",
  "root_tree_sha": "descriptor root tree SHA",
  "archive_sha256": "descriptor archive SHA256",
  "folder_id": "1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ",
  "account": {
    "email": "lk520222333@gmail.com",
    "link_id": "link_6acb98a04ab8819188482234fc6ef229",
    "profile_id": "118419590976145726901"
  },
  "uploaded_file_id": "actual returned Drive file ID",
  "readback_metadata": {
    "id": "same actual Drive file ID",
    "parent_ids": ["1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ"],
    "size": "actual returned byte count",
    "url": "actual returned view URL"
  },
  "download": {
    "file_id": "same actual Drive file ID",
    "path": "/absolute/path/to/actual/downloaded/delta.zip"
  },
  "baseline_coverage": {
    "commit_sha": "descriptor baseline commit SHA",
    "tree_sha": "descriptor baseline tree SHA",
    "folder_id": "1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ",
    "account_email": "lk520222333@gmail.com",
    "index_file_id": "actual verified baseline or multipart-index Drive ID",
    "archive_sha256": "SHA256 of original exact baseline archive",
    "recombined_sha256": "same SHA256 after actual part readback/recombination",
    "readback_verified": true,
    "tree_verified": true
  }
}
```

The metadata may use raw `parents` or normalized `parent_ids`, and can be wrapped
in the actual MCP result. The connected metadata tool may omit its requested MD5
field; therefore actual file download is mandatory, and the script independently
hashes its bytes. If a server `md5Checksum`/`md5_checksum` is available, it must
also match. Reusing the original local export path or a hard link as a purported
Drive download is rejected.

The baseline flags summarize separately retained real verification evidence:
all baseline archive parts were downloaded from the approved folder, recombined
losslessly, and the restored baseline tree matched the descriptor's baseline.
The original baseline exceeds the connector's 100 MiB upload bound and is handled
by the authorized uploader's 80 MiB lossless parts plus a verified index. This
script neither splits that baseline nor uploads it. A delta without a recoverable
base cannot complete the gate. Account/folder linkage and these raw external
receipts are verified by the operator; JSON fields do not create authorization.

The v2 workflow preserves v1 snapshot/manifest formats so existing frozen bytes
can be exported without inventing a different tree. Loading a v1 Git-only success
explicitly closes the development gate until the correct Drive receipt is added.
The immutable Git-only v1 implementation remains separate historical evidence;
it is superseded by this two-destination order.

## Interruptions, uncertainty, and conflicts

If dispatch was recorded but the result was not applied, `next` does **not**
blindly repeat the write. It emits a read-only action with a `reconciles` field.
Call that read directly (do not dispatch it as a new normal action) and apply
its result using its own emitted ID. The original write remains in flight.

- Blob/tree uncertainty: read the exact expected content-addressed object. A
  matching SHA verifies its existence. An authoritative missing-object read
  permits retrying the identical planned write.
- Branch-create/ref-update uncertainty: read the exact target ref. The intended
  head resumes verification; the unchanged expected parent permits the same
  compare-and-swap retry. Any third head stops the gate. Never force over it.
- Commit-create uncertainty: this connector chooses server-side commit metadata,
  so an unreturned orphan commit cannot safely be identified from the local
  tree alone. Recover the actual SHA from the original tool receipt, then run:

```sh
python tools/checkpoint_backup.py --state "$STATE" recover-commit --sha "$ACTUAL_SHA"
```

The next action is a read-only commit verification. Never guess the SHA or
repeat `create_commit` blindly. If the receipt cannot be recovered, keep the
gate closed and escalate the exact blocker.

A wrong SHA, wrong repository, branch race, truncated/inexact tree, source edit
during publication, unexpected format, or denied action closes the gate. Inspect
remote state read-only and preserve the pending snapshot. If rebuilding local
state becomes necessary, first establish the exact remote head and complete
tree, resolve any unbacked local edits explicitly, and initialize a separate
state directory using that verified head. Never delete the old state merely to
bypass a mismatch. A blocked backup is not permission to change scope or routes.

## Offline verification

```sh
python -m unittest discover -s tests -p 'test_checkpoint_backup.py' -v
```

All 30 tests use temporary fixture directories and an in-memory simulated GitHub
transport. They cover first publication; unchanged and fresh-clone no-ops;
changed source; binary art, Blender, REAPER and licenses; explicit exclusions;
secret detection; symlink escape; deterministic hashes and executable modes;
bounded multi-chunk trees; interrupted object/ref/commit writes; crash between
receipt and state persistence; exact-tree mismatch; branch races; live source
changes; manifest tampering; and raw/MCP receipt shapes. They also cover Drive-first write gating, exact
account/folder/snapshot linkage, actual downloaded checksum validation,
deterministic delta archives with deletions/modes, baseline dependencies, and
migration of a previously open Git-only gate. They make no external
calls and do not mutate the production source or baseline. Live connector
publication still needs the verification sequence above.
