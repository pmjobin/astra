# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise missing snapshots, wrong observations and compiler error propagation."""
from pathlib import Path
import json
import subprocess
import sys
sys.dont_write_bytecode = True
from pipeline import collect, observations


def main(compiler, collector, output):
	compiler = compiler.resolve(strict=True)
	collector = collector.resolve(strict=True)
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	out = fresh_output(output)
	out.mkdir()
	source = out / 'valid.astra'
	source.write_text('int main(){return 42;}\n')
	checks = []
	def run(argv, cwd):
		p = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, text=True, timeout=30)
		assert p.returncode == 0 and not p.stderr, (p.returncode, p.stderr)
		return p.stdout
	observations(compiler, collector, [source], out, 'valid', run, out, public=True)
	checks.append('two fresh pipelines match all nine public CLI snapshots')
	for fault in ['missing', 'wrong']:
		wrapper = out / (fault + '.py')
		wrapper.write_text('#!/usr/bin/env python3\nimport pathlib,subprocess,sys\nsubprocess.run([' + repr(str(collector)) + ',*sys.argv[1:]],check=True)\np=pathlib.Path(sys.argv[1])/"ssa"\n' + ('p.unlink()\n' if fault == 'missing' else 'p.write_text("wrong observation\\n")\n'))
		wrapper.chmod(0o755)
		try:
			observations(compiler, wrapper, [source], out, fault, run, out, public=True)
		except AssertionError:
			checks.append(fault + ' snapshot refused')
		else:
			raise AssertionError(fault + ' accepted')
	invalid = out / 'invalid.astra'
	invalid.write_text('int main(){return missing_name;}\n')
	try:
		collect(collector, [invalid], out / 'invalid', out, run)
	except AssertionError as error:
		assert 'missing_name' in str(error)
		checks.append('real compiler diagnostic and nonzero exit propagated')
	else:
		raise AssertionError('invalid source accepted')
	(out / 'checks.json').write_text(json.dumps(dict(status='PASS', checks=checks), indent=2) + '\n')
	print(out / 'checks.json')


if __name__ == '__main__':
	main(*map(Path, sys.argv[1:]))
