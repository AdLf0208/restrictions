# Re-pin audit — `restrictions` at Horizon `83ad384f`

Read-only audit (2026-11-05). No port code, content, tools or campaign docs were
changed; no build, stage or e2e was run. Verdicts are source reads.

| | |
|---|---|
| New Horizon | `83ad384f48d0742746d518737511882680aab5b7` (427 hooks / 159 helpers) at `ports/_shared/pins/horizon-83ad384f` |
| New mixins | `e8cd0aa38cffef49cb2e088ef716baa107148c02` |
| Old Horizon (reference) | `c9d474dd…` — 108 hooks (`ports/_shared/repin-83ad384f.md`); the old sources were read from a staged `c9d474d` tree during this audit (since removed by a concurrent target clean) |
| Port pin | still `c9d474dd…` (`compatibility.json`, `mixins/restrictions/horizon-mixin.toml`) |
| Source shorthand | `hooks.rs` = `crates/horizon-client/src/game/native_hooks.rs`, `support.rs` = `mixins/restrictions/support.rs`, `runtime.rs` = `mixins/restrictions/runtime.rs`, `motion.rs` = `crates/horizon-client/src/game/native_entity_motion.rs`, `content.rs` = `crates/horizon-mods/src/content.rs`, `docs` = `docs/native-mods.md` |

## 1. Deferred inventory and verdicts

Deferred items from `notes.md` §"Gaps" + the "Known discrepancy" + ARCHITECTURE
item 9: **10** (one of which is already done — see §4).

| # | Deferred feature | Old pin | New pin verdict | Symbol / evidence | Next step |
|---|---|---|---|---|---|
| 1 | **One Way** (no collision, pushes every entity inside its own cell, `+0.2·facing`) | deferred (no no-collision template with a block entity) | **realizable now** — trigger hook existed, the no-collision content field is new | `block_entity_inside` `hooks.rs:7913` (API 73, present at `c9d474d` too) + `collision_shapes: {"default": []}` (`content.rs:271`, `mod_content.rs:1618`, docs `:173-203`) | Move `oneway.json` off `minecraft:glass`; declare `collision_shapes: {"default": []}` (and `occludes: false` if it should not hide neighbours) and queue the push (§2.1) |
| 2 | **One Way Wall** (full collision only while moving along `facing`) | blocked | **absent** | `collision_shapes` is per *state*, not per entity; no collision hook in the 427; `block_collision` `hooks.rs` (API 363, `docs:3515`) is a read | Keep blocked; nothing on this pin expresses "solid for one direction" |
| 3 | Players cannot be moved (server side) | blocked | **still blocked server-side; client half now possible** | `set_velocity` "not for players" `motion.rs:57-60`; `push_player` is client-only `native_motion.rs:31`; new: mod messages (`net_send_to_player` `native_net.rs:116`, `net_from_server` `hooks.rs:6873`, API 40 docs `:331`) | Server computes, sends the push; the client half calls `push_player` in `tick` — upstream also pushes players client-side (§2.2) |
| 4 | Item entities cannot be moved | blocked | **realizable now** | `native_item_entities(dimension, min, max)` `hooks.rs:8579` (API 42, box-filtered, gives ids) + `EntityRef::set_velocity` `motion.rs:51` (new; items are a simulated kind) | Enumerate with `native_item_entities` over the run's AABB and push each id |
| 5 | Arrows / boats / orbs out of scope | out of scope | **partly realizable** | `entity_tick_pre` `hooks.rs:7336` (new) hears mobs, items, minecarts **and boats** — not projectiles/orbs/TNT/falling (`docs:1155`); `set_velocity` covers all simulated kinds | Boats/carts: yes. Arrows/orbs: still no enumeration → blocked |
| 6 | Volume membership is an exact feet cell, not upstream's entity box | recorded discrepancy | **realizable now** | `native_entity_bounding_box` `motion.rs:84` (new), `EntityRef::bounding_box` docs `:2646` | Replace `cell_of(mob.pos)` (`support.rs:75-76`) with a box/volume intersection; fixes "a cow one block below the run is still moved" |
| 7 | No fall-distance reset for `facing = up` | deferred | **partly realizable** | `merge_nbt` works on mobs and dropped items, **never players** (docs `:2657`); `native_entity_nbt` `crates/horizon-client/src/game/native_entity_data.rs:16` | `data merge` `{FallDistance:1.0f}` on the pushed mob/item; players stay unhandled |
| 8 | No client-side player prediction and no `powered` sync | deferred | **usable** | `block_entity_sync` `hooks.rs` (API 52) re-sends the block and update tag; mod messages API 40 | Only needed together with #3's client half |
| 9 | Facing is not set on placement | "recorded for slice 2" | **already implemented** | `mixins/restrictions/horizon-mixin.toml` injection `facing-on-placement` → `state_for_placement` `hooks.rs:1727`; e2e asserts it (`tools/e2e.sh:213-257`) | Nothing to do — remove the stale gap |
| 10 | Wall variants, McJtyLib 2-block placement rule, recipes (`c:` tags, `copy_components` loot) | deferred | content work; 2-block rule still partial | `PlacementContext` has `yaw/pitch/hit/sneaking` but no placer body/eye position (`crates/horizon-world/src/level/place.rs:55-79`) | Ordinary content work; the UP/DOWN special case stays out |

