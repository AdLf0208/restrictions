# Restrictions for Horizon

A port of [Restrictions 1.21-7.0.3](https://github.com/McJtyMods/Restrictions) (McJty, MIT) to
Horizon 26.3, as one native `.hmod`: the carried blocks, models, textures, language, recipes and
loot are in `assets/` and `data/`, and the behaviour is in `src/`.

## What is implemented

- **Attractor** and **Pusher**: the cells in front of the block, `pos + facing*1 …
  pos + facing*signal` (its own cell excluded), where `signal` is the strongest neighbouring
  redstone signal (0 = off). Each server tick, **every entity** whose bounding box meets that run
  gets a velocity impulse along the facing — a mob, a dropped stack, an arrow, a boat, an
  experience orb; a player is skipped, because its own client owns its motion: **−0.1**
  blocks/tick for the attractor (toward the block) and **+0.1** for the pusher (away). No
  line-of-sight test (upstream has none).
- The two movers own block entity types (`restrictions:attractor`, `restrictions:pusher`) and
  tick through their Part; the facing comes from the block's `facing` property, the level from
  the level in place.
- All four carried blocks (`attractor`, `pusher`, `oneway`, `oneway_wall`) take the placer's
  horizontal facing when placed, as McJtyLib's `BaseBlock` does.
- Nothing carried is dropped: the four blocks, the Glass Boots item, the creative tab, the
  recipes (with the `c:` tags they reference), the loot tables, the advancements and both
  language files are inside the package.

## Not yet ported (the gaps)

- **One Way** and **One Way Wall**: upstream's One Way is `noCollission()` and pushes on
  `entityInside`. The pin has the hook (`BlockPart::entity_inside` with `EntityWrite::Push`), but
  it fires only for a block the entity already collides with (the shape that decides "inside" is
  not exposed), so a no-collision block never fires it. One Way Wall's collision depends on the
  entity's velocity, and no per-entity collision shape exists.
- **Players** cannot be moved server-side: the host refuses a player's push and its client owns
  its motion, so a player in a run is skipped (and Glass Boots has no observable effect here).
- **Fall-distance reset** for `facing=up` is not carried yet, though the pin now has the write
  (`ServerHost::entity_reset_fall_distance`) — it is the next slice.
- McJtyLib's two-block UP/DOWN placement rule is out of scope (vanilla's look direction is used).

## Building and checking

Every command runs in this directory; `cargo horizon-mod` fetches the pinned SDK into
`.horizon/sdk/` (gitignored, never packed) on first use.

```sh
CARGO_INCREMENTAL=0 cargo test                              # the pure runtime, 16 tests
CARGO_INCREMENTAL=0 cargo clippy --all-targets -- -D warnings
cargo fmt --check                                           # not --all: .horizon/sdk is a path dep
rm -f Cargo.lock                                            # else the lock is packed and changes the sha256
CARGO_INCREMENTAL=0 cargo horizon-mod build                 # -> target/horizon-mod/restrictions.hmod
cp target/horizon-mod/restrictions.hmod ./restrictions.hmod
cargo horizon-mod check restrictions.hmod
cargo horizon-mod check restrictions.hmod --uses
cargo horizon-mod fits restrictions.hmod --build nightly
```

The in-game scenario is `tools/e2e.sh`; it needs a game built by the launcher with this mod
installed (`horizon-launcher native-build … --trust-native-code`), which this environment does
not have — see `notes.md`.

## Licence

MIT. The original copyright and permission notices travel inside the package (`LICENSE`,
`LICENSE-NOTICE.md`). Local-only until the maintainer approves publishing.
