> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Ecosystem ABI Surge 8 qualification

Use the coordinator `<historical-private-path>` and its established external
Meson build `<historical-private-path>`. Revalidate the Meson
source routing before another worktree uses that area. No source-tree build,
legacy runner, custom scheduler, package installation or peer worktree is needed.

Build only the selected compiler/proof targets, with hooks/configuration intact:

```sh
CCACHE_DISABLE=1 meson compile -C <historical-private-path> -j 4 \
  astrac astra-source-debug-proof astra-native-module-proof \
  astra-retained-proof astra-checked-closure-proof astra-record-proof \
  astra-payload-proof astra-shared-lifetime-proof astra-owned-state-proof \
  astra-nonnull-source-contracts astra-nonnull-core-contracts \
  astra-nonnull-cfg-contracts astra-nonnull-ssa-contracts \
  astra-nonnull-field-contracts astra-usability-native-contracts \
  astra-gen-member-contracts astra-public-optimizer-contracts \
  astra-closure-value-proof
```

Run the maintained 41-name selected matrix with ordinary Meson. This example
uses Python only to preserve the exact argument list without shell splitting:

```sh
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
names = json.loads(Path('tests/ecosystem-abi-8/integration-tests.json').read_text())
raise SystemExit(subprocess.call([
	'meson', 'test', '-C', '<historical-private-path>',
	'--no-rebuild', '--num-processes', '4', '--print-errorlogs',
	'--logbase', 'ecosystem-abi-8-final', *names],
	env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')))
PY
```

The existing real payload/importer recipes select the installed matching
`~/.local/opt/liburing-2.15` unless `ASTRA_LIBURING_PREFIX` names another existing
qualified prefix. They probe actual kernel setup/READ/WRITE/CANCEL before
counting execution. Missing/blocked providers must be reported as such. The
GObject/GIR/debug registrations require actual installed headers/libs/GIR,
LLVM22 tools, Clang, GDB and Valgrind. No skipped required gate becomes PASS.

The eight new focused registrations include internal debug/module
reject/restore controls, selected real GObject/signals/GIR at O0/O1/O2,
independent module cross-optimization combinations and all A57–A64 at O0/O2.
The application recipe has O1 spots, exact stdout/files, independent producer
and consumer objects, actual GDB at formatted source lines, and scoped
sanitizers. New memory runs explicitly disable default Valgrind suppressions.
Older retained registrations keep their original declared scopes.

Record exact source/tool/header/resolved-library/build identities externally:

```sh
python3 tests/ecosystem-abi-8/inventory.py \
  <historical-private-path> \
  <historical-private-path>
```

Inspect checked exits and actual output assertions, raw Meson JSON/text logs,
focused per-command receipts and source/product SHA-256. A successful compile
alone does not establish acceptance. Keep raw failed attempts and subsequent
qualified reruns; final current evidence must match the committed implementation.
Historical LAZY strict Q4 and prior partial/full-suite records remain unchanged.

After the final explicit task commit, verify the protected intake state:

```sh
python3 tests/ecosystem-abi-8/conservation.py \
  <historical-private-path> \
  <historical-private-path>
```

`evidence.py BUILD RUNTIME docs/ecosystem-abi-8-evidence.json` compacts the actual
41-registration run plus the two affected post-review version checks. It refuses
failed checks, stale source/product hashes or a changed compiler. It preserves
exact commands, output excerpts/full hashes and explicit scope; it does not run
or replace the native report publisher. The derived evidence document excludes
its own recursive source hash. Raw complete receipts remain external.
