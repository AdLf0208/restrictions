// Restrictions for Horizon — the mover logic (pure).
//
// Ported from Restrictions 1.21-7.0.3 (McJtyMods/Restrictions, MIT) for
// Minecraft 1.21.1 NeoForge. Upstream source read for behaviour only; this is a
// clean-room Rust rewrite.
//
// Slice 1: the Attractor and Pusher blocks move entities whose bounding box
// meets the run in front of the block, `signal` cells deep (0 = off). Each tick
// adds ±0.1 blocks/tick along the facing (upstream's AABB intersection).
// One Way / One Way Wall need a no-collision block with a block entity and are
// deferred (engine gap); players and item entities cannot be moved at the pin.

pub const ATTRACTOR: &str = "restrictions:attractor";
pub const PUSHER: &str = "restrictions:pusher";
pub const ONEWAY: &str = "restrictions:oneway";
pub const ONEWAY_WALL: &str = "restrictions:oneway_wall";

/// A block that moves entities in front of it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mover {
    Attractor,
    Pusher,
}

/// The mover a block id is, if any.
pub fn mover_for(block: &str) -> Option<Mover> {
    match block {
        ATTRACTOR => Some(Mover::Attractor),
        PUSHER => Some(Mover::Pusher),
        _ => None,
    }
}

/// Whether a block id orients to its placer: all four carried blocks declare
/// the six-way `facing` property and use McJtyLib's rotation placement.
pub fn orients_on_placement(block: &str) -> bool {
    matches!(block, ATTRACTOR | PUSHER | ONEWAY | ONEWAY_WALL)
}

/// The horizontal `facing` a block takes when a placer with `yaw` places it:
/// the direction toward the placer, as `Direction.fromYRot(yaw).getOpposite()`
/// (McJtyLib `OrientationTools.getFacingFromEntity`'s ordinary-case fallback).
pub fn facing_for_yaw(yaw: f32) -> &'static str {
    // `Direction.fromYRot` maps floor(yaw / 90 + 0.5) & 3 to
    // SOUTH, WEST, NORTH, EAST; the block faces the opposite way, the placer.
    let quarter = ((f64::from(yaw) / 90.0 + 0.5).floor() as i64 & 3) as u8;
    match quarter {
        0 => "north",
        1 => "east",
        2 => "south",
        _ => "west",
    }
}

/// The unit vector of a six-way `facing` property (minecraft's axis names).
pub fn facing_vector(facing: &str) -> Option<[i32; 3]> {
    Some(match facing {
        "north" => [0, 0, -1],
        "south" => [0, 0, 1],
        "west" => [-1, 0, 0],
        "east" => [1, 0, 0],
        "up" => [0, 1, 0],
        "down" => [0, -1, 0],
        _ => return None,
    })
}

/// The cells in front of `pos` that a signal powers: `pos + facing*1 …
/// pos + facing*signal`, the block's own cell excluded. Empty at signal 0.
pub fn volume(pos: [i32; 3], facing: [i32; 3], signal: i32) -> Vec<[i32; 3]> {
    if signal <= 0 {
        return Vec::new();
    }
    (1..=signal)
        .map(|step| {
            [
                pos[0] + facing[0] * step,
                pos[1] + facing[1] * step,
                pos[2] + facing[2] * step,
            ]
        })
        .collect()
}

/// The velocity added to a mob in the volume each tick: the attractor pulls
/// toward the block (−0.1 along the facing), the pusher pushes away (+0.1).
pub fn impulse(mover: Mover, facing: [i32; 3]) -> [f64; 3] {
    let sign = match mover {
        Mover::Attractor => -0.1,
        Mover::Pusher => 0.1,
    };
    [
        f64::from(facing[0]) * sign,
        f64::from(facing[1]) * sign,
        f64::from(facing[2]) * sign,
    ]
}

/// The block cell a mob's feet position is in.
pub fn cell_of(pos: [f64; 3]) -> [i32; 3] {
    [
        pos[0].floor() as i32,
        pos[1].floor() as i32,
        pos[2].floor() as i32,
    ]
}

