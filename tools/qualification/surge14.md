> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 14 complete inventory and frozen-source run

Run this recipe from the actual coordinator repository after committing the
task-owned inputs. Preserve unrelated untracked user work.

```sh
python3 tools/qualification/surge14.py \
	--build <historical-private-path> \
	--output <historical-private-path>
```

This discovers every actual Meson registration and binds A01–A132 to exact
committed application source hashes and recipe names. The inventory records
the build configuration and verifies its source routing. It includes the
multi-profile A101 host/guest routes and the A92 policy recipe; an application
is counted once regardless of variant or number of companion sources.

Build every target first with ordinary `meson compile -C BUILD -j8`. The complete
Linux profile selects `hosted_concurrency=true`, `linux_async=true` and the
existing liburing 2.15 `pkg_config_path`. Host test binaries may use
`debug=false`; this does not disable public Astra `-g`/DWARF qualification.
For a full replay, select `-Dstage0_optimization=3` and
`-Dnumeric_oracle_optimization=3` before rebuilding. These optimize only the
compiler implementation and the two exhaustive exact-number executables, as in
a production build; they change no cases, assertions or public Astra program
optimization route. Both options default to `inherit` for ordinary development.
Standalone IR model targets remain on the configured O0 profile, including the
normal-stack nesting and malformed-model controls.

Standalone Vala model subsets currently produce unused-internal-member warnings,
so the full registry profile uses `werror=false` and retains those warnings.
Independent production release builds separately require `werror=true`.

Add `--run --jobs 4` for one ordinary complete foreground Meson run, without
implicit rebuilding. The recipe snapshots every tracked source hash and HEAD,
the compiler and registry before execution; all must remain unchanged. It
retains exact names, commands, process results and raw Meson logs under a new
external attempt directory. Missing, duplicate, unexpected, failed or skipped
registrations and TAP skips prevent automatic registry qualification. Unsupported optional cases need
individual review and evidence; the script never silently converts a skip.

The inventory also reconciles portable feature/selection manifests to actual
registered names. The additional required safety/cost recipes are explicitly
listed in `surge14-auxiliary.json`; old receipt collectors and profile-reconfiguring
selection wrappers are not extra execution credit. Add `--auxiliary
--installed-prefix PREFIX --liburing-prefix EXISTING_PREFIX` to execute the catalog
serially after a fully passing registry. These include controlled same-O2
ablations, scalar/vector machine code, ASan/UBSan/TSan, independent heap and
worker stress, real liburing timer continuity, guest footprint/Callgrind and
concurrency resource costs. Actual result receipts, compiler hashes and source
conservation are checked. Build products stay in the external build tree.

Historical recipes that require absent output directories select an exclusive
child attempt through `output_paths.py` at their normal CLI entry point. Existing
files and earlier attempts remain untouched. `.astra-current-output.json` selects
a path; it does not assert success. Dependent memory/cost recipes resolve that
selection with `current_output()`. Inspect the selected run's own receipts and
current compiler identity before using its artifacts. A failed attempt remains
visible and cannot borrow an earlier successful receipt.

A complete registry result qualifies only that run. The manifest separately
lists native Windows A123–A125, actual VS Code A130 and final installed release
A129/A132 requirements. Execute and bind those external receipts explicitly;
`REGISTRY_AND_AUXILIARY_PASS_EXTERNAL_GATES_PENDING` is not a Surge 14 campaign PASS. The
canonical report and developer release candidate require all remaining gates.
