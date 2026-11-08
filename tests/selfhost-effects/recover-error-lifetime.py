#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual source Error snapshot allocation/retirement and fatal-size controls."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

PROGRAMS = {
	'empty-root': ('int main() { try { throw new Error(""); } catch (Error caught) { if (caught.message == "") return 42; return 3; } }\n', False),
	'one-byte-root': ('int main() { try { throw new Error("x"); } catch (Error caught) { if (caught.message == "x") return 42; return 3; } }\n', False),
	'counted-NUL-root': ('int main() { try { throw new Error("\\0x"); } catch (Error caught) { if (caught.message == "\\0x") return 42; return 3; } }\n', False),
	'derived-literal': ('class Detail : Error { init() : base("xyz") {} } int main() { try { throw new Detail(); } catch (Error caught) { if (caught.message == "xyz") return 42; return 3; } }\n', False),
	'original-InvalidUtf8': ('int main() { try { var bytes = new u8[1]; bytes[0] = 255; var message = utf8_message(bytes); return 3; } catch (InvalidUtf8 caught) { if (caught.message == "invalid UTF-8") return 42; return 4; } }\n', True),
}


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	if a.component:
		identity = read(a.component.with_suffix('.identity.json'))
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('error_lifetime_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-lifetime-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, environment=None, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		env = dict(os.environ, CCACHE_DISABLE='1')
		for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
			env.pop(key, None)
		invocation = ['/usr/bin/env', *[key+'='+value for key, value in environment.items()], *argv] if environment else argv
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *invocation], cwd=build, env=env, capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=invocation, test_environment=dict(environment or {}), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr.splitlines()[:3])
		return r
	prior = load_module('error_lifetime_interposer', ROOT/'tests/selfhost-effects/recover-r4-lifetime.py')
	provider = leaf/'observe.c'
	provider.write_text(prior.INTERPOSER)
	library = build/'observe.so'
	run(['cc', '-std=c11', '-O2', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', provider, '-o', library], 'observer-build')
	rows = []
	for name, (text, utf8) in PROGRAMS.items():
		source = leaf/(name+'.astra')
		source.write_text(text)
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		if utf8:
			inputs += [ROOT/'lib/astra/text/utf8-message.astra']
		oracle = build/(name+'-C0')
		run([C0, '-'+a.mode, *inputs, '-o', oracle], name+'-C0-build')
		products = [('C0', oracle)]
		if a.component:
			physical = build/(name+'.ll')
			optimized = build/(name+'-optimized.ll')
			obj = build/(name+'.o')
			exe = build/(name+'-Astra')
			run([a.component, '--native', physical, *inputs], name+'-Astra-emit')
			run(['opt', '-passes=verify', '-disable-output', physical], name+'-Astra-verify')
			run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], name+'-Astra-optimize')
			run(['opt', '-passes=verify', '-disable-output', optimized], name+'-Astra-optimized-verify')
			run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-Astra-object')
			run(['cc', '-no-pie', obj, '-o', exe], name+'-Astra-link')
			products.append(('Astra', exe))
		row = dict(name=name, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], profiles={})
		for label, exe in products:
			observed = run([exe], name+'-'+label+'-execute', allowed=(42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+label+'-memory', allowed=(42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and memory.stdout == observed.stdout
			trace_run = run([exe], name+'-'+label+'-trace', {'LD_PRELOAD':str(library)}, (42,))
			trace = [(event.decode(), int(index), int(size)) for event, index, size in re.findall(rb'^R4 ([AFX]) ([0-9]+) ([0-9]+)$', trace_run.stderr, re.M)]
			assert trace
			failure_sizes = sorted({1, 2, 3, 4, 13, 14, 32} | {size for event, _, size in trace if event == 'A'})
			failures = []
			for size in failure_sizes:
				expected_fatal = any(event == 'A' and amount == size for event, _, amount in trace)
				failure = run([exe], name+'-'+label+'-fail-size-'+str(size), {'LD_PRELOAD':str(library), 'ASTRA_R4_FAIL_SIZE':str(size)}, (132, -4) if expected_fatal else (42,))
				if expected_fatal:
					assert ('R4 X 0 '+str(size)+'\n').encode() in failure.stderr
				else:
					assert b'R4 X ' not in failure.stderr
				failures.append(dict(size=size, exit=failure.returncode, fatal=expected_fatal, returning_memory_credit=False))
			row['profiles'][label] = dict(ELF_sha256=sha(exe), stdout_sha256=sha(leaf/(name+'-'+label+'-execute.stdout')), stderr_sha256=sha(leaf/(name+'-'+label+'-execute.stderr')), trace=trace, failures=failures)
		if a.component:
			assert row['profiles']['Astra']['trace'] == row['profiles']['C0']['trace']
			assert row['profiles']['Astra']['failures'] == row['profiles']['C0']['failures']
			assert row['profiles']['Astra']['stdout_sha256'] == row['profiles']['C0']['stdout_sha256'] and row['profiles']['Astra']['stderr_sha256'] == row['profiles']['C0']['stderr_sha256']
		rows.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_ERROR_LIFETIME_CONTROLS' if a.component else 'INDEPENDENT_C0_ERROR_LIFETIME_ORACLES', profile=a.mode, component_sha256=sha(a.component) if a.component else None, interposer_source_sha256=sha(provider), interposer_ELF_sha256=sha(library), programs=rows, limitation='Interposition targets only named source-generated executables, never the compiler or Valgrind. Returning Valgrind runs use no interposer or suppressions. Fatal traces/signals are preserved and earn no returning-memory credit. Helper-only tests do not replace this source-to-native comparison.'), indent=2)+'\n')
		print(a.mode, name, 'actual Astra/C0 lifetime match' if a.component else 'C0 source allocation/fatal oracle', flush=True)


if __name__ == '__main__':
	main()