Net: **4 of 10 newly realizable** (#1, #4, #6, and #8 as a building block),
**2 partly** (#3 client-only, #5 boats/carts, #7 mobs/items), **2 still blocked**
(#2, arrows/orbs), 1 already done (#9), 1 content work (#10).

## 2. The three findings that matter

### 2.1 One Way is now possible — and it reaches players

Two separate conditions were missing before; one was never missing:

1. **The trigger was available all along.** `block_entity_inside` is at
   `c9d474d` too (verified in the staged `c9d474d` tree read during this audit,
   since cleaned), fires
   from the movement sweep for **every non-`minecraft:` block** the entity's box
   touches, and "idle overlap still fires" (`hooks.rs:7910-7912`). It is reached
   for mobs (`crates/horizon-client/src/game/creatures.rs:124`), item entities
   (`crates/horizon-client/src/entities.rs:741`), projectiles
   (`crates/horizon-client/src/arrows.rs:1104`) and **the window's own player**
   (`crates/horizon-client/src/motion.rs:1787`, `kind: "minecraft:player"`,
   guests included via `as_guest`).
2. **The content blocker was the collision shape.** `oneway.json` still uses
   `minecraft:glass` (full collision), and the old schema had no way to empty it
   (old `BlockShapes`: one property plus values, no `collision_shapes`).
   At this pin `collision_shapes: {"default": []}` does exactly that
   (`content.rs:271`, docs `:173-203`).

Caveat that shapes the design: API 73 hooks "run synchronously without `self`"
(`docs:871`), so the handler cannot call `native_push_mob`/`set_velocity`
directly. It must queue `(entity, kind, cell)` into a static and apply it from
`server_tick`/`level_tick_post`, exactly like `redstonepen`'s pending writes
(`redstonepen/mixins/redstonepen/support.rs` `Pending`). For players the apply
step is still blocked (see 2.2) — so One Way is **complete for mobs, items and
projectiles, still open for players**, and only *half* of the old "players
cannot be moved" gap closes here.

### 2.2 Players: the server is still the wall, the client is the door

- `native_entity_set_velocity` returns `false` for a player, with the reason in
  the doc comment: "False for a player (its client moves it)"
  (`motion.rs:51-60`).
- `native_push_player` exists only as a client helper (`native_motion.rs:31-41`)
  and is the one the engine's own explosion knockback uses.
- New at this pin: mod messages (`net_send_to_player` `native_net.rs:116`,
  `net_from_server` `hooks.rs:6873`; API 40, docs `:331`). So a faithful port is
  possible: the server half computes the impulse (as it already does for mobs)
  and sends it; the client half calls `push_player`. That is what upstream does —
  `notes.md` records that the player force is applied on the client and that
  glass boots gate exactly that. It needs a **client half** the port does not
  have yet (the bundle is one `Game` module), so it is a slice-3-sized change,
  not a one-liner.

### 2.3 AABB membership and item push are one small change each

- `native_entity_bounding_box` (`motion.rs:84`, new) returns the entity's box;
  for mobs the port has ids from `native_mobs` (`native_mobs.rs:223`). The
  recorded discrepancy (`notes.md` "Known discrepancy") can be fixed in
  `support.rs:75-76` by intersecting `[min,max]` with the run's box instead of
  `cells.contains(&cell_of(mob.pos))`.
- `native_item_entities(dimension, min, max)` (`hooks.rs:8579`) already filters by
  **box overlap** (`box_meets`, `hooks.rs:8579-8605`) and returns ids, so the item
  push needs no enumeration design at all: the same run box that is handed to
  the mob test is handed to it, and each id is pushed with `set_velocity`.

## 3. Still blocked, and the smallest unblocker

| Need | Evidence | Unblocker |
|---|---|---|
| One Way **Wall** | no per-entity collision shape; `collision_shapes` is per state | A per-entity collision override (or a `getCollisionShape(state, pos, entity)` hook) |
| Server-side player push | `motion.rs:57-60`; `push_player` client-only | A player velocity write; today: client half + mod message |
| Arrows / orbs / TNT / falling blocks as push targets | `entity_tick_pre` hears mobs/items/carts/boats only (`docs:1155`); no listing helper for them | A generic entity-list helper (mobs have `native_mobs`, items `native_item_entities`) |
| Fall-distance reset for players | `merge_nbt` never touches players (`docs:2657`) | A player NBT/velocity write |
| McJtyLib's 2-block UP/DOWN placement | `PlacementContext` (`place.rs:55-79`) has no placer position | Placer entity/eye position in the context |

## 4. Stale claims in `notes.md` / ARCHITECTURE (do not re-derive)

- Gap "**Facing is not set on placement** … recorded for slice 2" is out of date:
  the `facing-on-placement` injection is in `horizon-mixin.toml` and the e2e
  asserts the placed facing (`tools/e2e.sh:213-257`).
- ARCHITECTURE item 9 says "6 tests / 6 embedded"; `runtime.rs` currently has
  **11** `#[test]`s (the placement slice added five). The pinned claim is stale.
- The gap "no neutral no-collision template with a block entity" conflates two
  things: One Way needs **no block entity** (upstream has none), only empty
  collision — `collision_shapes: []` settles it. Only the Attractor/Pusher need
  a BE template.
- "Players and item entities cannot be moved at the pin" is now half wrong: items
  are movable (`set_velocity` + `native_item_entities`), and the One Way trigger
  reaches players (the *push* still does not).

## 5. Highest-value next step (one)

**Fix volume membership to the entity box (AABB), on the mob path and the new
item path, in one slice.** It is the only recorded *correctness* bug in the port
(a cow one block below the run is moved upstream and not here, and a cow at the
run's edge behaves differently), the fix is local (`support.rs:75-76`), and the
same box is exactly what `native_item_entities` needs — so the same change also
delivers the item-entity push that the notes list as impossible. Prove it with a
differential the current e2e can run: a cow whose **feet are one block below**
the run must move (upstream semantics) while the unpowered control does not, and
a cow whose box only *touches* the run from outside must not move. One Way
(`collision_shapes: []` + queued `block_entity_inside` push) is the natural next
slice after that.
