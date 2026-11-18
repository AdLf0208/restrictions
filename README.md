# Restrictions — a Horizon port

**Restrictions** is a Minecraft mod. All about restricting (and enabling) movement. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [McJtyMods/restrictions](https://github.com/McJtyMods/restrictions) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Restrictions ([source](https://github.com/McJtyMods/restrictions)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `restrictions.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

### What is implemented (slice 1)

- **Attractor** and **Pusher**: the cells in front of the block, `pos + facing*1 …
  pos + facing*signal` (its own cell excluded), where `signal` is the strongest neighbouring
  redstone signal (0 = off). Each server tick, every mob whose bounding box meets that run gets a
  velocity impulse along the facing: **−0.1** blocks/tick for the attractor (toward the block) and
  **+0.1** for the pusher (away). No line-of-sight test (upstream has none).
- The two movers own block entity types (`restrictions:attractor`, `restrictions:pusher`) and
  tick through their Part; the facing comes from the block's `facing` property, the level from
  the level in place.
- All four carried blocks (`attractor`, `pusher`, `oneway`, `oneway_wall`) take the placer's
  horizontal facing when placed, as McJtyLib's `BaseBlock` does.
- Nothing carried is dropped: the four blocks, the Glass Boots item, the creative tab, the
  recipes (with the `c:` tags they reference), the loot tables, the advancements and both
  language files are inside the package.

## Not yet ported

- **One Way / One Way Wall have no behaviour.** Upstream's One Way is `noCollission()` and pushes
- **Players** cannot be moved server-side: `EntityRef::push` refuses a player (its client moves
- **Item entities and arrows/boats/orbs** are out of this slice's mob filter. The host can now
- **Fall-distance reset** for `facing=up` (above).
- The **in-game e2e was not re-run** in this migration: it needs a game the launcher built with

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `restrictions.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Restrictions was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/McJtyMods/restrictions

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run restrictions` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/restrictions/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
