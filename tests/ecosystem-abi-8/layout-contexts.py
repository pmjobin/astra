#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native binding/rebinding must release queried layout caches before contexts."""
from pathlib import Path
import hashlib
import json
import os
import re
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve(strict=True)
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='layout-contexts-', dir=output))
	guard = work/'guard.so'
	source = Path(__file__).with_name('layout-lifetime-guard.c')
	receipt = dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), checks=[])
	def run(args, guarded=False, negative=False, expected=0, contains=''):
		env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
		if guarded:
			env['LD_PRELOAD'] = str(guard)
		if negative:
			env['ASTRA_TEST_RETAIN_LAYOUT'] = '1'
		assert hashlib.sha256(compiler.read_bytes()).hexdigest() == receipt['compiler_sha256']
		p = subprocess.run(list(map(str, args)), cwd=work, env=env, capture_output=True, text=True, timeout=120)
		receipt['checks'].append(dict(command=list(map(str, args)), exit=p.returncode, expected=97 if negative else expected, stdout=p.stdout, stderr=p.stderr))
		(work/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert p.returncode == (97 if negative else expected) and contains in p.stdout+p.stderr, receipt['checks'][-1]
		if negative:
			assert 'queried cache survives context' in p.stderr
		elif guarded:
			assert re.search(r'layout-guard: queries=[1-9]\d* released=[1-9]\d* contexts=[1-9]\d*', p.stderr), p.stderr
		return p
	run(['cc', '-std=c11', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', source, '-ldl', '-lLLVM', '-o', guard])
	fixtures = ROOT/'tests/declaration-interop-16'
	metadata = runpy.run_path(str(ROOT/'tests/structural-generics-15/units.py'))
	for level in ('0', '2'):
		case = work/('O'+level)
		case.mkdir()
		for name in ('leaf', 'middle', 'consumer'):
			(case/(name+'.astra')).write_bytes((fixtures/('foreign-unit-'+name+'.astra')).read_bytes())
		leaf = [compiler, '-O'+level, '-c', '--module', 'Hidden16']
		for name in ('Session', 'Fault', 'Sample', 'Pair<f64>'):
			leaf += ['--native-export', 'Hidden16.'+name]
		leaf += ['--emit-interface', case/'leaf.asti', case/'leaf.astra', '-o', case/'leaf.o']
		run(leaf, guarded=True)
		run([compiler, '-O'+level, '-c', '--module', 'Adapter16', '--native-export', 'Adapter16.Facade', '--import-module', case/'leaf.asti', '--emit-interface', case/'middle.asti', case/'middle.astra', '-o', case/'middle.o'], guarded=True)
		(case/'leaf.astra').unlink()
		(case/'middle.astra').unlink()
		bad = case/'wrong-layout'
		bad.mkdir()
		(bad/'leaf.o').write_bytes((case/'leaf.o').read_bytes())
		groups = metadata['metadata']((case/'leaf.asti').read_text())
		declarations = groups['abi']['declarations']
		assert declarations.count('private int seed;') == 1
		declarations = declarations.replace('private int seed;', 'private i64 seed;')
		groups['abi']['declarations'] = declarations
		groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
		(bad/'leaf.asti').write_text(metadata['reseal'](groups))
		anchor = bad/'anchor.astra'
		anchor.write_text('int anchor(){return 0;}\n')
		# An ordinary checked layout rejection must also release scratch state.
		run([compiler, '--import-module', bad/'leaf.asti', '--dump-ssa', anchor], guarded=True, expected=1, contains='native type layout/visibility mismatch: Hidden16.Session')
		for mode in ('--dump-ssa', '--emit-class-source'):
			p = run([compiler, '--import-module', case/'middle.asti', mode, case/'consumer.astra'], guarded=True)
			if mode == '--dump-ssa':
				# SSA dumping creates only bind scratch contexts: at least two
				# proves the optimizer-import validation/rebind route ran.
				assert int(re.search(r'contexts=(\d+)', p.stderr)[1]) >= 2
				# Repeat the consuming path with a deliberately retained queried cache.
				# The guard must fail independently of pointer reuse or layout values.
		run([compiler, '--import-module', case/'middle.asti', '--dump-ssa', case/'consumer.astra'], guarded=True, negative=True)
	print('PASS: native layout contexts: O0/O2, optimizer rebinds and deterministic lifetime negatives')


if __name__ == '__main__':
	main(*sys.argv[1:])
