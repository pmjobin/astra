#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify existing borrowed payload identity without adding Shared value equality."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_arg, output_arg):
	compiler, out = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	rows = []
	def run(argv, expected=0):
		r = subprocess.run(list(map(str, argv)), capture_output=True, cwd=out, timeout=120)
		rows.append({'argv': list(map(str, argv)), 'exit': r.returncode, 'stdout': r.stdout.decode(errors='replace'), 'stderr': r.stderr.decode(errors='replace')})
		(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert r.returncode == expected, rows[-1]
		return r
	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'identity-observer.c', '-o', observer])
	for mode in ('O0', 'O2'):
		program = out / ('identity-' + mode)
		run([compiler, '-' + mode, HERE / 'identity.astra', '--link-object', observer, '-o', program])
		run([program])
		run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program])
	core = run([compiler, '--dump-core', HERE / 'identity.astra']).stdout.decode()
	body = core.split('(function "handle_same"', 1)[1].split('\n\t(function ', 1)[0]
	assert body.count('SHARED_ACTION_BORROW') == 2
	assert all(word not in body for word in ('SHARED_ACTION_CLONE', 'SHARED_ACTION_ACQUIRE', '(owned-initialize', '(release'))
	prefix = (HERE / 'identity.astra').read_text().split('int main()', 1)[0]
	setup = 'var p=new IdentityPayload(7);var root=shared_acquire(move p);'
	negatives = {
		'direct-handle-equality': setup + 'var copy=shared_clone(root);if(root==copy){return 0;}return 1;',
		'weak-operand': setup + 'var weak=shared_downgrade(root);if(handle_same(root,weak)){return 0;}return 1;',
		'released-operand': setup + 'release root;if(handle_same(root,root)){return 0;}return 1;',
		'escaped-projection': setup + 'var escaped=shared_borrow(root);return 0;',
		'wrong-payload': setup + 'var q=new OtherPayload();var other=shared_acquire(move q);if(handle_same(root,other)){return 0;}return 1;',
		'borrow-and-consume': setup + 'if(consume(shared_borrow(root),move root)){return 0;}return 1;',
	}
	for name, body in negatives.items():
		path = out / (name + '.astra')
		path.write_text(prefix + 'class OtherPayload {init(){}} bool consume(borrowed IdentityPayload p,owned shared IdentityPayload s){return true;} int main(){' + body + '}\n')
		r = run([compiler, '--check', path], 1)
		assert b'error:' in r.stderr and b'internal error' not in r.stderr.lower()
	result = {'status': 'PASS', 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'profiles': ['O0', 'O2'], 'negative_cases': list(negatives), 'comparison_acquisitions': 0, 'comparison_consumes': 0, 'implementation': 'existing borrowed native Class reference identity; no compiler extension'}
	(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
	print(json.dumps(result, indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
