# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check callback input flow through ordinary scalar and array expressions."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FORMS = {
	'integer-conversion': ('i64 converted = integers.replace_callback(CALLBACK) as i64;', 0),
	'floating-roundtrip': ('i64 converted = (integers.replace_callback(CALLBACK) as f64) as i64;', 0),
	'arithmetic': ('i64 converted = (integers.replace_callback(CALLBACK) + 1) as i64;', 1),
	'shift': ('i64 converted = (1 << integers.replace_callback(CALLBACK)) as i64;', 1),
	'array-index': ('int[1] traversal = {0}; '
	'i64 converted = traversal[integers.replace_callback(CALLBACK)] as i64;', 0),
	'array-initializer': ('int[1] traversal = {integers.replace_callback(CALLBACK)}; '
	'i64 converted = traversal[0] as i64;', 0),
	'buffer-allocation': ('var traversal = new u8[1 + integers.replace_callback(CALLBACK)]; '
	'i64 converted = len(traversal) as i64;', 1),
	'slice-range': ('int[1] traversal = {0}; '
	'var view = slice(traversal, integers.replace_callback(CALLBACK), 1); '
	'i64 converted = len(view) as i64;', 1),
}


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='code-inputs-', dir=output))
	fixture = HERE / 'scoped-code-inspection.astra'
	base = fixture.read_text()
	anchor = 'i64 converted = integers.replace_callback(inspect_code) as i64;'
	assert base.count(anchor) == 1 and base.count('converted != 0') == 1
	receipt = dict(format='astra-m15-code-inputs/1', compiler_sha256=sha(compiler),
		recipe_sha256=sha(Path(__file__)), fixture_sha256=sha(fixture),
		forms=list(FORMS), checks=[], sources={}, products={})

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv, expected=0, diagnostic=None, memory=False, dump=False):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		passed = result.returncode == expected
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
		elif memory:
			passed &= all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		if not dump:
			passed &= not result.stdout
		receipt['checks'].append(dict(argv=argv, expected_exit=expected, exit=result.returncode,
			stderr=result.stderr.decode(errors='replace'), stdout_sha256=hashlib.sha256(result.stdout).hexdigest(),
			elapsed_seconds=time.perf_counter() - started, passed=bool(passed)))
		save()
		assert passed, receipt['checks'][-1]

	for form, (replacement, value) in FORMS.items():
		for mode, target in [('positive', 'inspect_code'), ('negative', 'change_unobserved_code')]:
			text = base.replace(anchor, replacement.replace('CALLBACK', target))
			text = text.replace('converted != 0', 'converted != ' + str(value))
			source = out / (form + '-' + mode + '.astra')
			source.write_text(text)
			receipt['sources'][str(source)] = sha(source)
			for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi']:
				negative = mode == 'negative' and stage != 'syntax'
				run([compiler, '--dump-' + stage, source], expected=1 if negative else 0,
					diagnostic='readonly scoped inspector' if negative else None, dump=True)
			if mode == 'negative':
				continue
			for level in ['-O0', '-O1', '-O2']:
				binary = out / (form + level)
				run([compiler, level, source, '-o', binary])
				receipt['products'][str(binary)] = dict(sha256=sha(binary), bytes=binary.stat().st_size)
				run([binary])
				run(['valgrind', '--default-suppressions=no', '--leak-check=full',
					'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], memory=True)

	assert sha(compiler) == receipt['compiler_sha256']
	assert sha(Path(__file__)) == receipt['recipe_sha256']
	assert sha(fixture) == receipt['fixture_sha256']
	for path, digest in receipt['sources'].items():
		assert sha(Path(path)) == digest
	receipt['peak_child_rss_kib'] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
