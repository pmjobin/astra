# 28-A2 book engineering — PARTIAL

The campaign adds a 17-chapter Language Reference and 13-chapter Programming
Guide to the existing chapter manifest. Approximately 12,000 whitespace-delimited
words include exact code fixtures. The source inventory covers 269 compiler/library
units and 100 current SyntaxKind families; 52 representative rule entries name
hashed source/declaration spans and controls. These are substantial candidate
books, not qualified COMPLETE works.

## Actual current evidence

- Exact installed unchanged pm-next intake authenticated the 51,306,544-byte
  submission SHA `641e588a2e2e17a0772fe15d66bb1907ad2f1da111a7083e937f072d664e0ed2`,
  required initial HEAD/tree, prior submission/report, 51 live source Git blobs,
  12-part 15,680,456-byte transport and 19,744-file/10,372-blob mapping.
- Genuine prior G7 was discovered and reauthenticated before book edits. It ran
  2026-11-16 07:15:07–07:15:53 UTC after the actual report's 07:08:45 publication,
  bound to report SHA `1acc88af43839d90a52ec88b6ff4898e9305ffefd97988136ff28f8ceb40081f`.
  All 153 recorded command streams, 20 strict memory streams and 37 qualification
  receipts reauthenticate. Prior physical suites remain bound qualification
  evidence, not newly executed by that historical delivery recipe.
- All 25 authored cases pass through current compiler host O0/O2 and target
  O0/O2. The new campaign ran 317 timed commands, including 160 strict-memory
  invocations. It checked LLVM IR, exact exits/stdout, refusal sentinels, real
  file input/malformed/missing paths, and a static no-runtime fixed-array target.
  Native stage UTC: 08:34:43.467850–08:45:10.925537 on 2026-11-16.
- All 22 established native/ABI/ownership/physical suites freshly passed,
  including 46 LLVM-valid corruption refusals. Unchanged authenticated source
  consumer products were freshly executed O0/O2 under strict memory, retaining
  their historical build revision and validating every source/provider/tool byte.
  No unnecessary source-consumer or whole compiler rebuild is claimed.
- Current docs LLVM isolation passed. Four schema/extraction harness attempts
  initially lacked jsonschema on the pinned interpreter's search path. Their
  failures remain preserved; the four affected lanes passed after authenticating
  and supplying the existing dependency path. No package or toolchain was installed.
- The offline site integrates actual compiler-generated API pages, both books,
  full-book browser Find routes and print-friendly HTML. Local links/fragments,
  deterministic regeneration and hostile-input controls pass. Real Chromium
  checks and visual review cover desktop/mobile, native Tab/Enter skip-link
  focus and print media with page scripts disabled. Mobile navigation was
  corrected after inspecting the first candidate. No web deployment occurred.

## Incomplete acceptance

G1/G2 remain PARTIAL: 231 inventoried source units lack a direct chapter-rule
witness. The declaration-line spans and representative positive/negative controls
are not exhaustive semantic proofs. The grammar is a parser-aligned summary,
not a complete independently qualified specification across all current policies.

G3/full-scope G4 remain PARTIAL: the Guide has a coherent progressive arc and
tested application, but deeper rule-specific teaching/conformance coverage is
still required for admitted generic, ownership, effect, ABI and profile
combinations. Passing all authored fixtures cannot narrow the promised complete
two-book scope. Native refusals discovered during writing are disclosed rather
than repaired by changing compiler semantics or weakening verification.

Examples include current refusals of representative for, comparison-chain,
constant, vector, typed-pointer and retained-view programs. Successful parser
representation or historical bootstrap documentation does not grant native
support. Early authoring failures and environment/browser harness corrections
are preserved. The first quick attempt lacked independently saved fixture
bytes; no historical witness was retroactively fabricated.

The first final-audit collector stopped because it omitted parent controller
receipts when counting the four preserved schema failures. The corrected audit
rehashes both parent and inner streams; execution outcomes were not changed.
Some early harness/collector failures exist as Codex tool responses rather than
independently captured process streams. They receive no retroactive raw-log or
source-witness claim.

## Preservation and delivery

Compiler/library sources, checked ownership, public C ABI/E25-A-v1, generic 256,
SSA 8M, original 451 protected paths, 6,622 donors, hooks, workflow and peer work
remain preserved. New refusal fixtures have their own exact-byte scope entries.
Formatting uses the guarded entry point and existing qualified tool identities.

Original C0 and 1,044 historical raw proofs remain absent; 27-B stays PARTIAL.
Rebuilt-C0 provenance substitution is ACCEPTED WITH DISCLOSURE only. Its strict
all-kinds process memory remains NOT_PASS, with separate release risk/technical
disposition still required. No historical acceptance is reclassified.

