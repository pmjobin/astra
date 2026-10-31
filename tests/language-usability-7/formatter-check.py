# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise public formatter safety, full-grammar samples, tokens and execution."""
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
	out = Path(tempfile.mkdtemp(prefix='formatter-', dir=output))
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	rows = []
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows, products={})
	def run(argv, expected=0, stdout=None, stderr=None):
		argv = list(map(str, argv))
		p = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout)
		valid &= (not p.stderr if stderr is None else stderr in p.stderr)
		rows.append(dict(command=argv, actual_exit=p.returncode, expected_exit=expected,
			stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), stderr=p.stderr.decode(errors='replace'), passed=bool(valid)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, (rows[-1], p.stdout)
		return p.stdout
	run([compiler, '--format', '--version'], stdout=b'astrac format 1\n')
	inputs = sorted(set([
		*ROOT.glob('lib/astra/**/*.astra'),
		*ROOT.glob('examples/owned-state-6/*.astra'),
		*ROOT.glob('examples/language-runtime-4/*.astra'),
		HERE/'for-control.astra', HERE/'for-checked.astra', HERE/'comparison-chain.astra', HERE/'foreach-bag.astra', HERE/'with-control.astra', HERE/'with-explicit.astra', *ROOT.glob('examples/language-usability-7/*.astra'), HERE/'float-text.astra',
	]))
	receipt['sources'] = {str(p.relative_to(ROOT)): sha(p) for p in inputs}
	for index, path in enumerate(inputs):
		before = (path.read_bytes(), path.stat())
		formatted = run([compiler, '--format', path])
		target = out/f'formatted-{index}.astra'; target.write_bytes(formatted)
		assert run([compiler, '--format', target]) == formatted
		run([compiler, '--format', '--check', target], stdout=b'')
		assert run([compiler, '--dump-syntax', path]) == run([compiler, '--dump-syntax', target])
		after = (path.read_bytes(), path.stat())
		assert before == after, f'formatter mutated {path}'
		# Braces and comment markers inside literal spellings are never structure.
	source = out/'messy.astra'
	source.write_bytes(b'// literal escapes: \\0 \\t\nint main() {\n    /* block {\n       exact comment indentation */\n    string text = "\xc3\xa9{ /* \\0\\t"; // } stays comment\n    for (int i = 0;\n      i < 2; i = i + 1) {\n       if (text.byte_length != 9) { return 1; }\n    }\n    return 0;\n}\n')
	original = source.read_bytes()
	formatted = run([compiler, '--format', source])
	assert b'\n\tstring text' in formatted and b'\n\t\ti < 2;' in formatted
	assert b'/* block {\n       exact comment indentation */' in formatted
	assert b'"\xc3\xa9{ /* \\0\\t"; // } stays comment' in formatted
	assert source.read_bytes() == original
	run([compiler, '--format', '--check', source], expected=1, stdout=b'', stderr=b'formatting differs')
	target = out/'new.astra'
	run([compiler, '--format', source, '-o', target], stdout=b'')
	assert target.read_bytes() == formatted
	run([compiler, '--format', source, '-o', target], expected=2, stdout=b'', stderr=b'cannot create new formatter output')
	assert target.read_bytes() == formatted
	run([compiler, '--format', source, '-o', source], expected=2, stdout=b'', stderr=b'cannot create new formatter output')
	assert source.read_bytes() == original
	for opt in ['-O0', '-O1', '-O2']:
		for path in [source, target]:
			exe = out/(path.stem+opt)
			run([compiler, opt, path, '-o', exe], stdout=b'')
			run([exe], stdout=b'')
			receipt['products'][exe.name] = sha(exe)
	run([compiler, '--format', '--in-place', source], stdout=b'')
	assert source.read_bytes() == formatted
	metadata = source.stat()
	run([compiler, '--format', '--in-place', source], stdout=b'')
	assert source.stat() == metadata
	for name, text, location in [
		('for', b'int main() {\n\tfor (;; value = ) {}\n}\n', b':2:18: error:'),
		('chain', b'int main() {\n\tif (1 < 2 < ) {}\n}\n', b':2:14: error:'),
		('foreach', b'int main() {\n\tforeach (var item from bag) {}\n}\n', b':2:20: error:'),
		('with', b'int main() {\n\twith (var c = ) {}\n}\n', b':2:16: error:'),
		('literal', b'int main() { string x = "\\q"; }\n', b'error:'),
	]:
		bad = out/(name+'.astra'); bad.write_bytes(text)
		for mode in [[], ['--in-place'], ['-o', target]]:
			run([compiler, '--format', *mode, bad], expected=1, stdout=b'', stderr=location)
			assert bad.read_bytes() == text and target.read_bytes() == formatted
	print(f'{len(rows)} formatter checks over {len(inputs)} source files; receipts: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
