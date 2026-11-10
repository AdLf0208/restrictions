# Restrictions — carried content mod

Restrictions 1.21-7.0.3 (MC 1.21.1, NeoForge) carried from its jar into a Horizon
content mod (`.hmod`): four blocks, one item, the recipes, loot tables, advancements,
tags and assets. This folder **is** the mod root (`horizon-mod.toml` + `assets/` +
`data/`); `carry/`, `check.json` and `carry-report.json` are the untouched carry output
kept beside it for provenance. Content only: there is no code here, so the movement
logic (attract/push, the one-way rules, Glass Boots) belongs to the native port in
`ports/restrictions/`.

## Provenance

| | |
|---|---|
| Modrinth project | `oevBqQRC` (slug `restrictions`) |
| Version | `1.21-7.0.3` (version id `QiLugx4P`), game 1.21.1, loader neoforge |
| Jar | `restrictions-1.21-7.0.3.jar`, 45 018 bytes |
| SHA-1 | `e3a12b4b4daa2f12f9a21a8cc059fc0f0537ca1a` (matches Modrinth's `files[].hashes.sha1`) |
| Download | <https://cdn.modrinth.com/data/oevBqQRC/versions/QiLugx4P/restrictions-1.21-7.0.3.jar> |
| Licence | MIT (`META-INF/neoforge.mods.toml`: `MIT License https://github.com/McJtyMods/Restrictions/blob/1.21_neo/LICENSE`) |
| Upstream read | `https://github.com/McJtyMods/Restrictions`, branch `1.21_neo`, commit `fbc351c028414249c1d52e2daed4471fba993c48` (shallow clone, `ports/_shared/upstream/restrictions/`, deleted after the notes below were taken) |

Files read upstream: `src/main/java/mcjty/restrictions/setup/{Registration,ClientSetup}.java`,
`.../blocks/{AttractorTileEntity,PusherTileEntity,BaseTileEntity,OneWayBlock,OneWayWall}.java`,
`.../datagen/DataGenerators.java`. Facts taken from them: Attractor (speed −0.1) and Pusher
(+0.1) are full opaque cubes with `BlockStateProperties.FACING` (six values), a block entity
holding the redstone power level, 6-way orientation on placement (`orientedBlock`), strength
2.0 and `SoundType.METAL`; OneWay is `noCollission()`, `isSuffocating(false)`,
`isRedstoneConductor(false)`, `SoundType.GLASS`, and pushes entities inside it along its
facing; OneWayWall is `noOcclusion()`, `strength(2.0)`, `SoundType.GLASS`, `getLightBlock 15`,
and returns a full cube collision only while the entity moves towards its facing; Glass Boots
is an armour item with a custom wearer model (`GlassBootsModel`) that cancels all of it;
`ClientSetup` sets `RenderType.cutout()` for OneWay and OneWayWall only.

## Carry

```bash
cd ports/_shared/carry-work/restrictions
/tmp/opencode/atm10-carry-target/debug/horizon-port-pack \
    check restrictions-1.21-7.0.3.jar ../../../restrictions/content
# restrictions: Partly. 4 blocks, 1 item port; not 1 renderer or model in code.
#   ports: 4 blocks
#   ports: 1 item
#   ports: 5 recipes
#   ports: 4 loot tables
#   ports: 8 textures
#   ports: blocks take the closest vanilla block's shape, hardness and sounds
#   skipped: 1 renderer or model in code
```

```bash
cd ports/restrictions/content
cp -r carry/assets . && cp -r carry/data .
CARGO_TARGET_DIR=/tmp/opencode/atm10-carry-target \
cargo run --locked --offline --quiet \
  --manifest-path ../../../horizon/crates/cargo-horizon-mod/Cargo.toml -- horizon-mod build
# Built ./target/horizon-mod/restrictions.hmod
cp target/horizon-mod/restrictions.hmod .    # delivered as content/restrictions.hmod
rm -rf target                                # `/target/` in .gitignore is the port's, not this one's
CARGO_TARGET_DIR=/tmp/opencode/atm10-carry-target \
cargo run --locked --offline --quiet \
  --manifest-path ../../../horizon/crates/cargo-horizon-mod/Cargo.toml -- horizon-mod check restrictions.hmod
# restrictions 1.21-7.0.3 (mod, API 0.2, both)
#   19989 bytes, SHA-256 f22bbec9487f15118f2ffb6ac03efcb261d5c5a61fa13d9300768308521cbe55, unsigned
#   may add blocks, items, mob effects and entity types to your worlds
#   no code: content only, nothing to run
```

Carry report (`carry-report.json`): 37 copied, namespaces `[]`, outside `[]`, 5 recipes
upgraded, 2 loot tables upgraded, 5 item definitions added, 1 item, 0 convention tags,
oracle `false`, `blocks` all guessed as `minecraft:carved_pumpkin` (four horizontal
facings — wrong for all four blocks, see fixes).

The `.hmod` holds 54 entries: `horizon-mod.toml` + 53 files.

| Path | Files | |
|---|---|---|
| `assets/restrictions/blockstates` | 4 | carried 1.21.1 blockstates, already `facing=`-keyed |
| `assets/restrictions/items` | 5 | 26.3 item model definitions (carry added 4) |
| `assets/restrictions/models/block` | 4 | carried |
| `assets/restrictions/models/item` | 5 | carried |
| `assets/restrictions/lang` | 2 | `en_us`, `zh_cn` |
| `assets/restrictions/textures/block` | 6 | `attractor` `pusher` `side` `sideone` `onewayn` `oneways` |
| `assets/restrictions/textures/item` | 2 | `glassboots`, `textureboots` (unused by any model) |
| `data/restrictions/horizon/block` | 4 | declarations (this port) |
| `data/restrictions/horizon/item` | 1 | `glassboots` (`minecraft:stick`) |
| `data/restrictions/horizon/creative_tab` | 1 | added here |
| `data/restrictions/recipe` | 5 | upgraded by carry |
| `data/restrictions/loot_table/blocks` | 4 | upgraded by carry |
| `data/restrictions/advancement/recipes/misc` | 5 | upgraded by carry |
| `data/minecraft/tags/block` | 2 | added here (`mineable/pickaxe`, `needs_stone_tool`) |
| `data/c/tags/item` | 3 | added here (`glass_blocks`, `glass_panes`, `slimeballs`) |

## The block declarations, verbatim

`data/restrictions/horizon/block/attractor.json` (identical in `pusher.json`):

```json
{
  "template": "minecraft:beacon",
  "properties": {
    "hardness": 2.0,
    "explosion_resistance": 2.0,
    "requires_tool": false,
    "sounds": "minecraft:iron_block"
  },
  "state_properties": {
    "facing": {
      "type": "enum",
      "values": ["down", "up", "north", "south", "west", "east"]
    }
  },
  "default_state": { "facing": "north" }
}
```

`data/restrictions/horizon/block/oneway.json` (identical in `oneway_wall.json`):

```json
{
  "template": "minecraft:glass",
  "properties": {
    "hardness": 2.0,
    "explosion_resistance": 2.0,
    "requires_tool": false
  },
  "state_properties": {
    "facing": {
      "type": "enum",
      "values": ["down", "up", "north", "south", "west", "east"]
    }
  },
  "default_state": { "facing": "north" }
}
```

Why these templates:

- No vanilla full cube is six-way directional *and* otherwise inert. `carved_pumpkin`
  (the carry's guess) has only four horizontal facings, so `facing=up|down` had no state
  and no model. Vanilla's six-value `facing` is `end_rod` (thin, transparent),
  `lightning_rod`/`observer` (`facing` + `powered`, and a real redstone behaviour),
  `piston` (`facing` + `extended`) and `command_block`/`jigsaw` (block entities).
  `minecraft:stone` plus a **declared** `facing` gives exactly the six states with a full,
  opaque, non-ticking cube and no borrowed behaviour; the mod's own `facing` is the
  `BlockStateProperties.FACING` value set, in vanilla's `Direction` order.
- OneWay/OneWayWall are `RenderType.cutout` in Java and `noOcclusion`, so they take
  `minecraft:glass`: transparent (`can_occlude: false`, rule `same_block`), glass sounds,
  `solid_render: false`, full cube outline and collision. Their states are the same declared
  `facing`, so the carried `facing=` blockstates resolve.
- Numbers are Java's: `strength(2.0f)` → hardness 2.0 **and** explosion resistance 2.0
  (stone's 6.0 is overridden); `requires_tool: false` because the mod never calls
  `requiresCorrectToolForDrops()` and stone's `true` would otherwise be inherited;
  `sounds: "minecraft:iron_block"` because `SoundType.METAL` is not a block and the
  declaration names a vanilla block whose sounds to borrow (`String.valueOf` check in
  `mod_content`). Glass already is `SoundType.GLASS`.

## Hand fixes (what the carry got wrong or left out)

1. **Templates** — all four were `minecraft:carved_pumpkin` (four facings, no `up`/`down`
   state, missing models). Replaced by `stone` + declared `facing` (Attractor, Pusher) and
   `glass` + declared `facing` (OneWay, OneWayWall). Verified: each block now has exactly six
   states, `[facing=north, south, west, east, down, up]`, and
   `setblock …[facing=up|east|west|down]` is accepted in-game.
2. **Occlusion/light/render flags** — inherited correctly from the new templates
   (`can_occlude: true` for the two machines, `false` + `same_block` for the two one-ways;
   `solid_render: false` for the one-ways; `dampening: 15` for the machines, `0` for the
   one-ways).
3. **Lang** — nothing to rewrite: the jar already uses vanilla keys
   (`block.restrictions.*`, `item.restrictions.glassboots`, `itemGroup.restrictions`) and
   Horizon excepts `block.<ns>.<path>`, so the carried `en_us.json`/`zh_cn.json` are used
   as-is. Confirmed in-game: `give` prints "Attractor", "Pusher", "One Way", "One Way
   Wall", "Glass Boots".
4. **Creative tab** — the carry wrote none. Added
   `data/restrictions/horizon/creative_tab/restrictions.json` with
   `"title": "itemGroup.restrictions"` (the key the jar's lang files have), icon
   `restrictions:attractor` and the five items in the Java tab's order. It loads as
   `restrictions:restrictions` after vanilla's tabs with all five items.
5. **Block tags** — the jar ships none (the mod generates them with `DataGen`, which did
   not run into the jar), but every block calls `stonePickaxeTags()`. Added
   `data/minecraft/tags/block/mineable/pickaxe.json` and
   `data/minecraft/tags/block/needs_stone_tool.json` with the four blocks.
6. **Convention tags** — the carry leaves `c:` tags alone (`convention_tags: 0`), and the
   recipes use `#c:glass_blocks`, `#c:glass_panes`, `#c:slimeballs`; an unknown tag expands
   to an empty ingredient, so the recipes would load and never match. Wrote the three tags
   by hand under `data/c/tags/item/` (18 glass blocks incl. `tinted_glass`, 17 panes,
   `slime_ball`; NeoForge's membership).
7. **Item models / blockstates** — carried, none needed rewriting: the carry added the
   26.3 `assets/restrictions/items/<name>.json` model definitions (4) and left
   `models/item/*` + the `facing=` blockstates as the jar has them.

## Evidence

Content loads with no warnings and no skipped files:
`cargo horizon-mod check` (above) and a headless run

```bash
horizon-ctl ls launch --game <fast horizon-client> --world RestrContent --seed 20261103 \
    --creative --headless --wait --game-dir "$SCRATCH/game" --resources <prepared 26.3> \
    --dev-mod ports/restrictions/content
```

- log: `Horizon: content from 1 mod(s) in …/.horizon-cache/mod-content`; the build's
  `horizon-mod-content-warnings.txt` is empty.
- built tables: `model-states.json` has all four blocks with
  `"schema": {"facing": {"named": ["down","up","north","south","west","east"]}}` and six
  states each; `render-definitions.json` gives the machines `can_occlude: true` and the
  one-ways `false`/`same_block`; `gameplay-facts.json` gives hardness 2.0, explosion
  resistance 2.0, `requires_tool: false`, glass sounds on the one-ways and iron on the
  machines.
- `setblock restrictions:attractor[facing=up]`, `…pusher[facing=east]`,
  `…oneway[facing=west]`, `…oneway_wall[facing=down]` all returned
  `restrictions:<name>[facing=<value>]` from `horizon-ctl block`.
- `horizon-ctl break 1 64 0` in survival: `drops: {"restrictions:pusher": 1}` (the loot
  table and its `copy_name`/`copy_components` modifiers load).
- creative inventory: tab `restrictions:restrictions`, title `itemGroup.restrictions`,
  icon `restrictions:attractor`, items attractor/pusher/oneway/oneway_wall/glassboots.

## Gaps (remaining, and why)

1. **No block entity for Attractor and Pusher.** The content format has no block-entity
   declaration: a block file's keys are `template`, `properties`, `shapes`,
   `state_properties`, `default_state`, `connects_to`, `thickness`, `wood_type`,
   `wall_block`, `item`, `components` (`horizon-mods/src/content.rs`, `deny_unknown_fields`),
   and there is no `horizon/block_entity/` loader. Block entities are a native declaration
   (`native_block_entity`, `native_block_entity_tick`), so the power level and the push tick
   are the native port's job. Consequence: the carried loot tables' `copy_components`
   (`mcjtylib:item_energy`, `minecraft:container`) copy nothing — the block has no entity
   — which is harmless and was checked by breaking one in survival.
2. **OneWay is solid here; in Java it is `noCollission()`.** The content format can only
   express collision through `shapes`, and `shapes` (a) selects by a *template* state
   property (`glass` and `stone` have none) and (b) replaces the selection outline *and* the
   collision box together. The alternative — `minecraft:end_rod` (six-way `facing`) with an
   empty shape for every value — gives the Java collision but also an empty outline, and an
   empty outline means the block is no longer under the crosshair (Horizon `clip_ray` only
   hits `outline` boxes), so it could not be broken or built against. Keeping glass's
   collision keeps the block usable; measured: a dropped item rests at `y = 65.0` on top of
   a OneWay at `y = 64`. This is an engine API gap (splitting outline from collision, or a
   `collision: false` property), not something the native port can work around.
3. **OneWayWall's velocity-dependent collision** (a full cube only while the entity moves
   *towards* `facing`, empty otherwise, and empty for players in Glass Boots) cannot be
   expressed either; ours is a plain solid cube. Java also sets `getLightBlock 15` for it
   while glass is transparent, so ours lets light through.
4. **`facing` is not set on placement.** The template's behaviour (stone/glass) has no
   orientation logic, so a placed block keeps `default_state` `facing=north`. The Java
   `orientedBlock`/`getNearestLookingDirection` behaviour needs the native port
   (`native_place_block` can read the placer's look and set the state). `setblock …[facing=…]`
   works, and pistons/push-reactions are the template's.
5. **Glass Boots is not armour.** The item is a `minecraft:stick` template (carry: `items: 1`,
   `equipment: 0`); no `minecraft:equippable`, no armour points, no `GlassBootsModel`
   (`check` skipped "1 renderer or model in code"), and `textures/item/textureboots.png` is
   referenced by nothing. Its message keys (`message.restrictions.*`) are carried and
   translated but unused until the native item exists.
6. **No tooltip/`info` lines.** The Java blocks add mcjtylib tooltips
   (`message.restrictions.shiftmessage` + `*.header`); the content format has no tooltip
   hook, so the lang entries are inert.
7. **Models not visually verified.** The only runs here are headless (`ctl screenshot` →
   "no renderer yet"); the blockstates/models/items are in the overlay and the content build
   reports no warnings, but nobody has seen the four cubes or the item icons drawn.
8. **`zh_cn.json` is upstream-incomplete** (no `block.restrictions.oneway_wall`,
   no `item.restrictions.glassboots`), so those two names show raw keys in Chinese. Kept as
   upstream has it rather than inventing translations.
9. Native behaviour absent by design (this folder is data only): attract/push with the
   redstone signal, the OneWay push field, the Glass Boots exemption, block entity sync and
   the tooltip. See `ports/restrictions/notes.md` and the ledger row for those.

## Re-running

`check <jar> ports/restrictions/content` deletes and rewrites `content/carry/` and
`content/outside/` and the two report JSONs; the mod's own `assets/`, `data/` and
`horizon-mod.toml` at the folder root are hand-owned and are **not** touched, so a fresh
carry means re-applying the fixes above (the four block declarations, the creative tab, the
two block tags, the three `c:` tags), then `horizon-mod build`/`check` again.