The installed publisher produces the canonical PARTIAL report. Its independent
G8 remains PENDING until actual publication. Use committed
`tests/books/delivery.py --report-sha256 ACTUAL_SHA --qualification QUALIFICATION_JSON
--build FRESH_EXTERNAL_BUILD --runtime FRESH_EXTERNAL_RUNTIME` afterward; it
replays real native/book/docs/physical/source-consumer checks and preserves the
engineering PARTIAL status. No PDF, hardback, release, push, tag or deployment
is claimed. Next tracks remain 28-B performance/C++ comparisons, 28-C developer
experience and 28-D release qualification; print production remains later.

## Read the complete offline product from the report

The direct HTML evidence attachments are previews. The full linked site is
transported losslessly with its local assets and API pages. Save the following
standard-library recipe as `read-site.py`, then run
`python3 read-site.py astra-report-current.zip NEW_OUTPUT_DIRECTORY` and open
`NEW_OUTPUT_DIRECTORY/index.html`. The destination must be new. This byte check
does not run a compiler or close G8.

```python
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile
import zipfile

digest = lambda value: hashlib.sha256(value).hexdigest()
with zipfile.ZipFile(sys.argv[1]) as report:
	transport = json.loads(report.read('evidence/TRANSPORT.json'))
	pieces = []
	for part in transport['parts']:
		encoded = report.read('evidence/'+part['path'])
		assert len(encoded) == part['bytes'] and digest(encoded) == part['sha256']
		pieces.append(base64.b64decode(json.loads(encoded)['base64'], validate=True))
	raw = b''.join(pieces)
	assert len(raw) == transport['archive']['bytes']
	assert digest(raw) == transport['archive']['sha256']
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=False)
with tarfile.open(fileobj=io.BytesIO(raw), mode='r:xz') as archive:
	index = json.load(archive.extractfile('INDEX.json'))
	for name, row in index['files'].items():
		if not name.startswith('site/'):
			continue
		relative = PurePosixPath(name).relative_to('site')
		assert not relative.is_absolute() and '..' not in relative.parts
		assert row['blob'] == 'blobs/'+row['sha256']
		data = archive.extractfile(row['blob']).read()
		assert len(data) == row['bytes'] and digest(data) == row['sha256']
		path = output.joinpath(*relative.parts)
		path.parent.mkdir(parents=True, exist_ok=True)
		path.write_bytes(data)
```

## R1 continuation, 2026-11-16

This addendum describes ASTRA-RELEASE-28A2-R1-BOOK-COMPLETION. All earlier findings
above remain historical, including the original engineering PARTIAL. R1 began
at HEAD d1eed151d63cf4dbebf2b819872c5cf482b7fc04, tree
b74a250f154be4251c900481748f93d89fc5835e. The exact submission SHA-256 is
9e78499c69071e6972bbe98d7f7dd7a886567f45b9fbfd50f89548f713e0cc0b.
Installed intake and independent offline checks authenticated 101 indexed
payloads, 89 read-only witnesses, the exact nested predecessor submission/report,
78 source Git blobs, 2 evidence parts/2,087,568 bytes, 14,829 logical mappings and
8,414 independently hashed blobs. Initial tracked work/index were clean; the
pre-existing untracked compiler-complete runner remains byte-exact.

Before any source edits, the original delivery recipe ran against the actual
canonical published report hash, with fresh ABI/owner/docs/physical/browser
supplements. Independent audit established a genuine later original 28-A2 G8:
publication 09:15:54 UTC, execution 17:23:08–17:34:32 UTC, audit 17:35:00 UTC.
The transported receipt binds the exact 2,949,415-byte report hash
0d58b978a92d01f0ecdf6bfbcd0ff82423b0e5c0454920be05eed44655c2a01f,
1,035 command records, 314 strict returning-memory streams and 46 physical
corruption refusals. It changes no historical engineering status.

### What R1 adds

The 30-chapter candidate now has 39 book cases and 42 byte-linked fixture files.
New native examples observe implicit owning defaults, anchored readonly borrows,
weak expiry after the final strong retirement, written argument order and
short-circuit selection, consuming-call cleanup on success and throw, exact
numeric domains, integer extrema/stride cardinality, floating lazy reduction and
generic capability checks. New negatives expose moved-local rearming refusal,
an unanchored stored borrow, wrong capability, wrong fixed count, unproven dynamic
comprehension count and mixed numeric types. These are actual current product
behaviors; no compiler semantics were changed to make an example pass.

