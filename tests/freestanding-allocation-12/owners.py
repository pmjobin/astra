# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Astra allocation policies, independent runtime and owner oracles."""
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def domain(kind, name, capacity, blocks, allocate='', release=''):
	# Independently reproduce the documented link identity, excluding each
	# individual object's alignment from the shared storage domain.
	canonical = f'allocation/1;{kind};{len(name)}:{name};{capacity};{blocks};0;{allocate};{release}'
	return 'astra_alloc12_domain_' + hashlib.sha256(canonical.encode()).hexdigest()


def tag(name, role):
	value = int(hashlib.sha256(f'{name}/{role}'.encode()).hexdigest()[:16], 16)
	return str(value or 1) + 'ULL'


def main(compiler, output):
	e = Evidence(compiler, output, 'allocation-owners')
	runtime = ROOT / 'lib/runtime/runtime'
	common = e.output / 'allocation.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-fno-builtin', '-c', runtime / 'allocation-12.c', '-o', common])
	oracle = e.output / 'region-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DREGION_DOMAIN=' + domain(1, 'a101.region', 4096, 64),
		'-c', ROOT / 'tests/freestanding-allocation-12/region-oracle.c', '-o', oracle])
	source = ROOT / 'examples/freestanding-allocation-12/a101-region-owners.astra'
	for level in (0, 1, 2):
		product = e.output / f'a101-O{level}'
		e.run([e.compiler, f'-O{level}', '--link-object', common,
			'--link-object', oracle, source, '-o', product])
		# The last binding owns moved first; it retires before third and second.
		trace = '11,22,33,' + ''.join(f'{100+i},{200+i},{-200-i},{-100-i},' for i in range(12)) + '-11,-33,-22,44,-44,\n'
		e.run([product], expected=42, stdout=trace)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
		'--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'a101-O2'], expected=42,
		contains='ERROR SUMMARY: 0 errors')
	pool_oracle = e.output / 'pool-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DPOOL_DOMAIN=' + domain(2, 'a102.pool', 128, 2),
		'-c', ROOT / 'tests/freestanding-allocation-12/pool-oracle.c', '-o', pool_oracle])
	pool_source = ROOT / 'examples/freestanding-allocation-12/a102-pool-reuse.astra'
	pool_trace = '1,2,-1,4,-4,-2,' + ''.join(f'{i},{-i},' for i in range(10, 26)) + '\n'
	for level in (0, 1, 2):
		product = e.output / f'a102-O{level}'
		e.run([e.compiler, f'-O{level}', pool_source, '--link-object', common,
			'--link-object', pool_oracle, '-o', product])
		e.run([product], expected=42, stdout=pool_trace)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
		'--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'a102-O2'], expected=42,
		contains='ERROR SUMMARY: 0 errors')
	e.files(pool_source, ROOT / 'tests/freestanding-allocation-12/pool-oracle.c', pool_oracle)
	heap = e.output / 'heap.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-c', runtime / 'allocation-12-host.c', '-o', heap])
	policy_oracle = e.output / 'policy-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DCUSTOM_DOMAIN=' + domain(4, 'a103.custom', 1024, 8, 'a103_place', 'a103_released'),
		'-DHEAP_DOMAIN=' + domain(0, 'a103.heap', 0, 0),
		'-DSTATIC_DOMAIN=' + domain(3, 'a103.static', 64, 1),
		'-c', ROOT / 'tests/freestanding-allocation-12/policy-oracle.c', '-o', policy_oracle])
	retained = e.output / 'retained.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-c', ROOT / 'lib/runtime/interop/retained.c', '-o', retained])
	closure_oracle = e.output / 'closure-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DCLOSURE_DOMAIN=' + domain(2, 'a106.closures', 256, 4),
		'-c', ROOT / 'tests/freestanding-allocation-12/closure-oracle.c', '-o', closure_oracle])
	for app, stem, links, trace in [
		('a103', 'a103-policy-identity', [heap, policy_oracle],
		'1:0,10:7,1:256,10:8,20:9,20:10,30:11,31:11,30:13,31:13,21:10,21:9,11:8,2:256,11:7,2:0,\n'),
		('a106', 'a106-retained-pool', [retained, closure_oracle],
		'1:10,1:20,2:15,3:15,2:27,3:27,1:30,3:30,\n')]:
		selected = ROOT / 'examples/freestanding-allocation-12' / (stem + '.astra')
		for level in (0, 1, 2):
			product = e.output / f'{app}-O{level}'
			arguments = [e.compiler, f'-O{level}', selected, '--link-object', common]
			for link in links:
				arguments += ['--link-object', link]
			e.run([*arguments, '-o', product])
			e.run([product], expected=42, stdout=trace)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / f'{app}-O2'], expected=42,
			contains='ERROR SUMMARY: 0 errors')
		e.files(selected, *links)
	text_provider = e.output / 'text.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror',
		'-c', ROOT / 'lib/runtime/platform/text-posix.c', '-o', text_provider])
	for app, stem, provider, defines, libraries, trace in [
		('a104', 'a104-bounded-bags', 'bag-oracle',
		['-DBAG_DOMAIN=' + domain(1, 'a104.bags', 512, 32), '-DDIAGNOSTIC_DOMAIN=' + domain(2, 'a104.diagnostics', 512, 8)],
		[ROOT / 'lib/astra/text/utf8-message.astra', ROOT / 'lib/astra/base/errors.astra'],
		'1,2,3,4,-1,-2,-3,-4,\n'),
		('a105', 'a105-record-rollback', 'record-oracle',
		['-DPART_DOMAIN=' + domain(2, 'a105.parts', 512, 8),
		'-DPARENT_DOMAIN=' + domain(1, 'a105.children', 512, 8)],
		[ROOT / 'lib/astra/base/errors.astra'],
		'1,2,3,7,-1,-3,90,-2,1,2,90,-2,-1,99,\n')]:
		observer_source = ROOT / 'tests/freestanding-allocation-12' / (provider + '.c')
		observer = e.output / (provider + '.o')
		e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
			'-I' + str(runtime), *defines, '-c', observer_source, '-o', observer])
		selected = ROOT / 'examples/freestanding-allocation-12' / (stem + '.astra')
		for level in (0, 1, 2):
			product = e.output / f'{app}-O{level}'
			e.run([e.compiler, f'-O{level}', selected, *libraries, '--link-object', common,
				'--link-object', observer, '--link-object', text_provider, '-o', product])
			e.run([product], expected=42, stdout=trace)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / f'{app}-O2'], expected=42,
			contains='ERROR SUMMARY: 0 errors')
		e.files(selected, observer_source, observer, *libraries)
	for cc in ('gcc', 'clang'):
		observer_source = ROOT / 'tests/freestanding-allocation-12/layout-oracle.c'
		observer = e.output / f'{cc}-layout.o'
		e.run([cc, '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
			'-c', observer_source, '-o', observer])
		selected = ROOT / 'examples/freestanding-allocation-12/a107-c-layout.astra'
		for level in (0, 1, 2):
			product = e.output / f'a107-{cc}-O{level}'
			e.run([e.compiler, f'-O{level}', selected, '--link-object', observer, '-o', product])
			e.run([product], expected=42, stdout='C:size=40,align=8,offsets=0/8/16/20/24/32\n')
			e.files(product)
		e.files(selected, observer_source, observer)
	here = ROOT / 'tests/freestanding-allocation-12'
	shared_oracle = e.output / 'shared-policy-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DSHARED_DOMAIN=' + domain(2, 'shared12.payload', 128, 2),
		'-c', here / 'shared-policy-oracle.c', '-o', shared_oracle])
	for level in (0, 1, 2):
		product = e.output / f'shared-policy-O{level}'
		e.run([e.compiler, f'-O{level}', here / 'shared-policy.astra', '--link-object', common,
			'--link-object', shared_oracle, '-o', product])
		e.run([product], expected=42, stdout='7,-7,8,-8,\n')
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'shared-policy-O2'], expected=42, contains='ERROR SUMMARY: 0 errors')
	e.files(here / 'shared-policy.astra', here / 'shared-policy-oracle.c', shared_oracle)
	record_storage = e.output / 'record-storage-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DNODE_DOMAIN=' + domain(2, 'record12.nodes', 512, 8),
		'-DRECORD_DOMAIN=' + domain(1, 'record12.storage', 2048, 16),
		'-c', here / 'record-storage-oracle.c', '-o', record_storage])
	for level in (0, 1, 2):
		product = e.output / f'record-storage-O{level}'
		e.run([e.compiler, f'-O{level}', here / 'record-storage-policy.astra',
			'--link-object', common, '--link-object', record_storage, '-o', product])
		e.run([product], expected=42, stdout='1,2,3,4,5,6,-1,-6,-5,-4,-3,-2,\n')
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'record-storage-O2'], expected=42, contains='ERROR SUMMARY: 0 errors')
	e.files(here / 'record-storage-policy.astra', here / 'record-storage-oracle.c', record_storage)
	slot_oracle = e.output / 'slot-identity-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DSLOT_DOMAIN=' + domain(1, 'slot12.shared', 512, 16),
		'-DLEFT_OBJECT=' + tag('Left', 'object'), '-DRIGHT_OBJECT=' + tag('Right', 'object'),
		'-DLEFT_SLOTS=' + tag('Left', 'slots'), '-DRIGHT_SLOTS=' + tag('Right', 'slots'),
		'-c', here / 'slot-identity-oracle.c', '-o', slot_oracle])
	for level in (0, 1, 2):
		product = e.output / f'slot-identity-O{level}'
		e.run([e.compiler, f'-O{level}', here / 'slot-domain-identity.astra',
			'--link-object', common, '--link-object', slot_oracle, '-o', product])
		e.run([product], expected=42, stdout='')
		e.files(product)
	e.files(here / 'slot-domain-identity.astra', here / 'slot-identity-oracle.c', slot_oracle)
	e.files(source, runtime / 'allocation-12.c', runtime / 'allocation-12.h',
		ROOT / 'tests/freestanding-allocation-12/region-oracle.c', common, oracle)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
