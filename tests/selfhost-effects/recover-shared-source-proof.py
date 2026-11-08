#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0 and actual source-bound Shared stage observations."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	p.add_argument('--observer', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.observer.with_suffix('.identity.json'))
	assert sha(a.observer) == identity['sha256']
	paths = load_module('shared_source_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('shared-source-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	corpus = load_module('shared_source_corpus', ROOT/'tests/selfhost-effects/recover-shared-sources.py').corpus()
	commands = []
	rows = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr[-3000:])
		return r
	for name, text in corpus.items():
		source = leaf/(name+'.astra')
		source.write_text(text)
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		observation = run([a.observer, *inputs], name+'-types', (42,))
		facts = [list(map(int, line.split()[1:])) for line in observation.stdout.decode().splitlines() if line.startswith('SHARED ')]
		assert facts and all(row in ([1, 27, 4, 19], [2, 27, 4, 19], [3, 31, 2, 19]) for row in facts)
		assert all(marker in observation.stdout for marker in (b'SHARED_CORE_VALID', b'SHARED_CFG_VALID', b'SHARED_SSA_VALID'))
		products = []
		for mode in ('O0', 'O2'):
			exe = build/(name+'-'+mode)
			run([C0, '-'+mode, *inputs, '-o', exe], name+'-'+mode+'-build')
			run([exe], name+'-'+mode+'-execute', (42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', (42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			products.append(dict(profile=mode, ELF_sha256=sha(exe), actual_exit=42))
		rows.append(dict(name=name, source_sha256=sha(source), actual_error=not name.endswith('-success'), conditional_type_facts=facts, actual_stages=['Flow', 'Core', 'CFG', 'SSA'], C0=products))
		(leaf/'result.json').write_text(json.dumps(dict(status='SHARED_SOURCE_PREFLIGHT', programs=rows, observer_sha256=sha(a.observer), Astra_native_credit=0, limitation='Actual source-bound Flow/Core/CFG/SSA consumers and mutation twins execute over these source bytes. C0 independently establishes source semantics and returning memory. No Astra target ELF or original-function execution credit.'), indent=2)+'\n')
		print(name, 'C0 O0/O2 and actual Flow/Core/CFG/SSA', flush=True)


if __name__ == '__main__':
	main()
