# restrictions (Horizon port)

A Horizon port of [restrictions](McJtyMods/Restrictions) — MIT.

**Status: first slices.** What is below is what the port actually does today.

## Implemented so far

- Attractor/Pusher**: the cells in front of the block, `pos + facing*1 …
- pos + facing*signal` (its own cell excluded), where `signal` is the strongest
- neighbouring redstone signal (0 = off). Each server tick every mob whose feet
- are in one of those cells gets a velocity impulse along the facing:
- −0.1** blocks/tick for the attractor (toward the block) and **+0.1** for the
- pusher (away). No line-of-sight test (upstream has none).
- The block entity is created by the `block_entity` hook and ticks via
- `block_entity_ticks`; the facing is read from the block's `facing` property.

## Not yet ported

- One Way / One Way Wall**: upstream One Way is `noCollission()` and applies
- its push on `entityInside`; Horizon's content format couples outline and
- collision and has no per-entity collision shape, and no neutral no-collision
- template with a block entity. Deferred to an engine API (outline/collision
- split or a BE-capable no-collision template).
- Players and item entities** cannot be moved at the pin (no player velocity/
- position write; item entities have no position setter). Mobs only.
- Arrows/boats/orbs/wall variants are out of scope; McJtyLib's 2-block placement

## Install

Build the bundle with a native-mod capable launcher, or add the file from the
registry once it is listed. Pinned to Horizon `1d63e0a` and horizon-mixins
`5a64af93` for game 26.3.

## Build from source

```sh
cargo test
python3 tools/horizon.py check --horizon <horizon checkout>
python3 tools/horizon.py build --horizon <horizon checkout>
python3 tools/package.py
```

## Credits and licence

Original mod: McJtyMods/Restrictions. Port: AdLf0208. Licence: MIT — see [LICENSE](LICENSE);
the original notices are preserved.
