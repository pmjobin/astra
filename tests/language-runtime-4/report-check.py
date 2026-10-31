# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A32 combines shared observation, closures, interfaces, properties and file I/O."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APP = ROOT/'examples/language-runtime-4/observer-report.astra'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'text/scalar-format', 'hosted/text-ops', 'hosted/files', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	providers = [ROOT/f'lib/astra/platform/{name}-posix.c' for name in ['args', 'text', 'text-ops', 'files']] + [HERE/'report-observer.c']
	receipt = dict(compiler_sha256=sha(compiler), sources={str(p.relative_to(ROOT)): sha(p) for p in [APP, *LIBS, *providers]}, commands=[], products={}, comparisons=[], valgrind=0)

	def run(argv, code=0, memory=False):
		argv = list(map(str, argv))
		result = subprocess.run(argv, capture_output=True, cwd=ROOT, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		receipt['commands'].append(dict(argv=argv, exit=result.returncode,
			stdout_hex=result.stdout.hex(), stderr_hex=result.stderr.hex()))
		(out/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert result.returncode == code and not result.stdout, (argv, result.returncode, result.stdout, result.stderr)
		if memory:
			assert b'ERROR SUMMARY: 0 errors' in result.stderr and b'in use at exit: 0 bytes in 0 blocks' in result.stderr, result.stderr
			receipt['valgrind'] += 1
		else:
			assert not result.stderr, (argv, result.stderr)

	links = []
	for provider in providers:
		obj = out/(provider.stem+'.o')
		run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj])
		links.extend(['--link-object', obj])
	vg = ['valgrind', '--default-suppressions=no', '--leak-check=full',
		'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=97']
	for level in [0, 1, 2]:
		native = out/f'observer-report-O{level}'
		run([compiler, f'-O{level}', *LIBS, APP, *links, '-o', native])
		receipt['products'][native.name] = sha(native)
		for label, data, bias in [('empty', b'', 0), ('records', bytes([0, 7, 128, 255]), 3), ('many', bytes(range(64)), 17)]:
			input_path, output_path = out/(label+'.bin'), out/f'{label}-O{level}.txt'
			input_path.write_bytes(data)
			values = [2*(byte+bias) for byte in data]
			expected = ''.join(f'{index}:{value}\n' for index, value in enumerate(values)).encode()
			expected += f'records={len(data)} total={sum(values)} expired=1\n'.encode()
			for memory in [False, True]:
				run([*(vg if memory else []), native, input_path, output_path, bias], memory=memory)
				actual = output_path.read_bytes()
				assert actual == expected, (level, label, actual, expected)
				receipt['comparisons'].append(dict(input_sha256=sha(input_path), output_sha256=sha(output_path), expected_sha256=hashlib.sha256(expected).hexdigest(), memory=memory))
		run([native, out/'missing-input', out/'unwritten', 3], code=2)
		full = out/'records.bin'
		run([*vg, native, full, out/'missing-parent'/'report', 3], code=2, memory=True)
		run([native, full, out/'invalid', -1], code=64)
		huge = out/'too-many.bin'; huge.write_bytes(bytes(range(65)))
		run([native, huge, out/'too-many.txt', 3], code=64)
	(out/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print('A32 composed observer report: PASS')


if __name__ == '__main__':
	main(*sys.argv[1:])
