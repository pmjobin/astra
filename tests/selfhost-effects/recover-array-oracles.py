#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent unchanged C0 array semantics before adding source admission."""
import argparse
import json
import os
import time
from state import ROOT, C0, load_module, bounded_run, sha

CASES = {
	'fixed-zero': 'int main() { u8[0] bytes = {}; return len(bytes) + 42; }\n',
	'fixed-slice': 'int read(u8[] bytes) { if (len(bytes) != 1) return 3; return bytes[0] as int; }\nint main() { u8[4] bytes = {1, 42, 3, 4}; return read(slice(bytes, 1, 1)); }\n',
	'empty-slice': 'int read(u8[] bytes) { return len(bytes) + 42; }\nint main() { u8[1] bytes = {42}; return read(slice(bytes, 1, 0)); }\n',
	'explicit-borrow-write': 'int write(borrowed u8[] bytes) { bytes[0] = 42; return bytes[0] as int; }\nint main() { var bytes = new u8[1]; return write(bytes); }\n',
	'readonly-owned-field': 'class Bytes { readonly owned u8[] storage; init() { this.storage = new u8[1]; } int write() { this.storage[0] = 42; return this.storage[0] as int; } }\nint main() { var bytes = new Bytes(); return bytes.write(); }\n',
	'index-before-RHS-fatal': 'extern(C) int tick();\nint main() { var bytes = new u8[1]; bytes[2] = tick() as u8; return 42; }\n',
	'fixed-index-before-RHS-fatal': 'extern(C) int tick();\nint bad_index() { return 2; }\nint main() { u8[1] bytes = {0}; bytes[bad_index()] = tick() as u8; return 42; }\n',
}


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	p.add_argument('--case', choices=tuple(CASES), action='append')
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('array_oracle_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('array-oracles-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, allowed):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stderr.splitlines()[:3])
		return r
	provider = leaf/'provider.c'
	provider.write_text('#include <stdint.h>\n#include <unistd.h>\nint32_t tick(void) { const char text[] = "RHS\\n"; ssize_t count = write(STDOUT_FILENO, text, sizeof text - 1); return count == 4 ? 42 : 3; }\n')
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build', (0,))
	rows = []
	for name, text in CASES.items():
		if a.case and name not in a.case:
			continue
		source = leaf/(name+'.astra')
		source.write_text(text)
		profiles = []
		for mode in ('O0', 'O2'):
			exe = build/(name+'-'+mode)
			compiled = run([C0, '-'+mode, source, '--link-object', obj, '-o', exe], name+'-'+mode+'-build', (0, 1))
			if compiled.returncode != 0:
				profiles.append(dict(mode=mode, C0_source_rejected=True, diagnostic=compiled.stderr.decode(errors='replace')))
				continue
			fatal = name.endswith('-fatal')
			expected = (132, -4) if fatal else (42,)
			observed = run([exe], name+'-'+mode+'-execute', expected)
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', expected)
			if not fatal:
				assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			assert observed.stdout == memory.stdout
			profiles.append(dict(mode=mode, C0_source_rejected=False, ELF_sha256=sha(exe), exit=observed.returncode, fatal=fatal, stdout=observed.stdout.decode(errors='replace'), returning_clean_memory=not fatal))
		rows.append(dict(name=name, source_sha256=sha(source), profiles=profiles))
		(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C0_ARRAY_ORACLES', programs=rows, C0_sha256=sha(C0), Astra_native_credit=0, limitation='Original C0 source-policy, evaluation-order and memory observations only. Rejected source remains rejected. Fatal memory receipts are retained and never described as returning clean memory.'), indent=2)+'\n')
		print(name, ['C0 rejected' if row['C0_source_rejected'] else row['exit'] for row in profiles], flush=True)


if __name__ == '__main__':
	main()
