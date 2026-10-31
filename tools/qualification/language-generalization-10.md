> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Language generalization Surge 10 component qualification

Final result: 119/119 selected registrations at `d439d0d`, all twelve applications,
real timer continuity and verified source/product conservation. See
validation and
compact evidence.

The final integrated recipe selects the explicit maintained list in
`tests/language-generalization-10/integration-tests.json` (119 actual Meson
registrations, including all twelve applications). Its prerequisite build list
is `integration-targets.json`, derived from the real registration/dependency
inventory plus the existing numeric oracle prerequisites. Use normal Meson
commands; keep one build at a time and start tests only after a successful build.

```sh
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson setup --reconfigure <historical-private-path> <historical-private-path> -Dwerror=true
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
targets = json.loads(Path('tests/language-generalization-10/integration-targets.json').read_text())
raise SystemExit(subprocess.call(['meson', 'compile', '-C', '<historical-private-path>', '-j4', *targets], env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')))
PY
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
names = json.loads(Path('tests/language-generalization-10/integration-tests.json').read_text())
raise SystemExit(subprocess.call(['meson', 'test', '-C', '<historical-private-path>', '--no-rebuild', '--num-processes', '2', '--print-errorlogs', '--logbase', 'surge-10-final', *names], env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')))
PY
PYTHONDONTWRITEBYTECODE=1 python3 tests/interop-async-5/timer-check.py <historical-private-path> <historical-private-path>
```

The timer recipe builds the actual installed private liburing provider explicitly,
leaving the coordinator's default `linux_async=false` intact. No missing-provider
or return-77 result counts as PASS. A79's cooperative execution is a separate
claim. The selected C sanitizer recipe instruments actual Resource/POSIX adapters;
it does not claim instrumentation of generated Astra LLVM or system libraries.

Current application behavior, negative controls and individual command counts
are in the [corpus guide](../../examples/language-generalization-10/README.md).
The final integrated result, compiler/tool/source/product identities and Bible
scope belong in the campaign validation/evidence files. The component notes
below retain chronological intermediate scope and counts; they do not override
the final source or promote an earlier component run into whole-campaign PASS.

