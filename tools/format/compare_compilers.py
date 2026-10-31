#!/usr/bin/env python3
"""Compare two compilers on identical Git-pinned inputs, without span erasure."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--baseline', type=Path, required=True)
	p.add_argument('--formatted', type=Path, required=True)
	p.add_argument('--base', required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	out = a.output.resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=False)
	rows = []
	model = dict(base=a.base, compiler_hashes={str(c): hashlib.sha256(c.read_bytes()).hexdigest()
		for c in (a.baseline, a.formatted)}, sources={}, commands=rows, comparisons=[])
	def save():
		(out/'comparison.json').write_text(json.dumps(model, indent=2)+'\n')
	def original(name):
		path = out/'inputs'/name
		if not path.exists():
			path.parent.mkdir(parents=True, exist_ok=True)
			path.write_bytes(subprocess.check_output(['git', '-C', str(ROOT), 'show', a.base + ':' + name]))
			model['sources'][name] = hashlib.sha256(path.read_bytes()).hexdigest()
		return path
	def run(argv, expected=0):
		argv = list(map(str, argv))
		start = time.monotonic()
		result = subprocess.run(argv, capture_output=True, timeout=120)
		rows.append(dict(argv=argv, exit=result.returncode, expected_exit=expected,
			stdout_sha256=hashlib.sha256(result.stdout).hexdigest(), stderr=result.stderr.decode(errors='replace'),
			seconds=time.monotonic()-start))
		save()
		assert result.returncode == expected, rows[-1]
		return result.stdout, result.stderr
	providers = {}
	for name in ['lib/runtime/interop/retained.c', 'tests/interop-async-5/retained-observer.c',
		'lib/runtime/platform/args-posix.c', 'tests/shared-1b/apps-observer.c']:
		source = original(name)
		# Preserve original adjacent private headers for the baseline C observer.
		for header in (ROOT/Path(name).parent).glob('*.h'):
			original(str(header.relative_to(ROOT)))
		product = out/(Path(name).stem+'.o')
		run(['/usr/bin/gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', product])
		providers[name] = product
	cases = [
		('generic-vector', 'tests/gen/fixtures/gen-choose.astra', [], 42),
		('checked-owners', 'tests/error-1/fixtures/checked-owners.astra', [], 42),
		('exception-cleanup', 'tests/error-1/fixtures/control-flow.astra', [providers['lib/runtime/platform/args-posix.c']], 42),
		('shared-weak', 'tests/shared-1b/weak-backedge.astra', [providers['tests/shared-1b/apps-observer.c']], 0),
		('retained-callback', 'tests/interop-async-5/retained-identity.astra', [providers['lib/runtime/interop/retained.c'], providers['tests/interop-async-5/retained-observer.c']], 0),
		('numeric', 'tests/f32/fixtures/f32-basic.astra', [], 0),
	]
	for label, name, objects, expected in cases:
		source = original(name)
		for mode in ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--check']:
			before = run([a.baseline, mode, source])
			after = run([a.formatted, mode, source])
			assert before == after, (label, mode, 'exact stage/diagnostic mismatch')
			model['comparisons'].append(dict(case=label, mode=mode, exact=True))
		for opt in ['-O0', '-O2']:
			before = run([a.baseline, opt, '--dump-llvm', source])
			after = run([a.formatted, opt, '--dump-llvm', source])
			assert before == after, (label, opt, 'LLVM mismatch')
			products = []
			for tag, compiler in [('baseline', a.baseline), ('formatted', a.formatted)]:
				exe = out/(label+opt+'-'+tag)
				links = [x for obj in objects for x in ('--link-object', obj)]
				run([compiler, opt, source, *links, '-o', exe])
				# Identical argv[0] matters for the checked main(string[]) case.
				result = subprocess.run(['paired-program'], executable=exe, capture_output=True, timeout=30)
				assert result.returncode == expected, (label, result)
				products.append((result.returncode, result.stdout, result.stderr))
			assert products[0] == products[1], (label, opt, 'native output mismatch')
			model['comparisons'].append(dict(case=label, mode=opt, exact_llvm=True,
				exact_execution=True, expected_exit=expected, stdout_hex=products[0][1].hex()))
		for compiler in (a.baseline, a.formatted):
			formatted = run([compiler, '--format', source])[0]
			if compiler == a.baseline:
				original_format = formatted
			else:
				assert formatted == original_format
				# Identical invalid input checks diagnostics only; no malformed executable runs.
	source = original('tests/gen/fixtures/gen-invalid.astra')
	assert run([a.baseline, '--check', source], 1) == run([a.formatted, '--check', source], 1)
	model['status'] = 'PASS'
	save()
	print('PASS:', len(model['comparisons']), 'exact paired observations; no source-coordinate normalization')


if __name__ == '__main__':
	main()