All 269 source units have exact Git/content identities, role/declaration review
and explicit semantic-authority/independent-verifier/implementation distinctions.
All 100 SyntaxKind families have source surface/context notes. A 476-case corpus
contains the entire source inventory, 125 exact protected syntax goldens, book
sources and independently expected refusal controls. The real typed syntax-source
consumer observed all 96 concrete families at O0/O2 with strict returning memory;
four abstract bases have no concrete production. Per-case observations and
positive/negative source bytes remain independently retained. Grammar edition
28-A2-R1.1 records lexical productions, precedence, association, ambiguity and
per-source modern/legacy boundaries. Parser observation grants no native credit.

There are 66 rule records, up from 52. Applicable direct witness debt decreased
from 231 to 222 units; it did not disappear. Two witnesses have full declaration
ranges actually exposed by current astra-api-docs/1 extraction. The other 64
explicitly remain declaration-line spans. The internal API output exposes 166
declarations from this input closure, not every compiler body. Neither role
classification, parser acceptance nor a source citation establishes exhaustive
semantic conformance. The generated inventory preserves this distinction.

The boundary recipe independently generates 256/257 generic instances, eight/nine
lazy stages and captures, 1,048,576/1,048,577 comprehension counts, parser-only
64/65 interpolation operands and an actual legacy shared-parameter contrast.
The SSA 8,000,000 ceiling remains source-bound; no exhaustion execution is claimed.
Exact final outcomes, raw streams and per-command CPU/wall/RSS live in the
transported QUALIFICATION.json and execution-costs.json. The complete 39-case
book run and all 29 current regression suites passed. Those regressions retain
46 actual LLVM physical corruption refusals, unchanged owner/ABI products and
the genuine compiler-backed API extraction/isolation boundaries.

### Open original acceptance obligations

G0 is PASS from the exact intake and independently established predecessor G8.
G1, G2, G3 and full-scope G4 remain PARTIAL. The source catalogue has role review
and selected domain-body review, not completed per-rule semantic review of every
authoritative unit. The 222 units without a direct rule witness are enumerated
in inventory.json; some are implementation infrastructure, while applicable
semantic/verifier/library contracts still need rule-specific source spans,
positive and discriminating negative controls and normative chapter links.
Implementation exclusions need explicit reasons, not a count-based waiver.

The versioned grammar still needs complete foreign-policy/declaration/profile
cross-products and broader independently checked ambiguity boundaries. The
Guide needs deeper teaching and executable controls for the remaining admitted
ownership, generic, error/effect, ABI, profile and library combinations. A real
multi-file app, all observed concrete families and all authored cases passing
cannot replace those original obligations. Retain the disclosed refusals of
for, chains, constants, vectors, typed pointers and retained views.

G5 and G6 cover the actual offline product and current regression campaigns;
they do not establish complete language conformance. G7 requires the final
clean task commit, unchanged hooks/workflows/protections and authenticated
publisher result. R1 G8 is PENDING until a real later canonical publication.
The extended delivery.py recognizes this exact R1 identity and replays the full
books/grammar/boundary/regression/offline lanes afterward. Its output explicitly
awaits independent audit and fresh screenshot inspection; it cannot grant G8
from publication alone. Do not run it before publication and backdate a receipt.

### Failed attempts and preservation

Authoring/preflight failures remain evidence: a bare literal lacked contextual
type through a generic result, moved-local rearming was actually refused, and
several expected parser diagnostic strings needed correction. Full native
attempt 1 exposed a shared C-provider log-directory collision; the runner now
compiles each provider once and reuses that authenticated object. Typed-consumer
attempt 1 used a zero-based observation array for actual one-based family codes
and aborted at code 100. Its real Valgrind abort/reachable-memory/error record
is NOT_PASS, with the 159,289,344-byte core retained externally and its hash
transported. The corrected fresh provider/link/execution is separately dated;
the identical O0 consumer object was reused only after complete frozen-source
and actual compile-record checks, without backdating its object hash. O2 was
built freshly. Boundary attempt 1 omitted child tracing and therefore had no
real compiler return-memory summary; it receives no qualification credit.
Tool-only authoring/formatting/collector errors receive no invented raw log.

All compiler/library bytes, independent consumers, module-owned LLVM caches,
public E25-A-v1 ABI, resource ceilings, original 451 protected paths, 6,622 donors,
hooks/settings/installed workflows and peer/user work remain preserved. The
original C0/1,044-proof loss, historical 27B PARTIAL, rebuilt-C0 provenance
ACCEPTED_WITH_DISCLOSURE and rebuilt-C0 process memory NOT_PASS remain distinct.
No safety waiver, release, deployment, PDF/hardcover, push or tag is claimed.
The next authorized sequence remains truthful 28-A2 completion, then 28-B
efficiency/fair C++ comparisons, 28-C developer experience and 28-D release
decisions. This PARTIAL result does not authorize starting those tracks.
