#!/usr/bin/env python3
"""Craft every carried Restrictions recipe in a real crafting table.

The recipes are read **out of the delivered `.hmod`**, not copied here, so the
check cannot drift from the data the package ships. Called by `tools/e2e.sh`
with the open game's control socket and the position of a placed crafting table
(`python3 tools/craft_recipes.py SOCK CTL X Y Z [PACKAGE]`).

The harness's table screen is a 3x3 grid at slots 100..108 (row-major) with the
result at 200; the player's own slots keep their inventory numbers (the hotbar is
0..8). For each `data/restrictions/recipe/*.json` of type `crafting_shaped`:

1. the declared pattern, at the grid position it declares, makes exactly one of
   its result item — the id and the count are asserted, so a recipe that loses
   its result or its count fails here;
2. every ingredient is consumed (its inventory count is 0 afterwards) and the
   grid is empty;
3. the crafted item is in the inventory and can be read back by id.

A `#tag` ingredient is resolved to one concrete vanilla item by TAG_ITEMS; a tag
this table does not know fails the run rather than being skipped, so a new tag in
the carried data cannot become untested by accident.

`SELFTEST=1` expects the second recipe's result for the first pattern, so the run
MUST exit 1: it is the proof these assertions can fail.

Exit 1 with the observed result on the first mismatch.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import zipfile

SELFTEST = os.environ.get("SELFTEST") == "1"

GRID = {
    (0, 0): 100, (0, 1): 101, (0, 2): 102,
    (1, 0): 103, (1, 1): 104, (1, 2): 105,
    (2, 0): 106, (2, 1): 107, (2, 2): 108,
}
RESULT = 200
HOTBAR = 0

# The `c:` tags the carried recipes name, resolved to a vanilla item that is in
# them. An unknown tag is a failure, never a skip.
TAG_ITEMS = {
    "#c:glass_blocks": "minecraft:glass",
    "#c:glass_panes": "minecraft:glass_pane",
    "#c:slimeballs": "minecraft:slime_ball",
}


def recipes(package: str) -> list[dict]:
    """The shaped recipes the package carries, in file order."""
    out = []
    with zipfile.ZipFile(package) as jar:
        for name in sorted(jar.namelist()):
            if not (name.startswith("data/restrictions/recipe/") and name.endswith(".json")):
                continue
            recipe = json.loads(jar.read(name))
            if recipe.get("type") != "minecraft:crafting_shaped":
                raise SystemExit(f"FAIL: {name} is {recipe.get('type')!r}: this check crafts shaped recipes only")
            out.append({"name": name.rsplit("/", 1)[-1], **recipe})
    if not out:
        raise SystemExit(f"FAIL: {package} carries no data/restrictions/recipe/*.json")
    return out


def item_of(entry: str) -> str:
    if entry.startswith("#"):
        try:
            return TAG_ITEMS[entry]
        except KeyError:
            raise SystemExit(f"FAIL: no concrete item is mapped for the recipe tag {entry}") from None
    return entry


def layout(recipe: dict) -> tuple[list[tuple[int, str]], dict[str, int]]:
    """The (slot, item) placements and how many of each item the pattern needs.

    The grid position is the pattern's own: vanilla matches a shaped recipe with
    the pattern's spaces included, so an empty first row (glass boots) must stay
    empty in the grid.
    """
    slots: list[tuple[int, str]] = []
    need: dict[str, int] = {}
    pattern = recipe["pattern"]
    if len(pattern) > 3 or any(len(row) > 3 for row in pattern):
        raise SystemExit(f"FAIL: {recipe['name']}: pattern {pattern} does not fit a 3x3 table")
    key = {char: item_of(entry) for char, entry in recipe["key"].items()}
    for row, line in enumerate(pattern):
        for col, char in enumerate(line):
            if char == " ":
                continue
            if char not in key:
                raise SystemExit(f"FAIL: {recipe['name']}: pattern char {char!r} has no key entry")
            item = key[char]
            slots.append((GRID[(row, col)], item))
            need[item] = need.get(item, 0) + 1
    return slots, need


def main() -> int:
    sock, ctl, x, y, z = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
    package = sys.argv[6] if len(sys.argv) > 6 else "restrictions.hmod"
    x, y, z = int(x), int(y), int(z)
    shipped = recipes(package)
    print(f"recipe check: {len(shipped)} shaped recipes read from {package}")

    def run(*args: str) -> dict:
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"FAIL: ctl {' '.join(args)}: {out.stdout}{out.stderr}") from None

    def wait(ticks: int = 4) -> None:
        run("wait", str(ticks))

    def slots() -> list[dict]:
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"FAIL: no menu is open: {screen}")
        return screen["slots"]

    def count_of(item: str) -> int:
        return run("inventory")["counts"].get(item, 0)

    def find(item: str) -> int:
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"FAIL: missing ingredient {item} (inventory: {run('inventory')['counts']})")

    def result() -> dict | None:
        found = [s for s in slots() if s["slot"] == RESULT]
        if not found or not found[0].get("item"):
            return None
        return found[0]

    def place(item: str, targets: list[int]) -> None:
        """Put one `item` in each target, a stack at a time (an unstackable
        ingredient arrives as several stacks of one)."""
        for target in targets:
            slot = find(item)
            run("click-slot", str(slot))
            wait(1)
            run("click-slot", str(target), "right")
            wait(1)
            run("click-slot", str(slot))
            wait(1)

    def open_table(need: dict[str, int]) -> None:
        try:
            run("close")
        except SystemExit:
            pass
        wait(4)
        run("command", "clear @s")
        for item, count in need.items():
            run("give", item, str(count))
        wait(3)
        reply = run("interact", str(x), str(y), str(z))
        wait(4)
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(
                f"FAIL: the crafting table at {x},{y},{z} did not open: "
                f"interact={json.dumps(reply, sort_keys=True)} screen={json.dumps(screen, sort_keys=True)}")

    def take_result() -> None:
        run("click-slot", str(RESULT))
        wait(1)
        run("click-slot", str(HOTBAR))
        wait(2)

    for index, recipe in enumerate(shipped):
        want = recipe["result"]["id"]
        want_count = recipe["result"].get("count", 1)
        if SELFTEST and index == 0:
            want = shipped[1]["result"]["id"] if len(shipped) > 1 else "minecraft:stick"
            print(f"(selftest: expecting {want} from the {recipe['name']} pattern)")
        placements, need = layout(recipe)
        open_table(need)
        for item in need:
            place(item, [slot for slot, placed in placements if placed == item])
        got = result()
        print(f"  {recipe['name']}: {json.dumps(got, sort_keys=True)}")
        if not got or got.get("item") != want or got.get("count") != want_count:
            raise SystemExit(f"FAIL: {recipe['name']}: expected {want_count} {want}, got {got}")
        take_result()
        made = count_of(recipe["result"]["id"])
        left = {item: count_of(item) for item in need}
        grid = [s for s in slots() if s["slot"] in GRID.values() and s.get("item")]
        print(f"    crafted {made} {recipe['result']['id']}, ingredients left {left}, grid {json.dumps(grid)}")
        if made != want_count:
            raise SystemExit(f"FAIL: {recipe['name']}: the craft left {made} {recipe['result']['id']}, expected {want_count}")
        if any(left.values()):
            raise SystemExit(f"FAIL: {recipe['name']}: ingredients not consumed: {left}")
        if grid:
            raise SystemExit(f"FAIL: {recipe['name']}: the grid still holds {grid}")
    run("close")
    return 0


if __name__ == "__main__":
    sys.exit(main())
