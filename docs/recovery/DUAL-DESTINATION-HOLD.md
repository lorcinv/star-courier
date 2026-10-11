# Drive-first recovery checkpoint

The user requires this exact order: save and verify the frozen checkpoint in Google Drive first, then publish and verify it in private GitHub.

Approved Drive account: `lk520222333@gmail.com`, verified profile `118419590976145726901`, folder `1e_l2SnyhtlQBSFokQlZ7sS9_RdXKj4OZ` (星际快递备份). This replaces the earlier folder in a different account; that earlier destination cannot satisfy this gate.

Confirmed Git destination: private `lorcinv/star-courier`, branch `wip/recovery-20261011`. Main remains unchanged. The executable `tools/checkpoint_backup.py` now blocks all Git mutations until actual Drive download verification covers the same source snapshot and its baseline. It then verifies the complete Git tree, final branch ref and source identity. Both destinations are required before new game reconstruction starts.

The mechanism passed 30 offline fixture tests, including interruption, wrong account/folder, corrupt readback, deterministic export, unchanged runs and branch races. These are backup-tool tests, not fresh game-play validation. The game recovery remains incomplete because the documented resources are missing. No Git writes had occurred when this snapshot was frozen.

Every archive receipt identifies source tree, correct account/folder, file ID, byte count and downloaded SHA-256. Large baseline archives may be split losslessly with indexed part hashes and a verified recombined ZIP. No prior backup is to be deleted. See `docs/BACKUP_POLICY.md` for exact operator commands and receipt schema.
