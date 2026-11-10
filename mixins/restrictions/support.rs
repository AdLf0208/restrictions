// Game-side glue for Restrictions slice 1 (Attractor/Pusher, mobs only).
// Injected into `crate::game` as `restrictions_state`; it needs the game, so it
// is not part of the standalone library (only `runtime.rs` is).

use horizon_client::containers::ModBlockEntity;
use horizon_world::level::PlacementContext;
use horizon_world::nbt::Compound;
use horizon_world::registry::BlockStateId;

use crate::game::restrictions::{
    boxes_meet, cell_of, facing_for_yaw, facing_vector, impulse, mover_for, orients_on_placement,
    run_bounds, volume,
};

/// Give the mover blocks a block entity (`native_block_entity`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity(block: &str, entity: &mut Option<(String, Compound)>) {
    if mover_for(block).is_some() {
        *entity = Some((block.to_owned(), Compound::new()));
    }
}

/// The mover blocks tick (`native_block_entity_ticks`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity_ticks(block: &str, ticks: &mut bool) {
    if mover_for(block).is_some() {
        *ticks = true;
    }
}

/// `getStateForPlacement`: a placed Restrictions block keeps the placer's
/// horizontal facing, as McJtyLib's `BaseBlock` does with
/// `OrientationTools.getFacingFromEntity` (its ordinary-case fallback; the
/// placer's height is not part of `PlacementContext`, so no UP/DOWN special
/// case).
#[allow(private_interfaces)]
pub fn on_state_for_placement(
    level: &crate::game::GameLevel<'_>,
    state: BlockStateId,
    context: &PlacementContext,
    answer: &mut Option<Option<BlockStateId>>,
) {
    let Some(block) = level.registry.state(state).map(|state| state.name.as_str()) else {
        return;
    };
    if !orients_on_placement(block) {
        return;
    }
    if let Some(facing) =
        level.native_state_with_property(state, "facing", facing_for_yaw(context.yaw))
    {
        *answer = Some(Some(facing));
    }
}

/// One server tick of a mover: push every entity whose box meets the powered
/// run in front of it (upstream's AABB intersection, not a feet cell).
#[allow(private_interfaces)]
pub fn on_tick(game: &mut crate::game::Game<'_>, pos: [i32; 3], entity: &ModBlockEntity) {
    let Some(mover) = mover_for(&entity.id) else {
        return;
    };
    let Some(facing) = game
        .native_block_property(pos, "facing")
        .and_then(|facing| facing_vector(&facing))
    else {
        return;
    };
    let dimension = game.native_dimension();
    let signal = game.native_neighbor_signal(dimension, pos);
    let Some(run) = run_bounds(pos, facing, signal) else {
        return;
    };
    let push = impulse(mover, facing);
    for mob in game.native_mobs(dimension) {
        let bounds = game
            .native_entity(mob.id)
            .and_then(|entity| game.native_entity_bounding_box(entity));
        let met = match bounds {
            Some(bounds) => boxes_meet(run, bounds),
            // Kinds without a box: keep the feet-cell test rather than drop them.
            None => volume(pos, facing, signal).contains(&cell_of(mob.pos)),
        };
        if met {
            game.native_push_mob(dimension, mob.id, push);
        }
    }
}
