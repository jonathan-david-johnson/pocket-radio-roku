# PocketStreams for Roku

A Roku channel that plays your [Pocket Casts](https://pocketcasts.com) **Up Next** podcast queue (with resume + progress sync) and your **favorite radio streams** (via [radio-browser.info](https://radio-browser.info)). Companion to the [PocketRadio](https://github.com/jonathan-david-johnson/PocketRadio) project — feature parity with its macOS menubar app.

Built in BrightScript + SceneGraph. No emulator — all testing on a physical Roku in dev mode.

## Status

Pre-implementation. See [`HANDOFF.md`](./HANDOFF.md) — the self-contained build spec (every endpoint, protobuf wire format, key, and Roku gotcha). Milestone + spike planning lives in the parent PocketRadio repo under `docs/roku/`.

The pivotal open question: **can Roku speak Pocket Casts' protobuf API natively, or do we need a JSON↔protobuf relay?** Resolved by the spikes before milestone work begins.

## Quick start

```bash
# Enable dev mode on the Roku, then set device creds (kept out of git):
export ROKU_HOST=10.99.99.50          # your device IP
export ROKU_PASS=...                  # dev-mode password

make help        # list targets
make deploy      # zip + sideload to the device
make telnet      # open the BrightScript debug console (port 8085)
```

Dev-only credentials (Pocket Casts test account, device password) live in `SECRETS.local.md` — **gitignored, never committed**.

## Layout (once scaffolded)

```
manifest                       # channel metadata
source/main.brs                # Sub Main() -> SceneGraph scene
components/                    # SceneGraph scenes + views
components/tasks/              # Task nodes — all network I/O
images/                        # channel icons + splash
```

## License

Mozilla Public License 2.0 — same as the upstream Pocket Casts project.
