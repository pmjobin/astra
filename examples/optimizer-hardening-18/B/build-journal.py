#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build B1 through explicit public source/native/library routes."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from freeze import check as freeze_check

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'library-root', 'build', 'runtime']:
		parser.add_argument('--' + name, type=Path, required=True)
	parser.add_argument('--profile', choices=['sequential', 'threaded', 'uring'], default='sequential')
	parser.add_argument('--optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--facts', choices=['off', 'on'], required=True)
	parser.add_argument('--linkage', choices=['local', 'native'], default='native')
	parser.add_argument('--variant', choices=['base', 'renamed', 'fields', 'helpers'], default='base')
	parser.add_argument('--producer-optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--freeze', type=Path)
	args = parser.parse_args()
	compiler, library = args.compiler.resolve(strict=True), args.library_root.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='journal-B1-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='journal-B1-', dir=args.runtime.resolve()))
	checked = freeze_check(args.freeze, ROOT) if args.freeze else None
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1',
		ASTRA_TEST_OPTIMIZATIONS=args.facts, ASTRA_EXPLAIN_OPTIMIZATIONS='1')
	receipt = {'status': 'BUILDING_NOT_QUALIFIED', 'compiler': {'path': str(compiler), 'sha256': sha(compiler)},
		'profile': args.profile, 'optimization': args.optimization, 'facts': args.facts, 'linkage': args.linkage,
		'variant': args.variant, 'producer_optimization': args.producer_optimization, 'producer_facts': 'on',
		'freeze_before': checked, 'commands': [], 'inputs': {}, 'products': {}}
	path = runtime / 'build.json'
	def save():
		path.write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, facts=None, output=None):
		command = list(map(str, command)); start = time.monotonic()
		q = subprocess.run(command, cwd=build, env=dict(env, ASTRA_TEST_OPTIMIZATIONS=facts or args.facts), capture_output=True, text=True, timeout=90)
		if output is not None: output.write_text(q.stdout)
		receipt['commands'].append({'command': command, 'exit': q.returncode, 'stdout': q.stdout if output is None else {'path': str(output), 'sha256': sha(output)},
			'stderr': q.stderr, 'seconds': time.monotonic() - start})
		save()
		assert q.returncode == 0, receipt['commands'][-1]
		return q.stdout
	try:
		consumer = [HERE / ('journal-' + name + '.astra') for name in ['host', 'common', 'engine', 'jobs']]
		consumer += [library / 'base/errors.astra', library / 'collections/map.astra', library / 'collections/vector.astra']
		vapis = [library / 'memory/contexts.vapi']
		providers = [HERE / 'journal-host.c', library / 'runtime/context-17.c', library / 'platform/args-posix.c']
		c_flags = ['-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-I', library / 'runtime']
		links = []
		if args.profile == 'sequential':
			consumer += [HERE / 'journal-sequential.astra']
		elif args.profile == 'threaded':
			consumer += [HERE / 'journal-threaded.astra', library / 'async/threaded.astra']
			providers += [library / 'async/threaded.c', library / 'runtime/monitors-13.c']
		else:
			assert args.uring_prefix
			prefix = args.uring_prefix.resolve(strict=True)
			consumer += [HERE / 'journal-io-cpu.astra', HERE / 'journal-io.astra', library / 'async/payload.astra']
			vapis += [library / 'async/composition.vapi', library / 'async/payload.vapi']
			providers += [library / 'async/composed.c', library / 'async/linux.c', library / 'runtime/monitors-13.c']
			c_flags += ['-DJOURNAL18_IO', '-isystem', prefix / 'include']
			links += [prefix / 'lib/liburing.a']
		leaf, middle = HERE / 'journal-leaf.astra', HERE / 'journal-middle.astra'
		inputs = [Path(__file__), HERE / 'freeze.py', leaf, middle, *consumer, *vapis, *providers, *links]
		receipt['inputs'] = {str(p): sha(p) for p in inputs}
		# Render equivalent source variants outside the checkout. The algorithm,
		# independent reference, input seed and lifetime observations stay fixed.
		sources = build / 'sources'; sources.mkdir()
		texts = {p.name: p.read_text() for p in [leaf, middle, *consumer] if p.parent == HERE}
		if args.variant == 'renamed':
			for name, code in texts.items():
				for before, after in [('JournalLeaf18', 'LedgerLeaf18'), ('JournalMiddle18', 'LedgerMiddle18'),
					('Gate', 'TransactionLimit18'), ('JournalAccount18', 'LedgerAccount18'),
					('JournalUndo18', 'LedgerUndo18'), ('JournalHistory18', 'LedgerHistory18')]:
					code = code.replace(before, after)
				texts[name] = code
		elif args.variant == 'fields':
			before = '\tint transaction;\n\tint kind;\n\tint bound;'
			assert before in texts[leaf.name]
			texts[leaf.name] = texts[leaf.name].replace(before, '\tint bound;\n\tint kind;\n\tint transaction;')
		elif args.variant == 'helpers':
			before = 'int maximum = bound(amounts);'
			assert before in texts['journal-engine.astra']
			texts['journal-engine.astra'] = texts['journal-engine.astra'].replace(before, 'int maximum = journal18_amount_limit(amounts);')
			texts['journal-engine.astra'] += '\nint journal18_amount_limit(Gate gate) { return bound(gate); }\n'
		for name, code in texts.items(): (sources / name).write_text(code)
		receipt['rendered_inputs'] = {str(sources / name): sha(sources / name) for name in texts}
		consumer = [sources / p.name if p.parent == HERE else p for p in consumer]
		leaf, middle = sources / leaf.name, sources / middle.name
		leaf_module, middle_module = ('LedgerLeaf18', 'LedgerMiddle18') if args.variant == 'renamed' else ('JournalLeaf18', 'JournalMiddle18')
		gate_name = 'TransactionLimit18' if args.variant == 'renamed' else 'Gate'
		imports, native_objects = [], []
		if args.linkage == 'native':
			producer = build / 'producer'; producer.mkdir()
			for source in [leaf, middle, sources / 'journal-host.astra']:
				shutil.copyfile(source, producer / source.name)
			sdk = build / 'sdk'; sdk.mkdir()
			run([compiler, '-O' + args.producer_optimization, '-c', '--module', leaf_module,
				*[arg for name in [gate_name, 'gate_limit', 'add_two'] for arg in ['--native-export', leaf_module + '.' + name]],
				'--emit-interface', sdk / 'leaf.asti', producer / leaf.name, producer / 'journal-host.astra', '-o', sdk / 'leaf.o'], facts='on')
			run([compiler, '-O' + args.producer_optimization, '-c', '--module', middle_module,
				'--native-export', middle_module + '.bound', '--native-export', middle_module + '.odd_salt',
				'--import-module', sdk / 'leaf.asti', '--emit-interface', sdk / 'middle.asti', producer / middle.name, '-o', sdk / 'middle.o'], facts='on')
			for source in producer.iterdir(): source.unlink()
			# Both original rendered implementations and producer copies are hidden.
			leaf.unlink(); middle.unlink()
			imports = ['--import-module', sdk / 'middle.asti']
			native_objects = [sdk / 'leaf.o', sdk / 'middle.o']
			receipt['producer_inputs_removed'] = not any(producer.iterdir())
		else:
			consumer += [leaf, middle]
		common = [compiler, '-O' + args.optimization, *consumer,
			*[arg for p in vapis for arg in ['--vapi', p]], *imports]
		ssa = build / 'journal.ssa'; run([common[0], *common[2:], '--dump-ssa'], output=ssa)
		receipt['claims'] = {name: [line for line in ssa.read_text().splitlines() if marker in line]
			for name, marker in [('storage', '(stack-object'), ('shared', '(shared-elision'), ('dispatch', '(exact-call')]}
		ir = build / 'journal.ll'
		run([*common, '--dump-llvm'], output=ir)
		obj, product = build / 'journal.o', build / 'journal'
		command = [*common, '--entry-object', '-o', obj]
		receipt['consumer_command'] = list(map(str, command))
		trace = runtime / 'consumer-opens.log'
		run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command])
		if args.linkage == 'native':
			opened = trace.read_text()
			assert str(leaf) not in opened and str(middle) not in opened and str(build / 'producer') not in opened
		wrappers = ['-Wl,--wrap=' + name for name in ['calloc', 'malloc', 'realloc']]
		link = ['cc', *c_flags, obj, *native_objects, *providers, *links, *wrappers, '-o', product]
		receipt['link_command'] = list(map(str, link)); run(link)
		assembly = build / 'journal.asm'; run(['objdump', '-dr', product], output=assembly)
		receipt['sections'] = run(['size', '-A', product])
		artifacts = [ssa, ir, obj, product, trace, assembly, *native_objects]
		if args.linkage == 'native': artifacts += [sdk / 'leaf.asti', sdk / 'middle.asti']
		receipt['products'] = {str(p): {'sha256': sha(p), 'bytes': p.stat().st_size} for p in artifacts}
		receipt['product'] = str(product)
		assert sha(compiler) == receipt['compiler']['sha256']
		assert all(sha(p) == h for p, h in receipt['inputs'].items())
		receipt['status'] = 'BUILT_NOT_QUALIFIED'
	finally:
		receipt['freeze_after'] = freeze_check(args.freeze, ROOT) if args.freeze else None
		save()
	print(path)
	print(product)


if __name__ == '__main__':
	main()
