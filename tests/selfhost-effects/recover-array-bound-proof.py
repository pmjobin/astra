#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent integer oracle for the production constant-bound parser."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('array_bound_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('array-bound-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, expected=0):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-2000:])
		return r
	views = load_module('array_bound_AST_views', ROOT/'tests/selfhost-effects/recover-r4-original-view.py')
	inputs, selections = [], []
	for relative, declaration in [('compiler/semantic/elaborate.astra', b'int checked_decimal('), ('compiler/semantic/recover-arrays.astra', b'int recover_array_decimal(')]:
		source = ROOT/relative
		data = source.read_bytes()
		first = data.index(declaration)
		last = data.index(b'\n}\n', first)+3
		fragment = data[first:last]
		target = leaf/source.name
		target.write_bytes(fragment)
		original = views.declarations(run([C0, '--dump-syntax', source], source.stem+'-original-AST').stdout.decode())
		selected = views.declarations(run([C0, '--dump-syntax', target], source.stem+'-selected-AST').stdout.decode())
		assert len(selected) == 1 and selected[0] in original
		selections.append(dict(path=str(source), source_sha256=sha(source), first=first, last=last, fragment_sha256=hashlib.sha256(fragment).hexdigest(), view=str(target), exact_AST_sha256=hashlib.sha256(selected[0].encode()).hexdigest()))
		inputs.append(target)
	witness = read(paths.RUNTIME.parent/'effects25-r5/original-before-O0/result.json')
	host = Path(witness['inputs'][2]['path'])
	assert sha(host) == witness['inputs'][2]['sha256']
	inputs.append(host)
	provider = build/'text-ops-posix.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'lib/runtime/platform/text-ops-posix.c', '-o', provider], 'provider-build')
	cases = []
	for maximum in [*range(21), 127, 255, 65535, 16777216, 2147483647]:
		for value in sorted({*range(25), max(0, maximum-1), maximum, maximum+1, 2147483647, 2147483648, 9999999999999999999999999}):
			cases.append((str(value), maximum, value if value <= maximum else -1))
	for maximum in (0, 1, 2147483647):
		for text in ('', '-1', '+1', 'x', '1x', ' 1'):
			cases.append((text, maximum, -1))
	caller = leaf/'caller.astra'
	checks = ['\tif (recover_array_decimal('+json.dumps(text)+', '+str(maximum)+') != '+str(expected)+') return 3;' for text, maximum, expected in cases]
	caller.write_text('int main() {\n'+'\n'.join(checks)+'\n\treturn 42;\n}\n')
	profiles = []
	for mode in ('O0', 'O2'):
		exe = build/('bounds-'+mode)
		run([C0, '-'+mode, caller, *inputs, '--link-object', provider, '-o', exe], mode+'-build')
		run([exe], mode+'-execute', 42)
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], mode+'-memory', 42)
		assert all(marker in memory.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		profiles.append(dict(mode=mode, ELF_sha256=sha(exe), exit=42, cases=len(cases), unsuppressed_returning_memory=True))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_PRODUCTION_BOUND_PREFLIGHT', selections=selections, caller_sha256=sha(caller), cases=cases, profiles=profiles, Astra_native_execution_credit=0, limitation='Exact production parser definitions and AST subtrees execute under unchanged C0 against Python arbitrary-precision integer/comparison results. Includes the small-limit truncating-division regression, negative and overflowing inputs. This focused helper proof does not replace actual Astra source rejection or positive array execution.'), indent=2)+'\n')
	print(len(cases), 'independent integer bound cases pass C0 O0/O2 and unsuppressed memory; zero Astra execution credit', flush=True)


if __name__ == '__main__':
	main()
