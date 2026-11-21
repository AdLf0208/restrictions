# Restrictions — port notes (slice 2: every entity, not only mobs)

Ported from **Restrictions 1.21-7.0.3** (`McJtyMods/Restrictions` @ `fbc351c0`, MIT) for
Minecraft Java 1.21.1 NeoForge. Clean-room Rust rewrite from the mod's behaviour; the upstream
analysis is [§History](#history-010-and-earlier) below. The port targets Horizon 26.3 at the
campaign pin.

**Licence: MIT (`license` in the jar's `neoforge.mods.toml`, MIT text in the repo's `LICENSE`,
© 2017 McJty) → rank 0, permissive.** Local-only until the maintainer approves publishing
(ARCHITECTURE.md §8); publishable under MIT with this source. `LICENSE` (upstream's own text) and
`LICENSE-NOTICE.md` (provenance) travel **inside** the `.hmod`.

**Format: the SDK package (2026-11-18).** This port is one flat `.hmod` — code, assets and data in
the same package. See [§Migration to the SDK format](#migration-to-the-sdk-format).

**Version 0.2.3** is slice 2 ([§Slice 2](#slice-2--the-sweep-is-every-entity-not-only-mobs)): the
Attractor and Pusher move **every** entity in their run, not only mobs, at the campaign pin
`0a875da`, and the two movers' loot tables lose a component that cannot exist at 26.3. It follows
0.2.1 (PR #1181 review fixes) and supersedes PR **#877** (closed on 2026-11-18 by the `.hnmod`
format purge); the changelog is at the end of this file.

## Slice 2 — the sweep is every entity, not only mobs

**The gap it closes** (`notes.md` 0.2.1 §Gaps, item 3, verbatim):

> **Item entities and arrows/boats/orbs** are out of this slice's mob filter. The host can now
> move item entities (`LevelRef::all_entities` + `EntityRef::push`); a later slice should widen
> the filter and prove it in game.

Upstream sweeps **every `Entity`**: `getEntitiesOfClass(Entity.class, …)` at
`BaseTileEntity.java:70` "includes items, arrows, boats, minecarts, TNT, orbs"
(`ports/_shared/upstream/restrictions/FINDINGS.md:97-99`). 0.1.0/0.2.x filtered with
`host.mob(entity)` because the retired hook could move only mobs; the pin's `EntityRef::push`
moves any simulated non-player entity, so the filter had become a fidelity defect. The tier is
unchanged (`logic`): the same tick, run, impulse and budget — only the sweep's eligibility moves.

**The red (before the fix), verbatim.** The new e2e phase run against the **delivered 0.2.1
package, no rebuild** (`~/.cache/horizon-e2e/0b14f8a/restrictions`, log
`evidence/restrictions-e2e/e2e-red-0.2.1.log`):

```
before: ItemMe=3.5 ItemControl=3.5 OrbMe=5.5 OrbControl=5.4964434695464
sweep:  ItemMe=3.5..3.5 ItemControl=3.5..3.5
sweep:  OrbMe=5.5..5.5 OrbControl=5.496434181463228..5.49755859375
FAIL: the powered attractor did not pull the dropped item (before=3.5 min=3.5)
EXIT:1
```

The unit test was written first and failed to compile, which is the red for the pure rule:

```
error[E0425]: cannot find function `sweeps` in this scope
   --> src/runtime.rs:301:18
error[E0425]: cannot find value `ENTITIES_PER_CELL` in this scope
   --> src/runtime.rs:312:40
```

**The change.**

- `runtime::sweeps(id, players) -> bool` — the sweep's one exclusion: a player. Everything else
  whose box meets the run is pushed: a dropped stack, an arrow, a boat, an experience orb, a mob.
  A skipped player spends none of the budget, and a later API that could move a player must not
  make this port do so by accident.
- `MOBS_PER_CELL` → `ENTITIES_PER_CELL` (the same four per powered cell now covers every kind);
  `push_budget` is unchanged in behaviour.
- `support::on_tick` reads `host.players().server_players()` once per mover tick, drops the
  `host.mob` filter, and counts only a push the host **accepted** (`EntityRef::push` returns
  false for a player or a kind it does not simulate), so a refused candidate never starves the
  entities behind it.
- Tests: `a_mover_sweeps_every_entity_except_a_player`,
  `dropped_items_and_mobs_share_the_run_s_budget` (13 → 16 tests with the renamed budget test).

**The green (in game, 0.2.3 at `0a875da`).** Two movers side by side in The End, one powered
(z=-6) and one unpowered (z=-8), each with a dropped cobblestone and an experience orb in its run
on a y=64 floor so both boxes sit on the y=65 run plane:

```
before: ItemMe=3.5 ItemControl=3.5 OrbMe=5.5 OrbControl=5.5
sweep:  ItemMe=1.125..3.5 ItemControl=3.5..3.5
sweep:  OrbMe=1.25..5.5 OrbControl=5.5..5.5
PASS: the sweep moved a dropped item and an experience orb while the unpowered control stayed; …
EXIT:0
```

The same scenario on the **same Nightly without the package** fails at the item assertion
(`FAIL: the powered attractor did not pull the dropped item (before=3.5 min=3.5)`, `EXIT:1`), and
`SELFTEST=1` — which inverts the item assertion — fails with
`FAIL: selftest: the item in the powered run is asserted not to move (before=3.5 min=1.125)`,
`EXIT:1`. Logs: `evidence/restrictions-e2e/e2e-launcher-0.2.3{,-control,-selftest,-selftest-recipe}.log`.

## Recipes are crafted in game (parity rule, 2026-11-20)

Every carried recipe is crafted from the data **inside the delivered package** by
`tools/craft_recipes.py`: it reads `data/restrictions/recipe/*.json` out of the `.hmod`, lays each
declared pattern (spaces included, as vanilla matches a shaped recipe) in a real crafting table,
and asserts the result id and count, that every ingredient was consumed and that the grid is
empty. A `#tag` ingredient is resolved by one table of concrete vanilla items; an unknown tag
fails the run instead of being skipped. All five craft (attractor, pusher, oneway, oneway_wall,
glassboots), each with `count: 1`.

The phase is its own `--offscreen` launch: **a headless client never opens a crafting-table
menu** (measured here — `ctl interact` clicks the table and the screen stays `inventory`, and
`ctl screen` then times out; the same note is in `ports/pocketstorage/tools/e2e.sh:106-108`).
`SELFTEST=recipe` makes the first recipe expect the second's result and must fail:
`FAIL: attractor.json: expected 1 restrictions:glassboots, got {'count': 1, 'item':
'restrictions:attractor', 'slot': 200}` + `EXIT:1`
(`evidence/restrictions-e2e/e2e-launcher-0.2.3-selftest-recipe.log`).

## Approach (from the pin's `docs/modpacks.md`)

- **Class `content`, tier `logic`**, core, P3 (`ports/_shared/source-map/atm10-sources.csv`,
  `ports/ledger.csv`). §"Classes" and the `logic` row of §"Tiers".
- **Carry-over + agent port.** The carry is the four blocks, the Glass Boots item, the creative
  tab, the recipes (with the `c:` tags they name), the loot tables, the advancements and two
  language files. The agent port is the block-entity tick that reads the facing and the strongest
  neighbour signal and pushes mobs. No `machines` shape: no menu, no tank, no synced BE data.
- **Harness:** `tools/e2e.sh`, a headless The End scenario with an unpowered control lane, a
  box-membership pair, a placement-facing leg and a counterfactual/selftest switch.

## What is implemented (slice 1: the movers; slice 2: their sweep)

- **Attractor** and **Pusher**: the cells in front of the block, `pos + facing*1 …
  pos + facing*signal` (its own cell excluded), where `signal` is the strongest neighbouring
  redstone signal (0 = off). Each server tick, every entity whose bounding box meets that run
  gets `Entity.push(facing × ∓0.1)`: **−0.1** blocks/tick for the attractor (toward the block)
  and **+0.1** for the pusher (away). An impulse added to the velocity, never a teleport; no
  line-of-sight test (upstream has none). Since slice 2 "every entity" is literally that: mobs,
  dropped stacks, arrows, boats and experience orbs ([§Slice 2](#slice-2--the-sweep-is-every-entity-not-only-mobs)).
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
| `BlockEntityPart::block_entity_tick` | Part, server, listen | Answers `BlockEntityTickReply::Unchanged` (the part writes no BE payload, so ticking alone must not dirty the chunk), then `support::on_tick`: read `facing`, read `LevelRef::best_neighbor_signal`, compute the run, read the level's players once (`server_players`), and push every entity whose box meets the run and is not a player. |
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

3. **The two movers' loot tables named `mcjtylib:item_energy`** (`loot_table/blocks/attractor.json`
   and `pusher.json`: a `minecraft:copy_components` modifier with
   `include: ["mcjtylib:item_energy", "minecraft:container"]`, generated by McJtyLib's block
   template). That component belongs to McJtyLib, which is not part of this package and does not
   exist at 26.3, so a real break copied nothing and **the block dropped nothing at all** —
   measured: a stone-pickaxe break left `block=minecraft:air` and zero items, while
   `loot give @s loot restrictions:blocks/attractor` (no block entity in the context) gave exactly
   one. The port **drops the modifier** from both tables, matching the two glass blocks' tables
   (which never had it); a break now drops one of the block with a pickaxe and one by hand, which
   the e2e asserts. A user notices that a broken Attractor/Pusher can be picked up again. Worth an
   upstream report; not filed.

## Deviations (deliberate)

1. ~~**Mobs only**~~ — **closed by slice 2 (0.2.2).** 0.1.0–0.2.1 filtered with
   `host.mob(entity)`; the sweep now covers every entity the host can push
   (`runtime::sweeps`), proven in game with a dropped item and an experience orb.
2. **Membership is the entity's box** (`EntityRef::bounding_box` + `runtime::boxes_meet`), with
   the feet-cell test as the fallback for kinds without a box (the ender dragon), as upstream
   intersects boxes.
3. **Placement** uses vanilla's yaw (`PlacementContext.yaw` → `runtime::facing_for_yaw`) rather
   than McJtyLib's two-block UP/DOWN special case: identical for ordinary placements, and the
   placer's height is not in `PlacementContext`.
4. **No fall-distance reset** for `facing=up` yet: the pin now has
   `ServerHost::entity_reset_fall_distance` (so the 0.1.0 "no write at the pin" note is stale),
   but this slice does not use it — an upward lift can still deal fall damage until the next one.
5. **No `powered` sync and no client half**: the redstone level is read from the world each tick
   instead of being synced to a client copy (upstream syncs it only to feed the client-side player
   push, which this slice does not have).

## Gaps

- **One Way / One Way Wall have no behaviour.** Upstream's One Way is `noCollission()` and pushes
  on `entityInside`, and the pin **does** have the hook (`BlockPart::entity_inside` with
  `EntityWrite::Push`), but it only fires for an entity inside a block it already collides with:
  the SDK's own note says the `getEntityInsideCollisionShape` that decides "inside" is not exposed
  (`horizon-mod-vocab/src/hooks/notes.rs`, tracked upstream as #44), and `glassential` measured the
  consequence at this pin (`entity_inside` fires only inside a block the entity collides with).
  A no-collision content block therefore never fires it, and a solid one cannot be entered — the
  upstream mechanic cannot be expressed. Both blocks are placed and carried, and `oneway` orients
  on placement, but neither moves anything. One Way Wall is further blocked: its collision shape
  depends on the entity's velocity, and no per-entity collision shape exists.
- **Players** cannot be moved server-side: `EntityRef::push` refuses a player (its client moves
  it), and there is no player velocity or position write in the API. This is also why glass boots
  have no observable effect here. The sweep now skips a player explicitly and by test
  (`runtime::sweeps`), so the budget stays for what can move.
- ~~**Item entities and arrows/boats/orbs** are out of this slice's mob filter.~~ **Closed by
  slice 2 (0.2.2)**: `EntityRef::push` moves them, `runtime::sweeps` includes them, and the e2e
  proves a dropped stack and an experience orb are pulled while an unpowered control stays.
- **Fall-distance reset** for `facing=up` (above). **Now implementable**: the pin has
  `ServerHost::entity_reset_fall_distance(entity)` (the 0.1.0 note "no mob fall-distance write"
  is stale), and upstream forces `fallDistance = 1.0` while a lifted entity's vertical velocity is
  above −0.5 (`BaseTileEntity.java:73-75`). This is the next slice.
- The **in-game e2e was not re-run** in this migration: it needs a game the launcher built with
  the mod (`horizon-launcher native-build …`), and `horizon-launcher` is not installed here. The
  0.1.0 run stands as the behaviour evidence for the identical scenario (see
  [§History](#history-010-and-earlier)); the transport changed, not the rules.

### Coverage (parity rule, 2026-11-20)

Every family the package ships, and where it is proven. `tested` names the e2e phase/assertion;
the log is `evidence/restrictions-e2e/e2e-launcher-0.2.3.log` unless another is named.

| Family (from the jar) | State | Proof |
|---|---|---|
| Attractor pull (run = `signal` cells, ±0.1/tick, off at 0) | tested | `sweep` phase (item + orb pulled west), `PullMe` cow lane (`1.503` from `3.5`) |
| Pusher push (opposite sign) | tested | `PushMe` cow lane (`11.55` from `3.5`) |
| Unpowered control (signal 0 does nothing) | tested | `ItemControl`/`OrbControl`/`Control`/`Outside` lanes stay inside ±0.2 |
| Box membership (upstream's AABB, not a feet cell) | tested | `Below` (feet one block down) pulled, `Under` (two down) still |
| Placement facing = toward the placer | tested | four `place_at` placements read back with the wanted `facing`, and the placed facing drives a pull |
| The sweep covers every entity, not only mobs | tested | `sweep` phase: a dropped item and an experience orb move in the powered run and stay in the unpowered one; `SELFTEST=1` inverts it (FAIL + EXIT:1) |
| All four carried blocks place and read back | tested | `blocks` phase: `oneway[facing=up]` and `oneway_wall[facing=south]` read back, the movers placed throughout |
| Unknown content id is refused | tested | `setblock … restrictions:no_such_block` answers `Unknown block type 'restrictions:no_such_block'` (the parsed reply) |
| The loot tables (four blocks) | tested | `blocks` phase: pickaxe break → 1, bare-hand break → 1 (requiring `requires_tool: false`), vanilla stone → 1 `minecraft:cobblestone` |
| Every carried recipe (5 shaped) | tested | `tools/craft_recipes.py` reads them out of the delivered `.hmod` and crafts each in a table: id + count, ingredients consumed, grid empty; `SELFTEST=recipe` inverts the first (FAIL + EXIT:1) |
| `#minecraft:mineable/pickaxe` (the blocks' tool class) | tested | the pickaxe breaks them (the `blocks` phase); a hand break is slower but still completes |
| `#minecraft:needs_stone_tool` (stone tier) | blocked(no tier gate at the pin) | measured: a **wooden** pickaxe drops the block too. The break path reads only `facts.requires_tool` + `correct_for_drops` (`horizon/crates/horizon-client/src/game.rs:5834,5847`); nothing reads `needs_stone_tool`, so content cannot enforce the tier |
| One Way: `entityInside` push of +0.2 along the facing | blocked(`entity_inside` needs a block the entity collides with) | the hook exists (`BlockPart::entity_inside`, `EntityWrite::Push`), but the SDK says the `getEntityInsideCollisionShape` that decides "inside" is not exposed (hooks/notes.rs, upstream #44) and `glassential` measured it at this pin; a no-collision content block never fires it |
| One Way Wall: per-entity collision along `facing` | blocked(no per-entity collision shape) | no API; the block is carried and inert |
| Glass Boots: player immunity to the push | not ported | the push a player feels is the client half; a player cannot be moved server-side (see Gaps), so the boots have no observable effect here |
| Advancements, lang, models, blockstates, item models | tested | the items exist and render (the craft phase reads them back by id); the advancement fires on the first craft (`Player… has made the advancement [Stone Age]` is vanilla's; the mod's own are carried data) |

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

## Review fixes (2026-11-18)

The reviewer's source review of PR #1181 (`var/review-all/1181-restrictions.md`) left one finding;
it is fixed in **0.2.1** (`36548 B`, sha256 `8b0a40025b49341cea7e8310f9abc1b2b821a0330f6beb4d0709f88ecbef8dc4`).

- **`src/support.rs:61` — every powered mover enumerated the level's whole entity population and
  resolved a mob handle for each entity before testing its local ray.** A mover now asks the level
  for the entities whose box meets its powered run (`LevelRef::entities_in` over `run_bounds`), so
  the engine's single entity-list walk is filtered by the run and `host.mob` is resolved only for
  the overlapping handful; the pushes are additionally capped by
  `runtime::push_budget` (four mobs per powered cell, zero when the signal is off), so one mover's
  work per tick is bounded by its own run. Test:
  `runtime::tests::a_mover_pushes_at_most_its_run_s_budget_of_mobs`.

**In-game leg:** `ports/tools/launcher-game.sh run restrictions` → `PASS` + `E2E EXIT:0`, control
`FAIL: the powered attractor did not pull the cow` + `EXIT:1`, recorded in
`ports/_shared/evidence/restrictions-e2e/`.

## Verification (0.2.3, slice 2)

Skills: superpowers/using-superpowers, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

Package: `restrictions.hmod` **37,954 B**, sha256
`895d8b2058dce2588d7582aebaa81f4d952d42ca4d41899f7ee68a4d88f40e4e`, version **0.2.3**, format
`native-1/0a875da91dbb0fdcb7ba8c42c11341aa229af51a/e59da9094f0c2fdda6c627fe9eff22dec6a906f0`,
63 entries, **no packed `Cargo.lock`**. Every log below prints this sha and size in its first line.

| Check | Command | Result |
|---|---|---|
| Runtime unit tests (SDK crate) | `CARGO_INCREMENTAL=0 cargo test` | **16 passed**, 0 failed (`evidence/restrictions/sdk-test.log`) |
| Lints | `cargo clippy --all-targets -- -D warnings` | exit 0, 0 warnings (`evidence/restrictions/sdk-clippy.log`) |
| Formatting | `cargo fmt --check` | clean (`evidence/restrictions/sdk-fmt.log`) |
| Package | `cargo horizon-mod build` ×2, `rm -f Cargo.lock` before each | 37,954 B both times, `cmp` byte-identical (`evidence/restrictions/sdk-build.log`) |
| Registry check | `cargo horizon-mod check restrictions.hmod` | `restrictions 0.2.3 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 37,954 B, EXIT 0 (`evidence/restrictions/sdk-check.log`) |
| Fits the pinned build | `cargo horizon-mod fits restrictions.hmod --build 0a875da` | `0a875da  made for`, EXIT 0 (`evidence/restrictions/sdk-fits.log`) |
| Fits a different build | `cargo horizon-mod fits restrictions.hmod --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 (`evidence/restrictions/sdk-fits-other.log`) |
| Package contents | `unzip -l restrictions.hmod` | 63 entries: manifest, `Cargo.toml`, `LICENSE`, `LICENSE-NOTICE.md`, `README.md`, `icon.png`, `src/{lib,runtime,support}.rs`, `uses.json`, 53 content files; no `Cargo.lock` |
| In-game leg (package) | `tools/e2e.sh` on the launcher-built game | `PASS` + `EXIT:0` (`evidence/restrictions-e2e/e2e-launcher-0.2.3.log`) |
| In-game leg (control, same Nightly, no package) | `GAME=$CONTROL_GAME tools/e2e.sh` | `FAIL: the powered attractor did not pull the dropped item` + `EXIT:1` (`…-0.2.3-control.log`) |
| In-game leg (sweep selftest) | `SELFTEST=1 tools/e2e.sh` | `FAIL: selftest: the item in the powered run is asserted not to move` + `EXIT:1` (`…-0.2.3-selftest.log`) |
| In-game leg (recipe selftest) | `SELFTEST=recipe tools/e2e.sh` | `FAIL: attractor.json: expected 1 restrictions:glassboots` + `EXIT:1` (`…-0.2.3-selftest-recipe.log`) |
| Exit-status audit | `python3 ports/tools/check-e2e-logs.py restrictions-e2e --strict` | `logs=5 ok=5 missing-exit=0 bad-exit=0`, exit 0 |
| Red proof (before the fix) | the sweep phase against the delivered **0.2.1** package (no rebuild) | `FAIL: the powered attractor did not pull the dropped item (before=3.5 min=3.5)` + `EXIT:1` (`…/e2e-red-0.2.1.log`) |
| `Skills:` line | `python3 ports/tools/check-skills.py --notes ports/restrictions` | the line above |
| Package gate | `python3 ports/tools/verify-sdk-package.py restrictions` | 1/1 |

### Harness facts this slice cost (still true)

- **An experience orb has no `id`** in `ctl entities` (mobs and items do), so an orb lane is
  tracked by the orb nearest its lane's `z`; the type filter needs the full id
  (`minecraft:experience_orb`) and the JSON `kind` is `orb`, `item`, `mob`.
- **`ctl screen` hangs headless and a headless client never opens a crafting-table menu**: the
  recipe phase is a second `--offscreen` launch (the `pocketstorage` pattern). `ctl menu` answers
  the occupied slots, not a grid.
- **`ctl break` respawns the drop where the player may already have picked it up**: assert
  "produced one" by counting the ground *or* the inventory, never one of them.
- **Vanilla stone drops `minecraft:cobblestone`**, so it is the differential for a loot readout.
- **A 7-block catch pit kills a cow** (it is then missing and the next lane's nearest-cow lookup
  aliases another animal): the catch floors are at y=62 now, and `cow_at` is **strict** (within
  1.5 blocks of the lane's z) so a missing cow fails loudly instead of passing against the wrong
  one.
- **The Under lane needs a shaft**: an idle AI cow on a bare 1x1 pillar has strolled off it.

### Not run in the 0.2.0 migration (closed by 0.2.3)

- **The in-game e2e** was not run in the 0.2.0 migration (no launcher on the box then). It **has**
  been run for 0.2.1/0.2.2 and again, with the whole parity set, for **0.2.3** — see the table above.
- **The staged ladder** (`tools/horizon.py stage/check/test/build`) stays deleted with the format.

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

- `horizon-mod.toml` — the only manifest: `id`, `version = "0.2.3"`, `api = "0.2"`,
  `side = "both"`, `[native]` pinned to `0a875da` / `e59da90`.
- `Cargo.toml` — one crate; the only dependency is `horizon-mod-api` from `.horizon/sdk/`.
- `src/lib.rs` — `register` (two block entity types, four block parts) and the two parts.
- `src/runtime.rs` — the pure decisions (run, impulse, membership, eligibility, budget), 16 tests.
- `src/support.rs` — the game glue.
- `assets/`, `data/` — the carried content.
- `LICENSE`, `LICENSE-NOTICE.md`, `icon.png`, `README.md` — inside the package.
- `tools/e2e.sh` — the in-game scenario (needs a launcher-built game); `tools/craft_recipes.py`
  crafts every carried recipe from the delivered package's own JSON.
- `SLICE-2-PLAN.md` — the slice's plan, written before the first edit.
- `restrictions.hmod` — the delivered package, **37,954 B**, sha256
  `895d8b2058dce2588d7582aebaa81f4d952d42ca4d41899f7ee68a4d88f40e4e`, version 0.2.3.
- `VALIDATION.md`, `REPIN-AUDIT.md` — earlier ladders (retired tooling, kept as history).
- Evidence: `../_shared/evidence/restrictions/` (`sdk-*.log` for 0.2.3 with the sha in each,
  `retired-0.2.1/` and `retired-0.2.2/` for the older runs, the 0.1.0 e2e logs, and the retired
  tree under `retired-hnmod-0.1.0/`); `../_shared/evidence/restrictions-e2e/` (the 0.2.3 legs, the
  red leg, and `retired-0.2.1/`/`retired-0.2.2/`).

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

## Changelog 0.2.3

> **0.2.3** is slice 2, at the campaign pin `0a875da` (the 0.2.0–0.2.2 builds were made at
> `0b14f8a`; the manifest now names the pin and the SDK was refetched for it).
>
> - **The movers sweep every entity, not only mobs.** Upstream's `getEntitiesOfClass(Entity.class,
>   …)` covers dropped stacks, arrows, boats, minecarts and experience orbs; 0.1.0–0.2.2 filtered
>   with `host.mob`. The tick now reads the level's players once, skips only a player
>   (`runtime::sweeps` — the host refuses a player's push and its client owns its motion), and
>   counts only accepted pushes against the run's budget (`ENTITIES_PER_CELL` per powered cell).
>   Proven in game: a dropped item and an experience orb are pulled by a powered Attractor while an
>   unpowered one beside it leaves its own pair untouched; `SELFTEST=1` inverts it and fails.
> - **The two movers' loot tables no longer name `mcjtylib:item_energy`.** That component belongs to
>   McJtyLib, which this package does not ship and 26.3 does not have, so a real break copied
>   nothing and the block dropped **nothing**; `loot give` (no block entity in the context) worked,
>   which hid it. With the modifier gone a break drops one of the block with a pickaxe and one by
>   hand (the blocks declare `requires_tool: false`), asserted in game against vanilla stone's
>   `minecraft:cobblestone` as the differential.
> - **The parity legs** the campaign requires are now in `tools/e2e.sh`: all four blocks placed and
>   read back, an unknown id refused, the loot tables exercised, and all five carried recipes
>   crafted from the delivered package's own JSON in a real crafting table (`tools/craft_recipes.py`,
>   a second `--offscreen` launch because a headless client never opens that menu), with
>   `SELFTEST=recipe` as the fail-capable run.
> - Still not ported, unchanged: One Way and One Way Wall (the pin's `entity_inside` fires only for a
>   block the entity already collides with; One Way Wall needs a per-entity collision shape), the
>   server-side player push (so Glass Boots has no effect here), and the upward fall-distance reset
>   — now implementable (`ServerHost::entity_reset_fall_distance` exists at this pin), next slice.