/// The world-space box of the powered run (`volume`) as `[min, max]` corners,
/// one full block per cell. `None` when the signal is off (no run).
///
/// Upstream intersects the entity's bounding box with the run's AABB
/// (`BaseTileEntity.getValidEntities` → `level.getEntitiesOfClass` over the
/// run), so a mob whose feet are below the block plane but whose body reaches
/// into the run is still moved. This is that box.
pub fn run_bounds(pos: [i32; 3], facing: [i32; 3], signal: i32) -> Option<[[f64; 3]; 2]> {
    let cells = volume(pos, facing, signal);
    let first = *cells.first()?;
    let last = *cells.last()?;
    let mut min = [0.0; 3];
    let mut max = [0.0; 3];
    for axis in 0..3 {
        let (a, b) = (first[axis], last[axis]);
        min[axis] = f64::from(a.min(b));
        max[axis] = f64::from(a.max(b) + 1);
    }
    Some([min, max])
}

/// Vanilla `AABB.intersects`: two boxes meet when every axis overlaps
/// strictly, so boxes that only touch at a face do not.
pub fn boxes_meet(a: [[f64; 3]; 2], b: [[f64; 3]; 2]) -> bool {
    (0..3).all(|axis| a[0][axis] < b[1][axis] && a[1][axis] > b[0][axis])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn movers_are_recognised_by_block_id() {
        assert_eq!(mover_for(ATTRACTOR), Some(Mover::Attractor));
        assert_eq!(mover_for(PUSHER), Some(Mover::Pusher));
        assert_eq!(mover_for("restrictions:oneway"), None);
        assert_eq!(mover_for("minecraft:beacon"), None);
    }

    #[test]
    fn facing_vectors_match_minecraft_names() {
        assert_eq!(facing_vector("north"), Some([0, 0, -1]));
        assert_eq!(facing_vector("south"), Some([0, 0, 1]));
        assert_eq!(facing_vector("west"), Some([-1, 0, 0]));
        assert_eq!(facing_vector("east"), Some([1, 0, 0]));
        assert_eq!(facing_vector("up"), Some([0, 1, 0]));
        assert_eq!(facing_vector("down"), Some([0, -1, 0]));
        assert_eq!(facing_vector("sideways"), None);
    }

    #[test]
    fn the_volume_is_the_signal_deep_run_in_front() {
        let pos = [10, 64, 10];
        let east = [1, 0, 0];
        assert!(volume(pos, east, 0).is_empty(), "unpowered is off");
        assert_eq!(volume(pos, east, 1), vec![[11, 64, 10]]);
        assert_eq!(
            volume(pos, east, 3),
            vec![[11, 64, 10], [12, 64, 10], [13, 64, 10]]
        );
        assert_eq!(volume(pos, [0, 1, 0], 2), vec![[10, 65, 10], [10, 66, 10]]);
        assert_eq!(volume(pos, [0, 0, -1], 2), vec![[10, 64, 9], [10, 64, 8]]);
        assert_eq!(volume(pos, east, 15).len(), 15);
    }

    #[test]
    fn attractor_pulls_and_pusher_pushes_along_the_facing() {
        let north = [0, 0, -1];
        assert_eq!(impulse(Mover::Attractor, north), [0.0, 0.0, 0.1]);
        assert_eq!(impulse(Mover::Pusher, north), [0.0, 0.0, -0.1]);
        assert_eq!(impulse(Mover::Attractor, [0, 1, 0]), [0.0, -0.1, 0.0]);
        assert_eq!(impulse(Mover::Pusher, [1, 0, 0]), [0.1, 0.0, 0.0]);
    }

    #[test]
    fn mob_feet_are_assigned_to_their_block_cell() {
        assert_eq!(cell_of([10.5, 64.0, 10.5]), [10, 64, 10]);
        assert_eq!(cell_of([-0.1, 63.9, -0.1]), [-1, 63, -1]);
    }

    #[test]
    fn the_volume_excludes_the_blocks_own_cell() {
        let pos = [0, 64, 0];
        for cell in volume(pos, [0, 0, 1], 15) {
            assert_ne!(cell, pos);
        }
    }

    #[test]
    fn the_run_box_spans_its_cells() {
        // East from x=10: cells 11..=13, so the box is x 11..14, one block
        // wide on y and z.
        assert_eq!(
            run_bounds([10, 64, 10], [1, 0, 0], 3),
            Some([[11.0, 64.0, 10.0], [14.0, 65.0, 11.0]])
        );
        // North is negative z, so min z is the far cell and max z the near one.
        assert_eq!(
            run_bounds([10, 64, 10], [0, 0, -1], 2),
            Some([[10.0, 64.0, 8.0], [11.0, 65.0, 10.0]])
        );
        assert_eq!(
            run_bounds([10, 64, 10], [0, 1, 0], 2),
            Some([[10.0, 65.0, 10.0], [11.0, 67.0, 11.0]])
        );
        assert_eq!(
            run_bounds([10, 64, 10], [1, 0, 0], 0),
            None,
            "off has no run"
        );
    }

    #[test]
    fn a_box_meets_the_run_only_when_it_overlaps() {
        let run = run_bounds([0, 65, 0], [1, 0, 0], 15).expect("signal 15 has a run");
        // A cow standing with its feet on the block plane (y=65).
        assert!(boxes_meet(run, [[3.5, 65.0, 0.5], [4.4, 66.4, 1.5]]));
        // Upstream's case: feet one block below, the body reaches into the run.
        assert!(boxes_meet(run, [[3.5, 64.0, 0.5], [4.4, 65.4, 1.5]]));
        // Two blocks below: the box tops out at 64.4, under the run.
        assert!(!boxes_meet(run, [[3.5, 63.0, 0.5], [4.4, 64.4, 1.5]]));
        // A box that only touches the run's face does not meet it.
        assert!(!boxes_meet(run, [[-0.4, 65.0, 0.5], [1.0, 66.4, 1.5]]));
        // Outside on another axis.
        assert!(!boxes_meet(run, [[3.5, 65.0, 1.5], [4.4, 66.4, 2.5]]));
    }

    #[test]
    fn placement_faces_the_placer_from_the_look_direction() {
        // Yaw 0 looks south, so the block faces north, toward the placer
        // (McJtyLib `OrientationTools.getFacingFromEntity` fallback:
        // `entity.getDirection().getOpposite()`).
        assert_eq!(facing_for_yaw(0.0), "north");
        assert_eq!(facing_for_yaw(90.0), "east");
        assert_eq!(facing_for_yaw(180.0), "south");
        assert_eq!(facing_for_yaw(270.0), "west");
    }

    #[test]
    fn placement_facing_wraps_and_handles_negative_yaw() {
        assert_eq!(facing_for_yaw(-90.0), "west");
        assert_eq!(facing_for_yaw(-180.0), "south");
        assert_eq!(facing_for_yaw(360.0), "north");
        assert_eq!(facing_for_yaw(450.0), "east");
        assert_eq!(facing_for_yaw(44.9), "north");
        assert_eq!(facing_for_yaw(45.0), "east");
        assert_eq!(facing_for_yaw(-45.0), "north");
        assert_eq!(facing_for_yaw(-45.1), "west");
    }

    #[test]
    fn placement_facing_is_always_horizontal() {
        for yaw in [
            -720.0, -270.0, -44.0, 0.0, 45.0, 179.0, 270.0, 360.0, 1080.0,
        ] {
            let facing = facing_vector(facing_for_yaw(yaw))
                .unwrap_or_else(|| panic!("yaw {yaw} did not name a facing"));
            assert_eq!(facing[1], 0, "yaw {yaw} must not face up or down");
        }
    }

    #[test]
    fn the_push_follows_the_placement_facing() {
        // A block placed by a placer looking north (yaw 180) faces south, so
        // its front run and impulse point south: the pusher pushes south and
        // the attractor pulls north, never the default north-facing push.
        let facing = facing_vector(facing_for_yaw(180.0)).expect("yaw 180 is horizontal");
        assert_eq!(facing, [0, 0, 1]);
        assert_eq!(impulse(Mover::Pusher, facing), [0.0, 0.0, 0.1]);
        assert_eq!(impulse(Mover::Attractor, facing), [0.0, 0.0, -0.1]);
    }

    #[test]
    fn the_four_carried_blocks_orient_on_placement() {
        for block in [ATTRACTOR, PUSHER, ONEWAY, ONEWAY_WALL] {
            assert!(orients_on_placement(block), "{block}");
        }
        for block in [
            "minecraft:beacon",
            "minecraft:glass",
            "restrictions:glassboots",
        ] {
            assert!(!orients_on_placement(block), "{block}");
        }
    }
}
