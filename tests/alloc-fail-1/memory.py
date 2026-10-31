# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal-stage, error-return and separately classified fatal memory."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('inherited', ROOT / 'tests/gen-buffer-1/memory.py')
inherited = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inherited)


def qualify(args):
	out = args.output.resolve()
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	source = out / 'ordinary-name-control.astra'
	source.write_text('int f(){' + ''.join('int C%d=0;' % i for i in range(5001)) + 'return 0;}')
	assert hashlib.sha256(source.read_bytes()).hexdigest() == '926d5a295e7a62db4fc11c96a59d71437e5cc96026ee092d31dca696a2965927'
	prior = json.loads((ROOT / 'build/gen-buffer-1/independent-gen-buffer-1-memory/candidate-inherited.json').read_text())
	rows = []
	def run(name, category, command, status=0, extra=None):
		log = out / (name + '.log')
		argv = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(log), *map(str, command)]
		p = subprocess.run(argv, cwd=out, env=env | (extra or {}), capture_output=True)
		(out / (name + '.stdout')).write_bytes(p.stdout)
		(out / (name + '.stderr')).write_bytes(p.stderr)
		text = log.read_text()
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, category=category, argv=argv, status=p.returncode, expected_status=status, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
		rows.append(row)
		(out / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert 'ERROR SUMMARY:' in text and row['suppressed'] == 0 and p.returncode == status, row
		if category == 'inherited-control':
			assert row['errors'] == 2 and row['definite'] == 49152 and row['indirect'] == row['possible'] == 0, row
			stacks = {}
			for block in re.split(r'\n==\d+==\s*\n', text):
				match = re.search(r'([\d,]+) bytes in 1 blocks are definitely lost', block)
				if match:
					stacks[match[1]] = [inherited.frame_identity(frame) for frame in re.findall(r'(?:at|by) 0x[0-9A-F]+: (.+)', block)]
			assert stacks == prior['loss_stack_identities'], (stacks, prior['loss_stack_identities'])
			row['loss_stack_identities'] = stacks
		elif category != 'fatal-no-caller-unwinding':
			assert row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
		(out / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
		print(name, category, row['status'], row['definite'], flush=True)
	build = args.build.resolve()
	for label, compiler in [('baseline', args.baseline.resolve()), ('candidate', build / 'astrac')]:
		run(label + '-5001', 'inherited-control', [compiler, '--dump-semantics', source], 99)
	for stage in ['core', 'cfg', 'ssa', 'pipeline', 'llvm']:
		run(stage, 'normal-model', [build / 'tests/alloc-fail-1' / ('astra-alloc-fail-' + stage), '--tap'])
	program = out / 'normal.astra'
	program.write_text('struct R{int x;f64 y;}void report<T>(T value,int n){}owned T[] make<T>(int n){return new T[n] else report(n,n);}int main(){var old=make<R>(2);old=new R[3] else report(len(old),3);var saved=old[0];return saved.x;}\n')
	run('normal-compiler', 'normal-compiler', [build / 'astrac', program, '-o', out / 'normal'])
	run('normal-owner-runtime', 'normal-runtime', [out / 'normal'])
	(out / 'bad.astra').write_text('int report(){return 0;}int main(){var a=new int[0] else report();return 0;}\n')
	run('diagnostic-return', 'normal-error-return', [build / 'astrac', '--dump-llvm', out / 'bad.astra'], 1)
	(out / 'missing.astra').write_text('extern(C) void missing(int n);int main(){var a=new int[2] else missing(2);return 0;}\n')
	run('link-error-return', 'normal-error-return', [build / 'astrac', out / 'missing.astra', '-o', out / 'must-not-exist'], 1)
	assert not (out / 'must-not-exist').exists()
	if args.execution:
		binary = args.execution.resolve() / 'O2-gcc'
		for case, category, status in [(0, 'normal-runtime', 0), (36, 'normal-generic-runtime', 0), (38, 'normal-mixed-runtime', 0), (16, 'fatal-no-caller-unwinding', -4), (39, 'fatal-no-caller-unwinding', -4)]:
			run('effects-' + str(case), category, [binary], status, {'ASTRA_ALLOC_CASE': str(case)})
	if args.client:
		run('installed-consumer', 'normal-installed-runtime', [args.client.resolve() / 'installed/consumer-0-gcc'])
	print('Unsuppressed normal, fatal and exact inherited-control categories retained separately')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--baseline', type=Path, required=True)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--execution', type=Path)
	parser.add_argument('--client', type=Path)
	args = parser.parse_args(); args.output = fresh_output(args.output)
	qualify(args)
