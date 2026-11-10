#!/usr/bin/env bash
# In-game check for Restrictions slice 1 (Attractor/Pusher, mobs only).
#
# In The End at the feet plane y=65:
#  - a powered Attractor (facing east) must pull the cow in its front run west
#    (its x falls by > 0.4 at some point in the window);
#  - an unpowered Attractor control on a pillar over a void must not move;
#  - a powered Pusher must move its cow the other way (east, into a wall);
#  - a cow outside the signal-15 run (x=20, run is x=1..15) must not move;
#  - box membership (upstream's AABB): a cow whose feet are one block below the
#    run plane (y=64, body reaching into y=65) is pulled, while a cow two blocks
#    down (y=63, box top 64.4) is not — the differential that fails a feet-cell
#    test;
#  - COUNTERFACTUAL=1 leaves the Attractor unpowered and turns that assertion
#    into "the cow stays" (same pillar, same cow, same release);
#  - placement: a player places an Attractor from each side and the block must
#    keep the facing toward the placer, not the template's default north;
#  - the placed facing drives the push: an east-facing Attractor pulls a cow
#    west and a west-facing one on the same cell pulls a cow east;
#  - NEGATIVE=1 skips the player placement and writes facing=north instead, so
#    the same push assertion must fail (proof the scenario can fail).
#
# Harness facts learned in-game at this pin (c9d474d...):
#  - `NoAI:1b` is not usable for the moving cow: Horizon skips `ai_step`
#    entirely, so a NoAI mob has no gravity and no velocity integration (a
#    cow summoned at y=68 floats). It holds the cow still before power-on,
#    then `/data merge entity {NoAI:0b}` releases it with the power already on.
#  - Idle AI cows stroll. The control/outside cows stand on 1x1 pillars over a
#    deep void (no valid stroll destination), so their x stays fixed.
#  - The volume is a feet-cell test in the block's own y plane, so the movers,
#    the pillars' top faces and the cows' feet are all at y=65.
#  - The pulled cow is dragged off the pillar into a catch pit; AI may wander
#    once it lands, so the assertion uses the minimum x over the window.
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/restrictions
# The control binary is shared at the campaign pin; the game is this port's build.
CTL=${CTL:-$CLONE/ports/_shared/bin/horizon-1d63e0a5/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
RES=${RES:-${HORIZON_RES:-${HORIZON_RES:-$HOME/.local/horizon-client/26.3}}}
SOCK=${SOCK:-/tmp/opencode/restrictions-e2e.sock}
COUNTERFACTUAL=${COUNTERFACTUAL:-0}
NEGATIVE=${NEGATIVE:-0}
# SELFTEST=1 keeps the powered run but asserts the attractor did NOT pull, so
# the run must fail: the counterfactual proving the pull assertion can fail.
SELFTEST=${SELFTEST:-0}
# EMBEDDED=1 (the default) launches with **only the native bundle** and no
# `--dev-mod`: the content comes from the bundle's embedded copy
# (`mixins/restrictions/data/…`, the AE2 pattern). CONTROL=1 (default with
# EMBEDDED) first launches the same binary with `.horizon-cache` unusable, where
# the block ids must be unknown.
EMBEDDED=${EMBEDDED:-1}
CONTROL=${CONTROL:-$EMBEDDED}
DEV_MOD=()
[ "$EMBEDDED" = 1 ] || DEV_MOD=(--dev-mod "$PORT/content")

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/restrictions-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
cow_at() { # cow_at Z: the cow nearest z=Z (the four lanes are 5 apart)
    ctl entities 40 cow \
        | jq -r --argjson z "$1" '[.entities[] | select(.type == "minecraft:cow")] | sort_by((.pos[2] - $z) | fabs) | .[0].id'
}
cow_x() { # cow_x ID
    ctl entities 40 cow | jq -r --argjson id "$1" '.entities[] | select(.id == $id) | .pos[0]'
}
need() { # need VALUE WHAT
    [ -n "$1" ] && [ "$1" != "null" ] || { echo "FAIL: missing $2" >&2; ctl logs --lines 40 >&2 || true; exit 1; }
}
# min/max accumulators
acc() { awk -v min="$1" -v max="$2" -v x="$3" 'BEGIN { print (x < min) ? x : min, (x > max) ? x : max }'; }

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    rm -rf "$SCRATCH" 2>/dev/null || true
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
# The game flushes after `quit`; let it leave before removing the scratch home.
finish() {
    ctl quit >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        rm -rf "$SCRATCH" 2>/dev/null && return 0
        sleep 0.5
    done
    return 0
}
trap cleanup EXIT

launch() { # launch WORLD
    rm -f "$SOCK"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$1" --seed 20261102 --creative --headless --wait \
        --resources "$RES" "${DEV_MOD[@]}" >/dev/null
    ctl wait-ready 120
    ctl command "execute in minecraft:the_end run tp @s 0 65 -6"
    ctl wait 10
    ctl command "execute in minecraft:the_end run fill -8 63 -8 24 63 20 minecraft:stone"
    ctl command "execute in minecraft:the_end run fill -8 64 -8 24 72 20 minecraft:air"
    ctl command "execute in minecraft:the_end run kill @e[type=!player]"
}

# The control for EMBEDDED=1: the same binary (every hook is in it) with the
# embedded content made unavailable — `.horizon-cache` is a plain file, so the
# helper can neither compare nor write its content file and falls back to
# `Continue`. The block ids must then be unknown; if they resolve, the run proves
# nothing about the embedded file.
control_leg() {
    echo "== control: the same game with no embedded content file =="
    mkdir -p "$SCRATCH"
    rm -rf "$SCRATCH/.horizon-cache"
    : > "$SCRATCH/.horizon-cache"
    launch RestrictionsControl
    ctl command "execute in minecraft:the_end run setblock 0 66 0 restrictions:attractor" >/dev/null 2>&1 || true
    ctl wait 4
    local name
    name=$(ctl block 0 66 0 | jq -r '.block // "unknown"')
    [ "$name" = "minecraft:air" ] || { echo "FAIL: the control game holds $name, so the block id was known" >&2; exit 1; }
    [ -f "$SCRATCH/.horizon-cache" ] || { echo "FAIL: the control's .horizon-cache was replaced: the helper wrote its content" >&2; exit 1; }
    echo "  without the embedded file: the attractor block stayed $name"
    ctl quit >/dev/null 2>&1 || true
    rm -f "$SCRATCH/.horizon-cache"
}

# EMBEDDED=1: the bundle must have written its content out at startup, byte for
# byte the delivered content mod.
embedded_content_check() {
    local cache=$SCRATCH/.horizon-cache/restrictions-embedded-content.hmod
    [ -f "$cache" ] || { echo "FAIL: the bundle did not write its embedded content to $cache" >&2; exit 1; }
    cmp -s "$cache" "$PORT/content/restrictions.hmod" \
        || { echo "FAIL: the embedded content differs from content/restrictions.hmod" >&2; exit 1; }
    echo "  embedded content: $(wc -c < "$cache" | tr -d ' ') B at $cache, identical to content/restrictions.hmod"
}

echo "== launch in The End =="
cd "$SCRATCH"
if [ "$CONTROL" = 1 ]; then control_leg; fi
if [ "$EMBEDDED" = 1 ]; then
    echo "== one .hnmod, no --dev-mod =="
else
    echo "== content --dev-mod content/ =="
fi
launch RestrictionsE2E
if [ "$EMBEDDED" = 1 ]; then embedded_content_check; fi

echo "== attractor facing east at 0,65,0; pusher at 0,65,5; pillars at x=3 (z 0,10) and x=20 (z 16) =="
# Pull lane: a catch floor only when powered; the pillar stands over it.
if [ "$COUNTERFACTUAL" = 0 ]; then
    ctl command "execute in minecraft:the_end run fill 1 58 -2 6 58 2 minecraft:stone"
fi
ctl command "execute in minecraft:the_end run fill 1 59 -2 6 64 2 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 3 64 0 minecraft:stone"
# Control / outside: 1x1 pillars over a deep void (no stroll destination).
ctl command "execute in minecraft:the_end run fill 1 30 8 6 64 12 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 3 64 10 minecraft:stone"
ctl command "execute in minecraft:the_end run fill 18 30 14 22 64 18 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 20 64 16 minecraft:stone"
# Pusher platform and catch wall.
ctl command "execute in minecraft:the_end run fill 1 64 3 11 64 7 minecraft:stone"
ctl command "execute in minecraft:the_end run fill 12 65 2 12 66 8 minecraft:stone"

# Box-membership lanes (z=22 and z=28), both attractors powered, both cows
# held NoAI until the power is on, only their y differs:
#  - Below: feet at y=64, one block under the run plane (y=65). The body
#    reaches into the run, so upstream's AABB intersection must pull it; a
#    feet-cell test would not. 1x1 pillar over a catch pit, as the pull lane.
#  - Under: feet at y=63, two blocks down (box tops out at 64.4). Must not move.
ctl command "execute in minecraft:the_end run fill 1 57 20 6 57 24 minecraft:stone"
ctl command "execute in minecraft:the_end run fill 1 58 20 6 64 24 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 3 63 22 minecraft:stone"
ctl command "execute in minecraft:the_end run fill 1 30 26 6 64 30 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 3 62 28 minecraft:stone"

ctl command "execute in minecraft:the_end run setblock 0 65 0 restrictions:attractor[facing=east]"
ctl command "execute in minecraft:the_end run setblock 0 65 5 restrictions:pusher[facing=east]"
ctl command "execute in minecraft:the_end run setblock 0 65 10 restrictions:attractor[facing=east]"
ctl command "execute in minecraft:the_end run setblock 0 65 16 restrictions:attractor[facing=east]"
ctl command "execute in minecraft:the_end run setblock 0 65 22 restrictions:attractor[facing=east]"
ctl command "execute in minecraft:the_end run setblock 0 65 28 restrictions:attractor[facing=east]"

# PullMe and PushMe are held NoAI so they cannot stroll before the power is on
# (a cow that walks off the pusher platform's west edge falls to the y=63 floor
# and leaves the run plane, which no push can then reach).
ctl command "execute in minecraft:the_end run summon minecraft:cow 3.5 65 0.5 {NoAI:1b,Tags:[\"pull\"]}"
ctl command "execute in minecraft:the_end run summon minecraft:cow 3.5 65 5.5 {NoAI:1b,Tags:[\"push\"]}"
ctl command "execute in minecraft:the_end run summon minecraft:cow 3.5 65 10.5"
ctl command "execute in minecraft:the_end run summon minecraft:cow 20.5 65 16.5"
ctl command "execute in minecraft:the_end run summon minecraft:cow 3.5 64 22.5 {NoAI:1b,Tags:[\"below\"]}"
ctl command "execute in minecraft:the_end run summon minecraft:cow 3.5 63 28.5 {NoAI:1b,Tags:[\"under\"]}"
ctl wait 5

pull_id=$(cow_at 0.5); need "$pull_id" "PullMe"
push_id=$(cow_at 5.5); need "$push_id" "PushMe"
control_id=$(cow_at 10.5); need "$control_id" "Control"
outside_id=$(cow_at 16.5); need "$outside_id" "Outside"
below_id=$(cow_at 22.5); need "$below_id" "Below"
under_id=$(cow_at 28.5); need "$under_id" "Under"
before_pull=$(cow_x "$pull_id"); need "$before_pull" "PullMe x"
before_push=$(cow_x "$push_id"); need "$before_push" "PushMe x"
before_control=$(cow_x "$control_id"); need "$before_control" "Control x"
before_outside=$(cow_x "$outside_id"); need "$before_outside" "Outside x"
before_below=$(cow_x "$below_id"); need "$before_below" "Below x"
before_under=$(cow_x "$under_id"); need "$before_under" "Under x"
echo "before: PullMe=$before_pull Control=$before_control PushMe=$before_push Outside=$before_outside Below=$before_below Under=$before_under"

if [ "$COUNTERFACTUAL" = 0 ]; then
    ctl command "execute in minecraft:the_end run setblock -1 65 0 minecraft:redstone_block"
else
    echo "(counterfactual: the attractor is unpowered)"
fi
ctl command "execute in minecraft:the_end run setblock -1 65 5 minecraft:redstone_block"
ctl command "execute in minecraft:the_end run setblock -1 65 16 minecraft:redstone_block"
ctl command "execute in minecraft:the_end run setblock -1 65 22 minecraft:redstone_block"
ctl command "execute in minecraft:the_end run setblock -1 65 28 minecraft:redstone_block"
ctl command "data merge entity @e[tag=pull,limit=1] {NoAI:0b}"
ctl command "data merge entity @e[tag=push,limit=1] {NoAI:0b}"
ctl command "data merge entity @e[tag=below,limit=1] {NoAI:0b}"
ctl command "data merge entity @e[tag=under,limit=1] {NoAI:0b}"

min_pull=$before_pull; max_pull=$before_pull
max_push=$before_push
min_control=$before_control; max_control=$before_control
min_outside=$before_outside; max_outside=$before_outside
min_below=$before_below; max_below=$before_below
min_under=$before_under; max_under=$before_under
for _ in $(seq 1 12); do
    ctl wait 5
    reply=$(ctl entities 40 cow)
    px=$(jq -r --argjson id "$pull_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    qx=$(jq -r --argjson id "$push_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    cx=$(jq -r --argjson id "$control_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    ox=$(jq -r --argjson id "$outside_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    bx=$(jq -r --argjson id "$below_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    ux=$(jq -r --argjson id "$under_id" '[.entities[] | select(.id == $id) | .pos[0]] | first // ""' <<<"$reply")
    [ -n "$px" ] || { echo "FAIL: PullMe disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    [ -n "$qx" ] || { echo "FAIL: PushMe disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    [ -n "$cx" ] || { echo "FAIL: Control disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    [ -n "$ox" ] || { echo "FAIL: Outside disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    [ -n "$bx" ] || { echo "FAIL: Below disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    [ -n "$ux" ] || { echo "FAIL: Under disappeared during the run" >&2; ctl logs --lines 40 >&2; exit 1; }
    read -r min_pull max_pull < <(acc "$min_pull" "$max_pull" "$px")
    read -r _ max_push < <(acc "$max_push" "$max_push" "$qx")
    read -r min_control max_control < <(acc "$min_control" "$max_control" "$cx")
    read -r min_outside max_outside < <(acc "$min_outside" "$max_outside" "$ox")
    read -r min_below max_below < <(acc "$min_below" "$max_below" "$bx")
    read -r min_under max_under < <(acc "$min_under" "$max_under" "$ux")
done
after_pull=$(cow_x "$pull_id"); after_push=$(cow_x "$push_id")
echo "after:  PullMe=$after_pull Control=${min_control}..${max_control} PushMe=$after_push Outside=${min_outside}..${max_outside}"
echo "box:    Below=${min_below}..${max_below} Under=${min_under}..${max_under}"
echo "pull window: PullMe=${min_pull}..${max_pull}; push max: $max_push"
echo "block:  $(ctl block 0 65 0)"

if [ "$COUNTERFACTUAL" = 0 ] && [ "$SELFTEST" = 1 ]; then
    awk -v before="$before_pull" -v min="$min_pull" 'BEGIN { exit !((before - min) < 0.1) }' \
        || { echo "FAIL: selftest: the powered attractor's pull is asserted absent (before=$before_pull min=$min_pull)" >&2; ctl logs --lines 40 >&2; exit 1; }
    echo "SELFTEST PASS (unreachable: the flipped assertion above must fail)"
    exit 1
elif [ "$COUNTERFACTUAL" = 0 ]; then
    awk -v before="$before_pull" -v min="$min_pull" 'BEGIN { exit !(before - min > 0.4) }' \
        || { echo "FAIL: the powered attractor did not pull the cow (before=$before_pull min=$min_pull)" >&2; ctl logs --lines 40 >&2; exit 1; }
else
    awk -v before="$before_pull" -v min="$min_pull" -v max="$max_pull" 'BEGIN { exit !((before - min) < 0.1 && (max - before) < 0.1) }' \
        || { echo "FAIL: the unpowered attractor moved the cow (before=$before_pull window=$min_pull..$max_pull)" >&2; ctl logs --lines 40 >&2; exit 1; }
    finish
    echo "COUNTERFACTUAL PASS: the unpowered attractor left the cow in place"
    exit 0
fi

awk -v before="$before_control" -v min="$min_control" -v max="$max_control" 'BEGIN { exit !((before - min) < 0.2 && (max - before) < 0.2) }' \
    || { echo "FAIL: the control cow (unpowered attractor) moved (before=$before_control window=$min_control..$max_control)" >&2; ctl logs --lines 40 >&2; exit 1; }
awk -v before="$before_push" -v max="$max_push" 'BEGIN { exit !(max - before > 0.4) }' \
    || { echo "FAIL: the pusher did not push the cow away (before=$before_push max=$max_push)" >&2; ctl logs --lines 40 >&2; exit 1; }
awk -v before="$before_outside" -v min="$min_outside" -v max="$max_outside" 'BEGIN { exit !((before - min) < 0.2 && (max - before) < 0.2) }' \
    || { echo "FAIL: the cow outside the run moved (before=$before_outside window=$min_outside..$max_outside)" >&2; ctl logs --lines 40 >&2; exit 1; }
# Upstream intersects the entity's box with the run: a cow whose feet are one
# block below the run plane is still pulled (its body reaches into the run),
# while a cow two blocks down (box top 64.4) is not. Same power, same facing,
# same NoAI release: only the y differs, so a feet-cell test fails the first.
awk -v before="$before_below" -v min="$min_below" 'BEGIN { exit !(before - min > 0.4) }' \
    || { echo "FAIL: the cow one block below the run was not pulled (before=$before_below window=$min_below..$max_below)" >&2; ctl logs --lines 40 >&2; exit 1; }
awk -v before="$before_under" -v min="$min_under" -v max="$max_under" 'BEGIN { exit !((before - min) < 0.2 && (max - before) < 0.2) }' \
    || { echo "FAIL: the cow two blocks below the run moved (before=$before_under window=$min_under..$max_under)" >&2; ctl logs --lines 40 >&2; exit 1; }

echo "== placement: the block keeps the placer's horizontal facing =="
# A wide floor south of the push lanes. The player stands on the side the
# block must face; `place` aims at the floor block under the target, so the
# placement yaw is the player-to-target direction and the block faces the
# player (upstream `OrientationTools.getFacingFromEntity`'s fallback).
ctl command "execute in minecraft:the_end run fill -12 63 24 24 63 44 minecraft:stone"
ctl command "execute in minecraft:the_end run fill -12 64 24 24 72 44 minecraft:air"
ctl command "execute in minecraft:the_end run kill @e[type=minecraft:cow]"
# The push lane at z=36 is a 1x1 rig over a catch floor: the cow cannot stroll
# to mask the pull, and the placed block still sits on its own support. The
# table placements at z=30 stay on the wide floor.
ctl command "execute in minecraft:the_end run fill -8 58 34 8 58 38 minecraft:stone"
ctl command "execute in minecraft:the_end run fill -8 59 34 8 64 38 minecraft:air"
ctl command "execute in minecraft:the_end run setblock 0 63 36 minecraft:stone"
ctl command "execute in minecraft:the_end run setblock 2 63 36 minecraft:stone"
ctl command "execute in minecraft:the_end run setblock -3 63 36 minecraft:stone"
ctl command "clear @s"
ctl command "give @s restrictions:attractor 64"

place_at() { # place_at X Z PLAYER_X PLAYER_Z WANT
    local tx=$1 tz=$2 px=$3 pz=$4 want=$5 reply got
    ctl tp "$px" 64 "$pz"
    # `ctl place` aims the client, but the placement hook reads the server's
    # player yaw: aim at the support face under the target and let a few ticks
    # carry that rotation to the server before clicking (the allthetweaks
    # placement e2e's proven sequence).
    ctl look-at-block "$tx" 63 "$tz" up >/dev/null \
        || { echo "FAIL: cannot look at the support under $tx,63,$tz" >&2; ctl logs --lines 40 >&2; exit 1; }
    ctl wait 6
    if [ "$NEGATIVE" = 0 ]; then
        reply=$(ctl place "$tx" 64 "$tz" --item restrictions:attractor 2>&1) \
            || { echo "FAIL: place $tx 64 $tz from ($px,$pz): $reply" >&2; ctl logs --lines 40 >&2; exit 1; }
        ctl wait 3
    else
        # Counterfactual: the template's default facing, as placement left it
        # before this gap was closed. The exact-state check is skipped so the
        # push assertion below is the one that has to fail.
        ctl command "execute in minecraft:the_end run setblock $tx 64 $tz restrictions:attractor[facing=north]"
    fi
    got=$(ctl block "$tx" 64 "$tz" | jq -r '.state // ""')
    echo "  placed ($tx,64,$tz) from ($px,$pz): $got (want facing=$want)"
    if [ "$NEGATIVE" = 0 ]; then
        [ "$got" = "restrictions:attractor[facing=$want]" ] \
            || { echo "FAIL: placement facing $got, want facing=$want" >&2; ctl logs --lines 40 >&2; exit 1; }
    fi
}

pull_with() { # pull_with PLAYER_X WANT COW_X POWER_X
    local px=$1 want=$2 cowx=$3 powerx=$4 id before x min max
    place_at 0 36 "$px" 36.5 "$want"
    ctl command "execute in minecraft:the_end run setblock $powerx 64 36 minecraft:redstone_block"
    ctl tp 0 64 43
    ctl wait 2
    ctl command "execute in minecraft:the_end run summon minecraft:cow $cowx 64 36.5 {NoAI:1b}"
    ctl wait 5
    id=$(cow_at 36.5); need "$id" "placement cow"
    before=$(cow_x "$id"); need "$before" "placement cow x"
    ctl command "data merge entity @e[type=minecraft:cow,limit=1] {NoAI:0b}"
    min=$before; max=$before
    for _ in $(seq 1 12); do
        ctl wait 5
        x=$(cow_x "$id")
        [ -n "$x" ] || { echo "FAIL: placement cow disappeared" >&2; ctl logs --lines 40 >&2; exit 1; }
        read -r min max < <(acc "$min" "$max" "$x")
    done
    echo "  pull facing=$want: cow x $before -> ${min}..${max}"
    if [ "$want" = east ]; then
        awk -v before="$before" -v min="$min" 'BEGIN { exit !(before - min > 0.4) }' \
            || { echo "FAIL: the east-facing attractor did not pull the cow west (before=$before min=$min)" >&2; ctl logs --lines 40 >&2; exit 1; }
    else
        awk -v before="$before" -v max="$max" 'BEGIN { exit !(max - before > 0.4) }' \
            || { echo "FAIL: the west-facing attractor did not pull the cow east (before=$before max=$max)" >&2; ctl logs --lines 40 >&2; exit 1; }
    fi
    ctl command "execute in minecraft:the_end run kill @e[type=minecraft:cow]"
    ctl command "execute in minecraft:the_end run setblock $powerx 64 36 minecraft:air"
    ctl command "execute in minecraft:the_end run setblock 0 64 36 minecraft:air"
    ctl wait 2
}

# Same cell, opposite placed facings: the cows are pulled in opposite world
# directions. With the default facing=north neither cow is in the front run.
pull_with 2.5 east 2.5 -1
pull_with -2.5 west -2.5 1

# Read the facing back for all four horizontal placements.
place_at 0 30 0.5 32.5 south
place_at 6 30 6.5 27.5 north
place_at 12 30 14.5 30.5 east
place_at 18 30 15.5 30.5 west

finish
echo "PASS: powered attractor pulled, unpowered stayed, pusher pushed away, outside control stayed; the box test pulled the cow one block below the run and left the one two blocks below; placement facings kept and the placed facing drove the pull"
