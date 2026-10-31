# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""ASan on emitted Astra bodies; ASan/UBSan on authored runtime and C oracles."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from owners import domain


def main(compiler, output):
	e = Evidence(compiler, output, 'allocation-sanitizers')
	here = ROOT / 'tests/freestanding-allocation-12'
	apps = ROOT / 'examples/freestanding-allocation-12'
	runtime = ROOT / 'lib/runtime/runtime'
	target = dict(line.split('=', 1) for line in e.run([e.compiler, '--target-info']).stdout.splitlines() if '=' in line)
	cases = [
		('a101-region-owners', 'region-oracle', ['-DREGION_DOMAIN=' + domain(1, 'a101.region', 4096, 64)], [], []),
		('a102-pool-reuse', 'pool-oracle', ['-DPOOL_DOMAIN=' + domain(2, 'a102.pool', 128, 2)], [], []),
		('a103-policy-identity', 'policy-oracle', [
		'-DCUSTOM_DOMAIN=' + domain(4, 'a103.custom', 1024, 8, 'a103_place', 'a103_released'),
		'-DHEAP_DOMAIN=' + domain(0, 'a103.heap', 0, 0), '-DSTATIC_DOMAIN=' + domain(3, 'a103.static', 64, 1)], [], [runtime / 'allocation-12-host.c']),
		('a104-bounded-bags', 'bag-oracle', ['-DBAG_DOMAIN=' + domain(1, 'a104.bags', 512, 32), '-DDIAGNOSTIC_DOMAIN=' + domain(2, 'a104.diagnostics', 512, 8)],
		[ROOT / 'lib/astra/text/utf8-message.astra', ROOT / 'lib/astra/base/errors.astra'], [ROOT / 'lib/runtime/platform/text-posix.c']),
		('a105-record-rollback', 'record-oracle', ['-DPART_DOMAIN=' + domain(2, 'a105.parts', 512, 8),
		'-DPARENT_DOMAIN=' + domain(1, 'a105.children', 512, 8)], [ROOT / 'lib/astra/base/errors.astra'], [ROOT / 'lib/runtime/platform/text-posix.c']),
		('a106-retained-pool', 'closure-oracle', ['-DCLOSURE_DOMAIN=' + domain(2, 'a106.closures', 256, 4)], [], [ROOT / 'lib/runtime/interop/retained.c']),
		('shared-policy', 'shared-policy-oracle', ['-DSHARED_DOMAIN=' + domain(2, 'shared12.payload', 128, 2)], [], []),
		('record-storage-policy', 'record-storage-oracle', ['-DNODE_DOMAIN=' + domain(2, 'record12.nodes', 512, 8), '-DRECORD_DOMAIN=' + domain(1, 'record12.storage', 2048, 16)], [], []),
	]
	for stem, observer, defines, libraries, providers in cases:
		source = (here if stem in ('shared-policy', 'record-storage-policy') else apps) / (stem + '.astra')
		text = e.run([e.compiler, '-O1', '--dump-llvm', source, *libraries]).stdout
		assert re.search(r'^define .*?@main\(', text, flags=re.M), 'public optimized dump must retain its C entry'
		text = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + text
		text = re.sub(r'^(define .*?)\s*\{\s*$', r'\1 sanitize_address {', text, flags=re.M)
		raw, checked, obj, product = [e.output / (stem + suffix) for suffix in ('.ll', '-asan.ll', '.o', '-asan')]
		raw.write_text(text)
		e.run(['opt', '-passes=default<O1>,asan', '-S', raw, '-o', checked])
		assert '__asan_report_' in checked.read_text(), 'Astra memory operations must actually be instrumented'
		e.run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', checked, '-o', obj])
		oracle = here / (observer + '.c')
		e.run(['clang', '-O1', '-g', '-std=c11', '-fsanitize=address,undefined',
			'-fno-omit-frame-pointer', '-Wall', '-Wextra', '-Werror', '-pedantic',
			'-I' + str(runtime), *defines, obj, runtime / 'allocation-12.c',
			oracle, *providers, '-o', product])
		e.run([product], expected=42, env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
			'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'})
		e.files(source, *libraries, oracle, *providers, raw, checked, obj, product)
	e.data['instrumentation'] = 'ASan on actual emitted Astra function bodies and authored C; UBSan on authored C runtime/oracles. System libraries are uninstrumented. Static domain suballocations rely additionally on source layout/bounds/ownership and runtime range/origin checks; these are not separate ASan heap objects.'
	e.files(runtime / 'allocation-12.c', runtime / 'allocation-12.h')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
