// Game-side glue for Restrictions slice 1 (Attractor/Pusher, mobs only).
//
// The decisions live in `runtime`; this module only reads the game and writes back through the
// host. It is compiled inside the package's own crate, so it names `mod_api` types freely.

use mod_api::{BlockState, HostBlockStates, LevelHost, ServerHost, StateForPlacementEvent};

use crate::runtime::{
    self, Mover, boxes_meet, cell_of, facing_for_yaw, facing_vector, impulse, run_bounds, volume,
};

/// `getStateForPlacement`: a placed Restrictions block keeps the placer's horizontal facing, as
/// McJtyLib's `BaseBlock` does with `OrientationTools.getFacingFromEntity` (its ordinary-case
/// fallback; the placer's height is not part of `PlacementContext`, so no UP/DOWN special case).
pub(crate) fn state_for_placement(
    level: &dyn LevelHost,
    event: &mut StateForPlacementEvent<'_>,
) -> Option<Option<BlockState>> {
    let block = level.state_block(event.state)?;
    if !runtime::orients_on_placement(block) {
        return None;
    }
    let facing = facing_for_yaw(event.context.yaw);
    // Parse `<block>[facing=<direction>]`, the state the block's own default would take with
    // that property set; `None` leaves vanilla's placement answer alone.
    let state = level.block_state_id(&format!("{block}[facing={facing}]"))?;
    Some(Some(state))
}

/// One server tick of a mover: push every mob whose box meets the powered run in front of it
/// (upstream's AABB intersection, not a feet cell).
///
/// The mob list is the level's whole entity list filtered to mobs, exactly the scope the retired
/// `native_mobs` helper gave this slice; item entities and players stay out of it (see the gap
/// list in `notes.md`).
pub(crate) fn on_tick(mover: Mover, host: &mut dyn ServerHost, pos: [i32; 3]) {
    let dimension = host.dimension();
    let Some(level) = host.level(dimension) else {
        return;
    };
    let Some(state) = level.block_state(&*host, pos) else {
        return;
    };
    let facing = {
        let states = host.block_states();
        state
            .property(&states, "facing")
            .ok()
            .flatten()
            .and_then(facing_vector)
    };
    let Some(facing) = facing else {
        return;
    };
    let signal = level.best_neighbor_signal(&*host, pos).unwrap_or_default();
    let Some(run) = run_bounds(pos, facing, signal) else {
        return;
    };
    let push = impulse(mover, facing);
    let cells = volume(pos, facing, signal);
    let Some(entities) = level.all_entities(&*host) else {
        return;
    };
    for entity in entities {
        if host.mob(entity).is_none() {
            continue;
        }
        let met = match entity.bounding_box(&*host) {
            Some(bounds) => boxes_meet(run, bounds),
            // Kinds without a box: keep the feet-cell test rather than drop them.
            None => entity
                .position(&*host)
                .is_some_and(|feet| cells.contains(&cell_of(feet))),
        };
        if !met {
            continue;
        }
        // `Entity.push`: an impulse added to the velocity, never a teleport (upstream's call).
        entity.push(host, push);
    }
}
