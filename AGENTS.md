# Working on a native Horizon mod (the SDK format since 2026-11-18)

> **This port is a flat SDK package, not a mixins bundle.** `horizon-mod.toml` is the only
> manifest and the only identity; the code is `src/lib.rs` + `src/runtime.rs` + `src/support.rs`,
> the carried content is `assets/` + `data/`, and the build is `cargo horizon-mod build` **run
> directly in this directory**. `build-slot.sh` speaks the retired `tools/horizon.py`, so the slot
> runner does not apply here (see the campaign's `../_shared/HANDOVER.md`); run cargo with
> `CARGO_INCREMENTAL=0` and never pass `--target-dir`.

Read `README.md` and `notes.md` (the migration section and the gap list) before editing; the
retired `compatibility.json`, `mixins/` tree and packaging tools are preserved under
`../_shared/evidence/restrictions/retired-hnmod-0.1.0/`. Keep this repository separate from
Horizon and horizon-mixins, and never modify the original checkout or player resources.

`src/runtime.rs` is the port's pure, unit-tested logic and is **byte-identical** to the
pre-migration file: change it only for a behaviour change, with a test, and record why in
`notes.md`. Game access belongs in `src/support.rs`; numbers belong in `runtime.rs`.

Validate with `cargo fmt --check` (not `--all`: `.horizon/sdk` is a path dependency),
`cargo clippy --all-targets -- -D warnings` and `cargo test`, then `rm -f Cargo.lock` before
`cargo horizon-mod build`, and `cargo horizon-mod check` / `fits` on the delivered `.hmod`.
The in-game scenario is `tools/e2e.sh`; it needs a launcher-built game (`GAME=`/`CTL=`). Keep
validation claims and supported revisions honest.
