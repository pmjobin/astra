# System LLVM packaging, 28-C

The integrated milestone is **PARTIAL**. Fedora 45 has focused packaging,
functional, physical and strict-memory PASS. Ubuntu 26.04 has functional and
physical PASS with an LLVM 22 branch adapter, but strict memory is NOT_PASS.
Both products remain unsigned **DEVELOPMENT_UNQUALIFIED**, named `astrac`.
No new binaries were published and no hosted run was executed for this source.

The exact package revision is `94e3d6b8ce82`; later commits contain qualification
recipes and findings. The canonical report binds full commit/tree identities,
raw resources, package checksums and failed attempts. Build leaves are
`~/Workspace/codex/work/astra/build/28c-system-llvm/{ubuntu4,fedora4}/`;
raw observations are under the matching `runtime/28c-system-llvm/`.
`tools/ci/system-llvm-builders.json` records portable builder setup recipes
against the immutable image lock. The canonical evidence records actual image IDs.

| Target | Distribution dependencies | Product bytes / SHA-256 |
|---|---|---|
| Ubuntu 26.04.1 amd64 | `llvm-22-dev` build, `libllvm22` runtime, both `1:22.1.2-1ubuntu1` | 1,301,768 / `9b47ebda6ff95d11c4ac3ac8e5439c321bf3c39f56e3468c56e05facd9de0c4e` |
| Fedora 45 x86_64 | `llvm-devel` build, `llvm-libs` runtime, both `23.1.5-2.fc45` | 1,352,217 / `35a8a4f73851d2f09fca6b4069178c4efeb15c270795d280191ada188be01d45` |

Both fresh consumer userlands passed O0/O2 compile/link/run, C ABI and five
owning drops, negative diagnostic/output preservation, deterministic docs,
43 installed Guide blocks, ordinary-user execution, missing-library refusal,
docs without LLVM, corruption refusal, same-version repair and uninstall.
Migration used the exact earlier hosted `astra-development` packages, not a
synthetic replacement. APT removed the old DEB; DNF replaced the old RPM.
Their private LLVM directories disappeared. Consumers had no LLVM development
packages or headers and mounted no private LLVM. Containers share the host kernel.

Both native ELF files have the distro LLVM SONAME in DT_NEEDED and no RPATH or
RUNPATH. Actual loader `--list`, `ldd`, ownership queries, native dependency
generators and complete payload inventories are retained. RPM has real LLVM
Requires, without dependency exclusions. DEB dependencies come from the native
compiler through `dpkg-shlibdeps`. The payload audit rejects LLVM copies,
symlinks, private archives and undocumented ELF images. Twelve mutated ELF/payload/
source controls passed; the runtime candidates themselves passed install tests.

## LLVM 22 compatibility

LLVM 23 split C branch opcode 2 into `LLVMUncondBr=70` and `LLVMCondBr=71`.
Astra's independent physical consumers use that vocabulary. The LLVM 22
provider uses `--wrap=LLVMGetInstructionOpcode`, translating only opcode 2
according to `LLVMIsConditional`. Other opcodes and all semantic/ownership/
physical verifiers remain unchanged. The docs image still links no LLVM.
The direct native object's historical banner remains LLVM 23.1.4; the installed
CLI obtains the actual runtime version, and installation provenance records it.

A compiled branch/LP64 ABI witness passed on both versions. Header/export
matrices cover 230 Fedora and 231 Ubuntu functions (the additional import is
`LLVMIsConditional`); common declarations agree. Added type/value/atomic enum
members are recorded, not assumed interchangeable. Astra uses neither the
shifted value-kind enum nor the new trailing enum members. Six existing GDB
physical suites passed 39 real mutations and 22 positive controls per target,
including ownership, ranges, enums, formatting, lazy operations and collections.
The LLVM 22 mutation observer uses the same normalized opcode boundary; the
independent raw LLVM structural verifier still accepts each mutated module
before Astra refuses it and preserves the sentinel.

The original authenticated O2 compiler object was reused, SHA-256
`a1e4fb5aa36aeb3726aa1bd47a74d8cce8464120410ba11a84a08c475f5c2988`.
All its Astra sources remain byte-identical to the authenticated generation.
The C provider is rebuilt against each target's headers; its guard and branch
adapter changes are disclosed separately in the handoff. No new source-generation
or convergence claim is made. Private pinned LLVM 23 remains build-only bootstrap
material, never a consumer dependency or a Linux payload.

## Strict memory and owner decision

Fedora 23.1.5 passed all 17 strict unsuppressed observations, including the
original InstCombine IR, owners-O2 and values-O2. This does not erase original
LLVM 23.1.4 InstCombine/owners/values NOT_PASS or qualify a full release.

Ubuntu LLVM 22 pulls official `libz3-4` `4.13.3-1build1`. Ten strict observations
fail with a 40-byte still-reachable allocation from the Z3 library initializer,
including identity/malformed/InstCombine standalone oracles and native compiler
cases. Raw traces show zero suppressed errors. Native generated targets and
isolated docs pass their focused memory checks. No suppression, explicit Z3
internal teardown, private library, source semantic change or runtime substitution
was used to make this green. Ubuntu remains PARTIAL under the required gate.

The functional official-LLVM-22 adapter is proven in the stated scope. The next
choice is to retain it as an unqualified development preview while qualifying
a distro/upstream fix for the Z3 process-lifetime allocation, or separately
authorize evaluation of signed apt.llvm.org LLVM 23 packages. That option is
third-party system management, is not yet tested here, may retain the same Z3
issue, and needs explicit owner acceptance of the APT repository/key/dependency
trust boundary before installation. No external APT source was added.

Rebuilt C0 remains ACCEPTED WITH DISCLOSURE; its historical strict memory remains
NOT_PASS. Original C0 and 1,044 raw proofs remain missing. Generic256/SSA8M,
module-owned layout lifetime, protected fixtures and peer work are preserved.
Windows remains an unfinished separate native port; only Windows may bundle LLVM.

## Distribution boundary

`tools/ci/copr-preparation.json` prepares generic project `astra`, package
`astrac`, and Fedora 45 x86_64; it leaves the actual Fedora account unassigned.
Its generic ecosystem description includes KAIROS and Nyx. The old COPR packet
is superseded unlaunched reference material, not an executed milestone.
No COPR create/upload, GitHub Release, new public binary artifact, merge or
branch-protection change occurred. The old exact binary approval is disabled
for new builds; the changed workflow uploads text observations only.


Resource observations retain per-command GNU time records. The actual native
relink used Ubuntu 0.565 s wall / 0.38 s user / 0.12 s system / 93,132 KiB peak
RSS, and Fedora 0.380 s wall / 0.29 s user / 0.07 s system / 99,148 KiB peak RSS.
Native package creation used Ubuntu 2.168 s wall / 2.03 s user / 0.07 s system /
92,820 KiB peak RSS, and Fedora 3.367 s wall / 3.66 s user / 0.77 s system /
620,120 KiB peak RSS. Final fresh-container lifecycles took 114.477 s and
109.005 s respectively. Podman client CPU is not aggregate container CPU;
compiler, memory and physical-test subprocess measurements are retained separately.
Two outer install wrappers ended with 143 while their independent child sessions
continued; their RUNNING records remain raw. Both child container commands have
actual exit-0 records and complete final install/migration/uninstall receipts.
