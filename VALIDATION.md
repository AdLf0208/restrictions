# Validation

Validated on Linux with Rust 1.95.0 on 2026-10-30, using the exact revisions in
`compatibility.json` and the real bundle committed here.

| Check | Result |
|---|---|
| `cargo fmt --all --check` | Pass |
| `cargo clippy --workspace --all-targets --locked --offline -- -D warnings` | Pass |
| `cargo test --workspace --locked --offline` | Runtime unit test passes |
| `python3 tools/test_template.py` | Actual bundle compiles in the tiny fixture; original method calls/result, shared runtime, AST audit, unchanged bytes/mtimes and incompatible revision/target rejection pass |
| `python3 tools/test_stage.py` | Complete pinned Horizon export stages deterministically; original checkout unchanged; exact HEAD/module audit passes |
| `python3 tools/horizon.py check` | Actual `horizon-client` binary checks successfully with `--no-default-features` |
| `python3 tools/horizon.py test` | The runtime's embedded test passes inside the actual Horizon game test binary |

The native check reported 69.55 seconds in Cargo, and the native test passed.
Both reused an existing external Cargo target directory with cached
Horizon dependencies. These are compilation/test checks, not a fresh-build
benchmark. Staging the full export took about 24 seconds per command on this
machine; a repeated application preserved the stage.

No game was launched and no Minecraft resources or player data were read or
changed. Interactive logging/gameplay remains a manual check with the compatible
prepared resources. The source audit verifies only the declared HEAD statement
and support module differ from pristine Rust ASTs; it does not claim compatibility
with other Horizon revisions or arbitrary third-party mods.

CI reproduces the formatting, clippy, standalone runtime and tiny-fixture tests.
The full native checks additionally need a Horizon Git history containing the
pin and its cached dependencies; use the commands in README.md to reproduce them.

## One-file bundle at `1d63e0a5` (2026-11-10)

The content mod is now carried inside the delivered `.hnmod`
(`mixins/restrictions/data/restrictions-content.hmod`); all steps ran through
`ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0`.

| Check | Result |
|---|---|
| `cargo fmt -- --check` | pass |
| `cargo clippy --all-targets --locked --offline -- -D warnings` | pass, 0 warnings |
| `cargo test --locked --offline` | 13 passed, 0 failed |
| `tools/horizon.py stage/check/test/build` at the pin | `cargo_exit: 0`, 0 warnings, 13 embedded tests, fast build |
| `tools/package.sh` | `content/restrictions.hmod` 19,997 B (54 entries), `restrictions.hnmod` 20,540 B (10 entries) |
| `cargo horizon-mod check restrictions.hnmod --kind native-mod` | exit 0 |
| `EMBEDDED=1 tools/e2e.sh` (control + pull/push/box/placement) | **PASS**, `EXIT:0` |
| `SELFTEST=1 tools/e2e.sh` | **FAIL** (inverted pull assertion), `EXIT:1` |
