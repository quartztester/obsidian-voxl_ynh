# obsidian-voxl — packaging design

Obsidian desktop app run on the server and streamed to the browser through voxl,
a Rust X11-to-H.264 WebSocket streamer. The one property that shapes the package:
voxl ships no prebuilt binaries — only the source crate — so the box builds it.

Anything not mentioned below is standard YunoHost boilerplate identical in most packages.

## Lifecycle
- **Install:** questions → `ynh_setup_source` (Obsidian tarball) → build voxl from the
  pinned crate → vault seed → nginx + systemd → start, seed the vault registry once
  the profile exists, restart.
- **Upgrade:** same deploy `--full_replace`, with the built `$install_dir/voxl` moved
  aside and restored around it (`scripts/upgrade` L15-L25); the vault-then-rebuild
  guard in `_common.sh` is the fallback; vault and settings survive untouched.
- **Backup/restore:** `$install_dir` (includes the built `voxl` binary), `$data_dir`,
  nginx and systemd files; restore re-checks the binary and rebuilds if absent.

## Decisions
- **Source:** Obsidian release tarballs per-arch with sha256 pins; a second decoy
  source (`sources.voxl`, manifest.toml L74-L84) exists only so the update bot tracks
  voxl releases — the real pin is duplicated in `scripts/_common.sh` L9-L10.
- **Runtime:** Electron (no build); voxl built on the box with cargo (`_common.sh` L34-L67):
  crate fetched and sha256-checked, rustup toolchain 1.85.1 installed under a scratch
  `$RUSTUP_HOME` because Debian bookworm's cargo 1.63 cannot parse the crate's v4 lock file,
  build deps via `[resources.apt]`. Binary lands in `$install_dir/voxl`, owned by `$app`.
- **Services:** one unit; start.sh runs Xvfb, openbox, tint2, voxl, and a supervisor loop
  restarting Obsidian while the display lives (`conf/start.sh` L31-L43).
- **Storage:** no DB; vault in `$data_dir/vault`, uploads via voxl's file panel into
  `$data_dir/vault/attachments`.
- **Auth:** ldap/sso `not_relevant`; access is the YunoHost permission on `/`.
- **Email:** no mail.
- **Path:** subdir; nginx `#sub_path_only` rewrite enforces the trailing slash.
- **Ports/firewall:** one port, loopback only, never exposed; voxl listens on it and
  nginx is the single door.
- **Scheduler:** none.
- **Migration:** none yet; `resolution` setting re-derived when missing
  (`_common.sh` L16-L21) covers upgrade/restore from older settings.
- **Sandboxing:** Obsidian runs `--no-sandbox --disable-gpu --disable-dev-shm-usage`
  as the app user (Electron under Xvfb); voxl drops nothing — it refuses host names
  outside `--allowed-hosts=__DOMAIN__` (`conf/start.sh` L25-L27).
- **Backup:** everything in/out; nothing regenerated on restore except log dir.
- **Admin-surface:** config panel has only `resolution` (drives Xvfb size at next restart).

## Don't break
- `--allowed-hosts=__DOMAIN__`: without it voxl 403s every proxied request
  (DNS-rebinding guard) — `conf/start.sh` L25-L27.
- voxl needs the crate built with `--locked` and rustup ≥1.85; "simplifying" to apt
  rustc breaks the build on bookworm (v4 lock file) — `scripts/_common.sh` L57-L63.
- The vault registry seed runs only at install after `Local State` exists
  (`scripts/install` L43-L53); moving it earlier writes a config Obsidian overwrites.
- `ram.build = "1G"` is for the voxl cargo build, not Obsidian — do not trim.
- Build is per-instance and survives backup via `$install_dir`; a restore onto a new
  arch rebuilds only if the restored binary cannot execute — the guard runs
  `voxl --version` (`scripts/_common.sh` L36), so a foreign-arch binary on a
  binfmt-emulated host could slip through.
- `--full_replace` deletes the built binary; the move-aside in `scripts/upgrade`
  is what keeps upgrades fast. Removing it silently adds a full recompile per upgrade.
