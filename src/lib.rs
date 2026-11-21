//! Restrictions — the Attractor and Pusher movers, as one `impl Hooks` at the crate root.
//!
//! The carried blocks are content in this package (`assets/`, `data/`); the behaviour is here:
//! each mover owns a block entity (a [Part](mod_api::BlockEntityPart) the game calls only for
//! those two blocks), reads the facing and the strongest neighbouring redstone level every
//! server tick, and pushes the entities — mobs, dropped stacks, arrows, boats, experience orbs —
//! whose box meets the powered run in front of it. All four carried blocks also take the placer's
//! facing on placement.
//!
//! The numbers — the run, the impulse, the placement facing, box intersection — are in
//! [`runtime`], a plain module with no `mod_api` types, so `cargo test` alone proves them.
use mod_api::{
    self, BlockEntityPart, BlockEntityTickEvent, BlockEntityTicksEvent, BlockPart, BlockState,
    Hooks, Host, LevelHost, Registrar, RegistrationContext, ServerHost, StateForPlacementEvent,
};

pub mod runtime;
mod support;

use runtime::Mover;

/// One mover block entity: the Attractor pulls, the Pusher pushes.
#[derive(Clone, Copy, Debug)]
struct MoverPart {
    mover: Mover,
}

#[mod_api::horizon_part]
impl BlockPart for MoverPart {}

#[mod_api::horizon_part]
impl BlockEntityPart for MoverPart {
    /// The mover's block entity ticks on the server (`EntityBlock.getTicker`).
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: move the mobs in the powered run in front of the block.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        // This part writes nothing into the block entity's own payload, so the tick must not
        // dirty the chunk: `Unchanged` discards no one else's edits, it only says ours is none.
        *event.reply = mod_api::BlockEntityTickReply::Unchanged;
        support::on_tick(self.mover, host, event.pos);
    }
}

/// The carried blocks keep the placer's facing (`BaseBlock.getStateForPlacement`).
#[derive(Clone, Copy, Debug)]
struct Placement;

#[mod_api::horizon_part]
impl BlockPart for Placement {
    fn state_for_placement(
        &self,
        level: &dyn LevelHost,
        event: &mut StateForPlacementEvent<'_>,
    ) -> Option<Option<BlockState>> {
        support::state_for_placement(level, event)
    }
}

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare the two block entity types and attach the parts to the carried blocks.
    ///
    /// The declaration owns the type id (`restrictions:attractor`, `restrictions:pusher`) and
    /// the game creates the entity for the block it is held by — the retired `block_entity`
    /// hook that answered the block's id and an empty compound is no longer needed.
    fn register(&self, r: &mut dyn Registrar, cx: &RegistrationContext) {
        for (path, block, mover) in [
            ("attractor", runtime::ATTRACTOR, Mover::Attractor),
            ("pusher", runtime::PUSHER, Mover::Pusher),
        ] {
            let kind = r.block_entity_type(path).blocks(&[block]).build();
            // Only our own duplicate declaration can refuse here, and without the part the
            // block would sit inert: refuse the mod's registration rather than load a
            // half-working mover, so the game log names it.
            if let Err(error) = r.block_entity_part(&kind, MoverPart { mover }) {
                cx.refuse(&format!(
                    "restrictions: the {path} mover part was refused: {error}"
                ));
                return;
            }
        }
        for block in [
            runtime::ATTRACTOR,
            runtime::PUSHER,
            runtime::ONEWAY,
            runtime::ONEWAY_WALL,
        ] {
            let key = r.block_key(block);
            r.block_part(key, Placement);
        }
    }
}