For the recorded native intake, `tests/language-generalization-10/evidence.py`
verifies the saved `g9-final-{build,test,timer}-command.json`, source index and
fresh raw receipts before writing the compact evidence. It performs no build,
commit or publication. Source/product or result drift is an error, and absent
empty Meson output fields normalize to empty output. Full command transcripts
remain under the external build/runtime directories; the compact artifact keeps
their hashes plus native input/output/exit observations and typed proof results.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/language-generalization-10/evidence.py <historical-private-path> <historical-private-path> docs/language-generalization-10-evidence.json
```

At the initial unfinished component stage, this recipe qualified copied sequences, stateful
iterators and recursive Resource/native Class/buffer record locals, including
explicit field take/replacement, Resource/Class/buffer MOVE_VALUE boundaries and
exact Resource/Class/owning-record enum payloads, including an owned UTF-8
snapshot with its input byte storage.
Use the existing coordinator-routed Meson
directory and preserve peer work and all previous products.

```sh
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson setup --reconfigure <historical-private-path> <historical-private-path> -Dwerror=true
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson compile -C <historical-private-path> -j 4 astrac astra-sequence-contracts astra-aggregate-contracts astra-enum-scalar-contracts astra-owned-state-proof
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson test -C <historical-private-path> --no-rebuild --num-processes 2 --print-errorlogs --logbase surge-10-components language-generalization-10-sequence-contracts language-generalization-10-sequence language-generalization-10-aggregate-contracts language-generalization-10-enum-contracts language-generalization-10-aggregate owned-state-6-proof struct-move-1-native-execution
```

The public fixtures run at O0/O1/O2 and under unsuppressed Valgrind. The driver
records exact commands, expected/actual exits, output, compiler/source/product
hashes and memory output in unique directories beneath the external test build
directory. The TAP proof independently corrupts and restores stage contracts.
The `enum-own-core`, `enum-own-cfg`, `enum-own-ssa` and `enum-own-native` targets
also build and test their models without upstream builders. Rebuild these
targets before including their results in a current-source selection.
These tests do not claim completion of G1–G9, A73–A84, async iteration or a full
historical regression sweep. Current campaign progress is in the
working ledger.

The ordinary checked generic-body component has its own focused selection:

```sh
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson compile -C <historical-private-path> -j 4 astrac astra-generic-body-contracts astra-gen-member-contracts
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson test -C <historical-private-path> --no-rebuild --num-processes 2 --print-errorlogs --logbase surge-10-general-generic-bodies-final language-generalization-10-generic-contracts language-generalization-10-generic gen-member-1a-contracts gen-member-1a-native-execution gen-member-1a-source-refusals
```

The public generic suite also qualifies the shared Vector declaration with
Class and Resource specializations. Build `astra-enum-own-native` and include
`enum-own-native` and `language-generalization-10-aggregate` for the Resource
component's selected native/record compatibility fence. Owning record element storage
and complete G2 remain open.

The record element component uses that same generic public suite and proof
target. Also build `astra-enum-own-core`, `astra-enum-own-cfg`,
`astra-enum-own-ssa`, `astra-enum-own-native` and include their four matching
`enum-own-*` tests in the selected regression fence. The current generic suite
checks copied record, exact Resource and unique Class element specializations;
generic method type parameters and broader G2 composition remain open.


The explicit generic-method component is qualified with the same selected
current-source stage binaries. `surge-10-generic-method-closed` selects ten suites:
`language-generalization-10-generic-contracts`, `language-generalization-10-generic`,
`language-generalization-10-aggregate`, the three `gen-member-1a` suites and all four
`enum-own-{core,cfg,ssa,native}` builder-free suites. Build `astrac`,
`astra-generic-body-contracts`, `astra-gen-member-contracts` and the four
`astra-enum-own-{core,cfg,ssa,native}` targets before this selection. The method
source is part of the public harness; its Resource observer uses the existing
strict C build. Current harness receipts include actual compiler/source/product
hashes and exact command output.


`surge-10-container-iteration-checked-closed` selects the two sequence suites,
the two generic suites, the aggregate public suite and all three historical
`gen-member-1a` suites. Build `astrac`, `astra-sequence-contracts`,
`astra-generic-body-contracts` and `astra-gen-member-contracts` first. The sequence
harness compiles both strict C observers and tests the container fixture at all
public dump stages, O0/O1/O2 and unsuppressed Valgrind. Its hashed receipts include
103 actual commands; nine sequence TAP proofs include the new independently
corrupted Checked/Core/CFG/SSA snapshot and consumption authorities.


`surge-10-owning-record-container-closed` runs the prior eight container-iteration
suites plus `enum-own-core`, `enum-own-cfg`, `enum-own-ssa`, `enum-own-native` and
`enum-own-llvm`. In addition to those earlier targets, rebuild
`astra-enum-own-{core,cfg,ssa,native,llvm}` for the shared cleanup change.
The generic harness now records 166 commands and its TAP target has six proofs.
This is a qualified owning-element component, not full G1–G9/A73–A84 acceptance.


`surge-10-generic-owner-boundaries-closed` uses the same thirteen-name selection
and current-source targets as the owning-record container component. The generic
harness records 198 commands and the generic contract target has seven TAP
proofs. The native-only enum fixture also carries detached generic owner channel
binding/erasure/restoration controls without a predecessor compiler graph.


`surge-10-generic-nested-closed-restored` uses the same thirteen-suite selection
and targets. It records 234 generic commands and nine generic TAP proofs;
the native-only fixture has four TAP proofs, including a separately authored
record/slot ownership graph. The preceding non-restored selection failed that
fixture's declaration rank check; the restored receipt follows its correction.
All public nested programs execute at O0/O1/O2 with unsuppressed Valgrind.


The child/cache selection `surge-10-generic-child-cache-closed-restored` adds
`language-generalization-10-properties`, `owned-state-6-proof`,
`owned-state-6-runtime` and `owned-state-6-refusals` to the thirteen prior suites.
Build `astra-owned-state-proof` with the earlier targets. The property harness
records 81 commands; the generic contract target has eleven TAP proofs, including
cache disarm and async frame acquisition/retirement controls after predecessor
release. The public async witness links the existing explicit
`lib/astra/async-virtual.o` provider, whose hash is recorded in its receipt.


`surge-10-nonnull-composition-closed` extends the seventeen-suite child/cache
selection with `language-generalization-10-nonnull`, all five
`language-usability-7-nonnull-{source,core,cfg,ssa,field}-contracts` and
`language-usability-7-nonnull`. Rebuild the matching five
`astra-nonnull-{source,core,cfg,ssa,field}-contracts` targets and all prior affected
stage fixtures first. The new suite records 122 commands with per-command input
hashes; the generic proof target has thirteen TAP proofs. Ordinary moved-owner
use is rejected at CFG liveness, and the raw Core dump is not counted as that
check. Physical parity compiles the same temporary file with contract tokens
replaced by equal-width spaces; async NABI source instruction positions are the
only normalized metadata. CABI and raw LLVM are compared exactly.


For descriptor work, build `astrac` and `astra-descriptor-contracts` after Meson
reconfiguration. `surge-10-descriptor-controls` selects
`language-generalization-10-descriptors`,
`language-generalization-10-descriptor-contracts` and the seven `cli-*` smoke
tests. `surge-10-descriptor-closed-restored` selects the two descriptor suites,
`language-usability-7-formatter` and `ecosystem-abi-8-modules`. The public
descriptor harness records 88 commands with compiler, source and product hashes,
including O0/O1/O2, unsuppressed Valgrind, a metadata-free peer, qualified aliases,
actual FNV-1a/31 collision refusal, forged runtime records and preserved output
on semantic/ownership/CLI failures. The source-only TAP proof releases the
original checked Class/record graph before rebuilding nominal declarations and
checking the generated source. There is no new erased native storage channel.


`surge-10-unicode-closed` selects `language-generalization-10-unicode`,
`language-generalization-10-descriptors`, `language-usability-7-formatter`,
`text-own-1a-native-execution`, `text-own-1b-native-execution`,
`text-own-1b-source-refusals` and `language-runtime-3-applications`. The new
Unicode harness records 118 commands: full public checked stages, independent
Python byte/scalar outputs at O0/O1/O2, unsuppressed Valgrind for all success and
parse-failure inputs, malformed counted bytes, embedded NUL, multibyte delimiter,
unchanged owner/snapshot checks and source refusals. It records all selected
library/provider inputs and generated native product hashes. This is G6
component evidence, with no regex provider selected; it does not accept an
integrated A73–A84 application or the final campaign by itself.


`surge-10-generic-properties-closed` is the 24-suite nonnull composition fence
plus both descriptor suites, Unicode, formatter, aggregate contracts and enum
contracts: 30 suites total. Rebuild the prior stage binaries and
`astra-descriptor-contracts` after the new immutable source/property/native
schema changes. The generic harness now records 268 public commands and 14 TAP
proofs. It includes copied record/Class/owning record property specializations,
fresh computation after growth/take, copied-U composition, public O0/O1/O2,
unsuppressed Valgrind and restored missing/wrong-receiver/cached/native-target
corruptions after explicit predecessor release. Vala builder/monomorphizer
intermediates are separately named and cleared before weak-reference checks.


The owning-record unit component builds `astrac` and `astra-native-module-proof`.
`surge-10-record-units-closed` selects
`language-generalization-10-record-units`, `ecosystem-abi-8-module-proof`,
`ecosystem-abi-8-modules`, `language-generalization-10-{aggregate,generic,properties,descriptors,unicode}`
and `language-usability-7-formatter` (nine suites; expand the braces into actual
test names). The record-unit harness records 59 commands and five separately
linked O0/O2 mixed or O1 paired executables, each under unsuppressed Valgrind.
It removes only its own generated producer copy before consumer compilation.
The module proof has three TAP cases, including direct typed lifetime
correspondence corruption/restoration without relying on a metadata digest
failure. Existing public module controls are regenerated against schema 2;
schema-1 historical receipts remain unchanged.


`surge-10-composite-units-closed` adds
`language-generalization-10-generic-units` to the nine record-unit selection names.
Build `astrac` and `astra-native-module-proof`; the module target now has four
TAP proofs. Both unit suites use the shared `unit-record.py` driver with distinct
real sources and oracles. The generic profile records 66 commands, copied and
owning record specializations, absent source, five independent link/execution
combinations, unsuppressed Valgrind, order-independent ABI identities, and
unexported/open/wrong-domain specialization refusals. Its direct correspondence
proof changes the closed argument's move schema while keeping its nominal name
and machine channels, then restores the native/LLVM artifact. All twelve
integrated applications and final same-revision G9 qualification remain required.


`surge-10-applications-a73-a75` selects the three actual registrations
`language-generalization-10-application-a73`, `-a74` and `-a75` (repeat the full
prefix for each name). The shared `apps.py` recipe accepts an explicit app ID and
records `PASS_APPLICATION` only for that app. It currently qualifies 125, 62 and
56 commands respectively: typed public stages, strict genuine C adapters,
O0/O1/O2 runtime input/oracle cases, unsuppressed Valgrind and semantic refusal
controls. A73 includes all partial initialization counts and a fully initialized
checked-failure path. A74 covers failed enum replacement and exact active-case
cleanup. A75 covers all three generic element domains, computed properties,
copied-U composition and relocation refusal while an element loan is active.
Nine further applications and final campaign qualification remain mandatory.
