# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unicode scalar/value composition with independent Python byte/scalar oracles."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='unicode-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	library = [ROOT/'lib/astra'/name for name in ['base/errors.astra', 'collections/bag.astra',
		'collections/vector.astra', 'text/utf8-message.astra', 'text/utf8-byte-builder.astra',
		'hosted/text.astra', 'hosted/text-ops.astra', 'text/unicode-scalars.astra']]
	values, boundaries = HERE/'unicode-values.astra', HERE/'unicode-boundaries.astra'
	providers = [ROOT/'lib/runtime/platform'/name for name in ['args-posix.c', 'text-posix.c', 'text-ops-posix.c']]+[HERE/'unicode-observer.c']
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [*library, values, boundaries, *providers, Path(__file__).resolve()]}, checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'internal ', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed),
			astra_inputs={arg: sha(Path(arg)) for arg in argv if arg.endswith('.astra') and Path(arg).is_file()}))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]
		return result.stdout

	for source in [values, boundaries]:
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, *library, source], stdout=None)
	for source in [library[-1], values, boundaries]:
		run([compiler, '--format', '--check', source])
	objects = []
	for provider in providers:
		obj = out/(provider.stem+'.o'); objects.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj])
	links = [item for obj in objects for item in ['--link-object', obj]]
	def expected_values(text, number):
		rows = [str(len(text.encode())), str(len(text))]
		for index, scalar in enumerate(text):
			rows += [str(len(text[:index].encode())), str(ord(scalar))]
		rows += [str(len(text.encode()))]
		if len(text) > 1:
			rows += [text[1:-1]]
		rows += [str(len(text.split('|'))), *text.split('|')]
		if number in ['2147483648', '-2147483649', '+1', '', '1x', '１２']:
			return ('\n'.join(rows+['invalid signed decimal'])+'\n').encode(), 92
		return ('\n'.join(rows+[str(int(number))])+'\n').encode(), 0
	text = 'A\0λ🙂e\u0301|42'
	boundary_rows = [text, str(len(text.encode())), str(len(text)), *map(str, [0, ord('λ'), ord('🙂'), ord('\u0301'), len(text.split('|')[0].encode())]),
		text[1:4], *text.split('\0'), *text.split('🙂'), '1', '2', '3', text, '2', '1', str(ord('🙂')), '🙂', '🙂A', '2', '3', '4', '1', '2', str(0x10ffff), '0']
	boundary_output = ('\n'.join(boundary_rows)+'\n').encode()
	cases = [('λ🙂|e\u0301|42', '-2147483648'), ('|a||', '2147483647'), ('', '0'),
		('ASCII', '-0'), ('\U0010ffff|é|中', '0017'), ('one|two', '2147483648'),
		('e\u0301', '-2147483649'), ('x', '+1'), ('x', ''), ('x', '1x'), ('x', '１２')]
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('unicode-values'+level)
		run([compiler, level, *library, values, *links, '-o', executable]); receipt['products'][str(executable)] = sha(executable)
		for text, number in cases:
			expected, status = expected_values(text, number)
			run([executable, text, number], expected=status, stdout=expected)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable, text, number], expected=status, memory=True, stdout=expected)
		executable = out/('unicode-boundaries'+level)
		run([compiler, level, *library, boundaries, *links, '-o', executable]); receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=boundary_output)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=boundary_output)
		dependencies = run(['readelf', '-d', executable], stdout=None)
		assert all(name not in dependencies.lower() for name in [b'glib', b'gobject', b'uring', b'pcre', b'regex'])
	for name, before, after, diagnostic in [
		('mutable-backing', 'builder.snapshot()', 'utf8_message(builder.backing)', 'private'),
		('owning-record-copy', 'var report = unicode_analyze(args[1]);', 'var report = unicode_analyze(args[1]); var alias = report;', 'copyable field graph'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(values.read_text().replace(before, after, 1))
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, *library, invalid], expected=1, diagnostic=diagnostic)
	invalid = out/'unsafe-byte-text.astra'
	invalid.write_text('int main(){u8[1] bytes={255}; string text=slice(bytes,0,1); return text.byte_length;}\n')
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, invalid], expected=1, diagnostic='string')
	receipt['status'] = 'PASS'
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {len(receipt["checks"])} Unicode commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
