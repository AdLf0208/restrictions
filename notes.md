# Restrictions — port notes (slice 1, migrated to the SDK format)

Ported from **Restrictions 1.21-7.0.3** (`McJtyMods/Restrictions` @ `fbc351c0`, MIT) for
Minecraft Java 1.21.1 NeoForge. Clean-room Rust rewrite from the mod's behaviour; the upstream
analysis is [§History](#history-010-and-earlier) below. The port targets Horizon 26.3 at the
campaign pin.

**Licence: MIT (`license` in the jar's `neoforge.mods.toml`, MIT text in the repo's `LICENSE`,
© 2017 McJty) → rank 0, permissive.** Local-only until the maintainer approves publishing
(ARCHITECTURE.md §8); publishable under MIT with this source. `LICENSE` (upstream's own text) and
`LICENSE-NOTICE.md` (provenance) travel **inside** the `.hmod`.

**Format: the SDK package (2026-11-18).** This port was migrated from the retired `.hnmod`
container + embedded content archive to one flat `.hmod` — code, assets and data in the same
package. See [§Migration to the SDK format](#migration-to-the-sdk-format).
`src/runtime.rs` is **byte-identical** to the retired `mixins/restrictions/runtime.rs`
(sha256 `ab17fee28196747dfdaf94092e59a41c5d25e2b7e3c43219aee033a76b2ced35`), including the file
inside the built package.

**Version 0.2.0** supersedes PR **#877** (closed on 2026-11-18 by the `.hnmod` format purge); the
changelog is at the end of this file.

## Approach (from the pin's `docs/modpacks.md`)

- **Class `content`, tier `logic`**, core, P3 (`ports/_shared/source-map/atm10-sources.csv`,
  `ports/ledger.csv`). §"Classes" and the `logic` row of §"Tiers".
- **Carry-over + agent port.** The carry is the four blocks, the Glass Boots item, the creative
  tab, the recipes (with the `c:` tags they name), the loot tables, the advancements and two
  language files. The agent port is the block-entity tick that reads the facing and the strongest
  neighbour signal and pushes mobs. No `machines` shape: no menu, no tank, no synced BE data.
- **Harness:** `tools/e2e.sh`, a headless The End scenario with an unpowered control lane, a
  box-membership pair, a placement-facing leg and a counterfactual/selftest switch.

## What is implemented (slice 1)

- **Attractor** and **Pusher**: the cells in front of the block, `pos + facing*1 …
  pos + facing*signal` (its own cell excluded), where `signal` is the strongest neighbouring
  redstone signal (0 = off). Each server tick, every mob whose bounding box meets that run gets
  `Entity.push(facing × ∓0.1)`: **−0.1** blocks/tick for the attractor (toward the block) and
  **+0.1** for the pusher (away). An impulse added to the velocity, never a teleport; no
  line-of-sight test (upstream has none).
- The two movers own block entity types `restrictions:attractor` / `restrictions:pusher`, which
  tick on the server; the facing comes from the block's `facing` property and the level from the
  level in place.
- All four carried blocks (`attractor`, `pusher`, `oneway`, `oneway_wall`) take the placer's
  horizontal facing on placement, as McJtyLib's `BaseBlock` does.

## Hooks and parts (SDK)

| Moment | Shape | What the port does |
|---|---|---|
| `Hooks::register` | once, at startup | Declares `restrictions:attractor` (blocks: `restrictions:attractor`) and `restrictions:pusher`, attaches [`MoverPart`] to each, and [`Placement`] to all four carried blocks. |
| `BlockEntityPart::block_entity_ticks` | Part, server, listen | `event.ticks = true` for the mover's own block. |
| `BlockEntityPart::block_entity_tick` | Part, server, listen | Answers `BlockEntityTickReply::Unchanged` (the part writes no BE payload, so ticking alone must not dirty the chunk), then `support::on_tick`: read `facing`, read `LevelRef::best_neighbor_signal`, compute the run and push every mob whose box meets it. |
| `BlockPart::state_for_placement` | Part, server, replace | `Some(Some(state))` with `facing` = `runtime::facing_for_yaw(context.yaw)`, `None` for any other block. |
| `block_entity` (initial compound) | **not implemented** | A declared block entity type starts with an empty compound; the retired hook that answered `Some((block_id, Compound::new()))` has no job left. |

The decisions — which blocks are movers, the run, the impulse, the placement facing, box
intersection — are in `src/runtime.rs` and unit-tested there (13 tests). `src/lib.rs` declares and
wires the parts; `src/support.rs` reads the game and writes back, with no numbers of its own.

## Content

`assets/restrictions/` and `data/restrictions/`, `data/c/`, `data/minecraft/` — 53 files carried
from the release jar and hand-patched (see the retired carry report at
`ports/_shared/evidence/restrictions/retired-hnmod-0.1.0/content/`). In the SDK format the
content is **part of the same `.hmod`**, so the AE2 embedded-content pattern
(`content_root` injection, `.horizon-cache` write) is gone: one file installs the blocks and the
code.

The Attractor and Pusher still use the `minecraft:beacon` template (block entity, full cube) with
the six-way `facing` property, because the engine creates a block entity for a block whose
template has one; the mod-declared type now owns its identity (`restrictions:attractor`, not
`minecraft:beacon`), so the beacon's menu/beam is no longer this block's block entity. One Way
keeps `minecraft:glass`.

## Upstream defects fixed

1. **The volume AABB was memoised at the first powered tick** and never invalidated by a signal
   change or a rotation (`BaseTileEntity.java:42-53`), so raising the signal did not raise the
   range until the block entity was recreated. **The port recomputes the run every tick** —
   `runtime::volume` / `runtime::run_bounds`. A user notices that a signal change takes effect at
   once. (Worth an upstream report; not filed.)
2. **The force on players is applied twice** (server sweep + a client-only copy), which is how
   glass boots gate exactly the client half. The port moves mobs only (players are
   client-authoritative); see the gap list.

## Deviations (deliberate)

1. **Mobs only**, as in 0.1.0: the slice is filtered with `host.mob(entity)` so the behaviour is
   exactly the verified one. The SDK's host can move any non-player entity
   (`EntityRef::push`), so widening is a later slice, not this migration.
2. **Membership is the entity's box** (`EntityRef::bounding_box` + `runtime::boxes_meet`), with
   the feet-cell test as the fallback for kinds without a box (the ender dragon), as upstream
   intersects boxes.
3. **Placement** uses vanilla's yaw (`PlacementContext.yaw` → `runtime::facing_for_yaw`) rather
   than McJtyLib's two-block UP/DOWN special case: identical for ordinary placements, and the
   placer's height is not in `PlacementContext`.
4. **No fall-distance reset** for `facing=up`: no mob fall-distance write at the pin, so an
   upward lift can still deal fall damage.
5. **No `powered` sync and no client half**: the redstone level is read from the world each tick
   instead of being synced to a client copy (upstream syncs it only to feed the client-side player
   push, which this slice does not have).

## Gaps

- **One Way / One Way Wall have no behaviour.** Upstream's One Way is `noCollission()` and pushes
  on `entityInside`; Horizon's content format couples outline and collision, has no per-entity
  collision shape, and has no neutral no-collision template with a block entity. Both blocks are
  placed and carried, and `oneway` orients on placement, but neither moves anything.
- **Players** cannot be moved server-side: `EntityRef::push` refuses a player (its client moves
  it), and there is no player velocity or position write in the API. This is also why glass boots
  have no observable effect here.
- **Item entities and arrows/boats/orbs** are out of this slice's mob filter. The host can now
  move item entities (`LevelRef::all_entities` + `EntityRef::push`); a later slice should widen
  the filter and prove it in game.
- **Fall-distance reset** for `facing=up` (above).
- The **in-game e2e was not re-run** in this migration: it needs a game the launcher built with
  the mod (`horizon-launcher native-build …`), and `horizon-launcher` is not installed here. The
  0.1.0 run stands as the behaviour evidence for the identical scenario (see
  [§History](#history-010-and-earlier)); the transport changed, not the rules.

### To confirm in the next in-game run

`check`/`fits` prove the package is well formed and uses only stamped surface; they cannot prove
three things the game decides at load. The next `tools/e2e.sh` run must show all three, and they
are the first thing to look at if a lane stays still:

1. **A content-declared block can hold a mod block entity type.** `register` asks for
   `restrictions:attractor` / `restrictions:pusher` by id (`Registrar::block_key`) and declares the
   type on them; the blocks themselves come from `data/restrictions/horizon/block/*.json`
   (`minecraft:beacon` template, i.e. with `facts.block_entity`). If a mover placed by `setblock`
   has no block entity, the pull lane stays still and the registration was refused — read the
   game log for the mod's registration refusal.
2. **`host.dimension()` inside a block-entity tick is the level being ticked.** The tick resolves
   its level from it (`host.level(dimension)`), as the retired `native_dimension` did. A wrong
   level would show as a wrong `facing`/signal read, not as a missing block entity.
3. **`BlockEntityTickReply::Unchanged` does not suppress the tick's side effect.** The push is a
   host write, not block-entity payload, so it must survive the `Unchanged` reply; the push lanes
   are the assertion.

## Migration to the SDK format

*Written 2026-11-18 for this port (second migration after `imfast`). Pins: nightly
**`0b14f8acfd97fa2c750e42795249dcc981178ca4`**, mixins
**`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, launcher 0.2.78, `cargo-horizon-mod` from
`horizon-rust/horizon@main`.*

**Why.** Horizon's mod-API merge (#16941, launcher ≥ 0.2.70) retired `.hnmod`; the registry closed
every `.hnmod` submission on 2026-11-18 (this port's was PR **#877**). The new unit is **one flat
`.hmod`** — content, native code, or both.

### File map

| Path | What it is |
|---|---|
| `horizon-mod.toml` | the only manifest and the only identity (field map below) |
| `Cargo.toml` | one crate; its only dependency is `horizon-mod-api` from `.horizon/sdk/` |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks` (`register`) plus the parts |
| `src/runtime.rs` | the port's pure logic, **copied byte-for-byte** (`cp`, then `cmp`) |
| `src/support.rs` | the game glue: `state_for_placement`, `on_tick` (no numbers) |
| `assets/restrictions/**`, `data/{restrictions,c,minecraft}/**` | the carried content, 53 files |
| `LICENSE`, `LICENSE-NOTICE.md` | the licence travels inside the package |
| `icon.png` | optional, square, ≤512², ≤256 KiB — reused the published one |
| `.gitignore` | `/target`, `/.horizon`, `/Cargo.lock` |
| `tools/e2e.sh` | the in-game scenario, updated for a launcher-built game |

`src/runtime.rs` is a module, so `lib.rs` says `pub mod runtime;` — a private module turns every
`pub` item into a `dead_code` warning. `src/support.rs` is private (`mod support;`) and only
exposes `pub(crate)` functions.

### Deleted, and where the evidence went

Everything was moved to
`ports/_shared/evidence/restrictions/retired-hnmod-0.1.0/` **before the first build**:

| Deleted | Why |
|---|---|
| `mixins/restrictions/` (`horizon-mixin.toml`, `runtime.rs`, `support.rs`, `block_entity.rs`, `ticks.rs`, `tick.rs`, `state_for_placement.rs`, `embedded_content.rs`, `data/restrictions-content.hmod`) | the container is retired; `runtime.rs` moved to `src/` |
| `restrictions.hnmod` (22,409 B, `890a3e1a…`) | unloadable on launcher ≥ 0.2.70 |
| `compatibility.json`, `rust-toolchain.toml` | `[native]` in the manifest is the pin; the pinned build decides the toolchain |
| `tools/horizon.py`, `tools/package.py`, `tools/package.sh`, `tools/test_stage.py`, `tools/test_template.py`, `tools/notice.py`, `tools/audit/` | staging and `.hnmod` packaging are gone |
| `content/` (the content project: `horizon-mod.toml`, `assets/`, `data/`, `carry/`, `carry-report.json`, `check.json`, `README.md`, the built `restrictions.hmod`) | its `assets/`+`data/` are now the package's; the project folder is evidence of the carry |
| `Cargo.lock` | a registry-free mod must ship without one (trap 5) |
| `.github/workflows/ci.yml` | it runs the retired tooling |

The old root `README.md` was the **horizon-mixin template** README (it documented `mixins/`,
`tools/package.py` and `target/mixins/plan.json`); it was replaced with a port README. The retired
content README and carry report stay in the evidence folder.

### Manifest field map

| Old | New |
|---|---|
| `horizon-mixin.toml` `[mod] id = "restrictions"` | `horizon-mod.toml` `id = "restrictions"` |
| `[mod] version = "0.1.0"` | `version = "0.2.0"` (a resubmission is a new version) |
| `[mod] priority = 100` | gone; parts are attached by key, not ordered by a bundle priority |
| `[compatibility] horizon_revision = 1d63e0a…` | `[native] horizon = 0b14f8a…` |
| mixins `5a64af93…` (bundle) | `[native] mixins = e59da909…` — **it moved too** |
| game version | `[native] game = "26.3"` |
| `[[module]] runtime` + `[[module]] state` | `src/runtime.rs` + `src/support.rs`: ordinary Rust modules, no plan |
| `[[injection]] block_entity` / `block_entity_ticks` / `block_entity_tick` | `BlockEntityPart` methods on two declared types |
| `[[injection]] state_for_placement` | `BlockPart::state_for_placement` on all four blocks |
| `[[injection]] embedded-content` (`content_root`) | **gone**: content is in the package |
| `horizon-native.json` | gone (the manifest is the only one) |
| — | `api = "0.2"`, `side = "both"`, `capabilities = ["registries"]`, `license`, `homepage`, `issues` |

`side = "both"` because it is the **installation** side: an integrated server belongs to the
client installation, so a single-player world or a LAN host needs it (the hooks themselves are
server-side). `capabilities = ["registries"]` is the one value the schema allows; it is a schema
requirement, not a claim, and the port now really declares block entity types.

### The ladder for an SDK package

`build-slot.sh` speaks the retired `tools/horizon.py`, so **every step runs directly in the port**
with `CARGO_INCREMENTAL=0` — no staging, no staged tree, no `--target-dir`, no slot lease:

```sh
cd ports/restrictions
CARGO_INCREMENTAL=0 cargo test                              # 13 passed
CARGO_INCREMENTAL=0 cargo clippy --all-targets -- -D warnings
cargo fmt --check                                           # NOT --all (trap 4)
rm -f Cargo.lock                                            # trap 5
CARGO_INCREMENTAL=0 cargo horizon-mod build                 # fetches .horizon/sdk/ on first use
cp target/horizon-mod/restrictions.hmod ./restrictions.hmod
cargo horizon-mod check restrictions.hmod                   # EXIT 0
cargo horizon-mod check restrictions.hmod --uses
cargo horizon-mod fits restrictions.hmod --build nightly    # EXIT 0
sha256sum restrictions.hmod
```

### Traps this migration hit or inherited

1. **The old paths must go before the first build** — a leftover `mixins/` is refused
   (`unexpected package path: …`). Deleted into the evidence folder first.
2. **Both pins are 40 hex and neither is the last campaign pin**: `[native] mixins` is
   `e59da9094f0c…`, not the retired `5a64af93…`. A short hash reads as "native requires game and
   exact revisions".
3. **`cargo horizon-mod check` with no file checks wasm** (`can't find crate for 'core'`); use
   `check <file.hmod>` for the package and `cargo test` for the native build.
4. **`cargo fmt --all --check` reports the fetched SDK's own files**; use `cargo fmt --check` and
   never "fix" `.horizon/sdk`.
5. **A packed `Cargo.lock` changes the artifact** and resolves newer crates than the SDK's own
   lock; `rm -f Cargo.lock` right before the build, `/Cargo.lock` in `.gitignore`.
6. **`side` is the installation side** (see above).
7. **`capabilities = ["registries"]` is mandatory** even for a mod that declares nothing.
8. **`runtime.rs` must be `pub mod`**, or every `pub` item warns `dead_code`.
9. **`Hooks`/Parts are `Any + Send + Sync`**; session state would need a `Mutex` (this port keeps
   no state).
10. **A Part is the right shape here, not a global hook.** `block_entity*` and
    `state_for_placement` are Part methods in the SDK: they must be attached in
    `Hooks::register` with `r.block_entity_part` / `r.block_part`, and each impl needs
    `#[mod_api::horizon_part]` (which derives the subscription lists). Looking for
    `Hooks::block_entity` compiles into nothing.
11. **Handle methods take the host.** `LevelRef::block_state(host, pos)`,
    `LevelRef::best_neighbor_signal(host, pos)`, `LevelRef::all_entities(host)`,
    `EntityRef::bounding_box(host)`, `EntityRef::position(host)`, `EntityRef::push(host, delta)` —
    the `entity_*`/`level_*` methods on the host traits are the backend contract, not the mod API.
    Passing `&*host` upcasts `&dyn ServerHost` to `&dyn Host`.
12. **`host.block_states()` needs `HostBlockStates` in scope** (a blanket extension trait, not a
    supertrait of `Host`), and its returned metadata must outlive the `&str` property you read:
    bind it in a block.
13. **`BlockEntityTickReply::Unchanged`** is the honest answer for a part that writes no payload:
    the default `Changed` dirties the chunk every tick.
14. **The content is in the package now**, so `tools/e2e.sh` passes no `--dev-mod` and there is no
    `.horizon-cache` content copy to compare; the script's `CTL`/`GAME` must both come from the
    launcher-built game's build.
15. **The e2e could not be re-run here** — `horizon-launcher` is not installed, and a port-built
    `target/horizon-cargo/fast/horizon-client` no longer exists (that was the retired staging
    ladder's output). `tools/e2e.sh` keeps the scenario and its assertions, now requiring `GAME=`
    and `CTL=` for a launcher-built game.

## Verification

Skills: superpowers/using-superpowers, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

| Check | Command | Result |
|---|---|---|
| Runtime unit tests (SDK crate) | `CARGO_INCREMENTAL=0 cargo test` | **13 passed**, 0 failed (`evidence/restrictions/sdk-test.log`) |
| Lints | `cargo clippy --all-targets -- -D warnings` | exit 0, 0 warnings (`evidence/restrictions/sdk-clippy.log`) |
| Formatting | `cargo fmt --check` | clean (`evidence/restrictions/sdk-fmt.log`) |
| Package | `cargo horizon-mod build` | `target/horizon-mod/restrictions.hmod`, EXIT 0 (`evidence/restrictions/sdk-build.log`) |
| Determinism | rebuild after `rm -rf target/horizon-mod Cargo.lock` | same size and sha256 |
| Registry check | `cargo horizon-mod check restrictions.hmod` | `restrictions 0.2.0 (native-mod, format native-1/0b14f8a/e59da90, for 26.3)`, **35,935 B**, sha256 `657dda40…8addc`, **EXIT 0** (`evidence/restrictions/sdk-check.log`) |
| What it uses | `cargo horizon-mod check restrictions.hmod --uses` | 139 surface entries (`evidence/restrictions/sdk-uses.json`), EXIT 0 |
| Fits the pinned build | `cargo horizon-mod fits restrictions.hmod --build nightly` | `0b14f8a  made for`, EXIT 0 (`evidence/restrictions/sdk-fits.log`) |
| `runtime.rs` untouched | `unzip -p restrictions.hmod src/runtime.rs \| sha256sum` | `ab17fee2…ed35` = the retired file, byte for byte |
| Package contents | `unzip -l restrictions.hmod` | 63 entries: manifest, `Cargo.toml`, `LICENSE`, `LICENSE-NOTICE.md`, `README.md`, `icon.png`, `src/{lib,runtime,support}.rs`, `uses.json`, 53 content files |
| `Skills:` line | `python3 ports/tools/check-skills.py --notes ports/restrictions` | see the line above |

### Not re-run in this migration

- **The in-game e2e** (trap 15). The 0.1.0 run stands as the behaviour evidence for the same
  scenario: what changed is the transport of the same tick (a declared block entity type and Parts
  instead of an injected helper), not the rules, which are byte-identical and tested.
- **The staged ladder** (`tools/horizon.py stage/check/test/build`) — deleted with the format.

## History (0.1.0 and earlier)

### Upstream provenance

| | |
|---|---|
| Repo | <https://github.com/McJtyMods/Restrictions> |
| Branch / commit | `1.21_neo` @ `fbc351c028414249c1d52e2daed4471fba993c48` |
| Version | `1.21-7.0.3` (`gradle.properties:6`) |
| Release equivalence | the four blocks, generated assets and lang are byte-identical to the 7.0.3 release commit `0aac647` |
| Library | McJtyLib `1.21_neo` @ `ef393e60…` (`1.21-9.0.22`) |
| Jar | `ports/_shared/licence-cache/restrictions-1.21-7.0.3.jar`; carry at `ports/_shared/carry-work/restrictions/` |

Files read: `setup/Registration.java`; `blocks/BaseTileEntity.java`, `AttractorTileEntity.java`,
`PusherTileEntity.java`, `OneWayBlock.java`, `OneWayWall.java`; `items/GlassBoots.java` (scope);
`datagen/DataGenerators.java`; `src/generated/resources/**`;
`src/main/resources/assets/restrictions/lang/en_us.json`, `models/item/*.json`,
`META-INF/neoforge.mods.toml`, `changelog.txt`. McJtyLib: `blocks/BaseBlock.java`,
`tileentity/GenericTileEntity.java`, `tileentity/TickingTileEntity.java`,
`varia/OrientationTools.java`.

Behaviour extracted:

| Block | Volume / trigger | Effect | Evidence |
|---|---|---|---|
| `restrictions:attractor` | front cells `pos+facing*1 … pos+facing*s`, `s` = strongest neighbour signal 0..15; **off at 0**, never its own cell, no occlusion check | adds `facing * -0.1` to every entity's velocity, every tick | `BaseTileEntity.java:42-53, 65-78`; `AttractorTileEntity.java:17` |
| `restrictions:pusher` | same volume and signal | adds `facing * +0.1` | `BaseTileEntity.java:70-77`; `PusherTileEntity.java:18` |
| `restrictions:oneway` | no signal, no BE; the block's own cell, on `entityInside` | adds `facing * +0.2` to every entity (no collision, pathfindable, light passes) | `OneWayBlock.java:25-68` |
| `restrictions:oneway_wall` | no signal, no BE; per-entity collision | blocks motion along `facing`, passes the reverse | `OneWayWall.java:41-83, 92-95` |
| `restrictions:glassboots` | leather FEET armour | player-only: suppresses the client-side push and the wall's collision | `GlassBoots.java:33-35` |

Shared facts: all four blocks use vanilla's six-way `facing` only; `strength(2.0)`; `METAL` sound
for the movers, `GLASS` for the One Way pair; stone-pickaxe datagen tags. Placement faces the
placer. No config, no NBT beyond one `powered` byte, no GUI, no packets, no event listeners.

### The 0.1.0 in-game run (evidence for the unchanged scenario)

`tools/e2e.sh`, The End at the feet plane y=65, AI cows on 1×1 pillars over a void, `NoAI` only to
hold them before power-on:

```
before: PullMe=3.5 Control=3.5 PushMe=3.5 Outside=20.5 Below=3.5 Under=3.5
after:  PullMe=1.449999988079071 Control=3.5..3.5 PushMe=11.550048828125 Outside=20.5..20.5
box:    Below=0.68994140625..3.5 Under=3.5..3.5
PASS: powered attractor pulled, unpowered stayed, pusher pushed away, outside control stayed;
      the box test pulled the cow one block below the run and left the one two blocks below;
      placement facings kept and the placed facing drove the pull
E2E EXIT:0
```

`COUNTERFACTUAL=1` (same pillar, same cow, no redstone block) leaves the pull window at 3.5
exactly; `SELFTEST=1` inverts the pull assertion and fails (`EXIT:1`); `NEGATIVE=1` writes
`facing=north` instead of placing and fails the push assertion. Logs:
`ports/_shared/evidence/restrictions/e2e-embedded.log`, `e2e-selftest.log`.

Harness facts that cost runs and are still true: `NoAI:1b` freezes a mob completely (no gravity, no
velocity integration), so movement lanes need an AI cow released with `{NoAI:0b}` after the power
is on; idle AI cows stroll, so pillars stand over a void; `ctl entities` carries no names;
`ctl setblock` acts in the player's current dimension, so every write goes through
`execute in minecraft:the_end run …`.

### Earlier slices (for the reader of the old tree)

- **83ad384f re-pin** replaced the exact feet-cell test with upstream's bounding-box intersection
  and added the `Below`/`Under` lanes.
- **1d63e0a5 one-file bundle** embedded the built content `.hmod` inside the `.hnmod` (AE2
  pattern) so one registry file installed both halves. That pattern is retired with `.hnmod`.
- **PR #629 review repairs**: the authors list names McJty (the org name had been there, not the
  author), the archive carries the MIT notice, the "feet cell only" description was corrected, and
  the port's `LICENSE` reproduces upstream's `Copyright (c) 2017` line verbatim.

## Files

- `horizon-mod.toml` — the only manifest: `id`, `version = "0.2.0"`, `api = "0.2"`,
  `side = "both"`, `[native]` pinned to `0b14f8a` / `e59da90`.
- `Cargo.toml` — one crate; the only dependency is `horizon-mod-api` from `.horizon/sdk/`.
- `src/lib.rs` — `register` (two block entity types, four block parts) and the two parts.
- `src/runtime.rs` — the pure decision, byte-identical to the pre-migration file, 13 tests.
- `src/support.rs` — the game glue.
- `assets/`, `data/` — the carried content.
- `LICENSE`, `LICENSE-NOTICE.md`, `icon.png`, `README.md` — inside the package.
- `tools/e2e.sh` — the in-game scenario (needs a launcher-built game).
- `restrictions.hmod` — the delivered package, 35,935 B, sha256
  `657dda40a99c20bc8b898246f6662def6107113cb9ba7fdc4ae9813e5ea8addc`.
- `VALIDATION.md`, `REPIN-AUDIT.md` — earlier ladders (retired tooling, kept as history).
- Evidence: `../_shared/evidence/restrictions/` (`sdk-*.log`, `sdk-uses.json`, `sdk-sha256.txt`,
  the 0.1.0 e2e logs, and the retired tree under `retired-hnmod-0.1.0/`).

## Changelog 0.2.0 — supersedes #877

> **0.2.0** republishes this mod as a **native `.hmod`** built with the Horizon mod SDK (nightly
> `0b14f8a`, `api = "0.2"`), after the registry closed #877 with the 2026-11-18 `.hnmod` format
> purge. It is the same port, not a rewrite: `src/runtime.rs` is byte-identical to 0.1.0, the same
> Attractor/Pusher behaviour and the same 53 carried files. What changed is the package: the blocks,
> models, textures, language, recipes, loot and advancements now travel **inside the same `.hmod`**
> as the code (no embedded content archive, no `--dev-mod`), the two movers declare their own block
> entity types (`restrictions:attractor`, `restrictions:pusher`) instead of borrowing the beacon
> template's, placement keeps the placer's facing through a block part, and a mover's tick no
> longer dirties the chunk (it writes no block-entity payload). Not yet ported, unchanged: One Way
> and One Way Wall (no per-entity collision shape at the pin), players and item entities (mob-only
> slice), and the upward fall-distance reset.
