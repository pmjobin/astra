#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare actual default allocator exhaustion with the independent C0 policy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MARKER = b'CLASS_STORAGE_TEST: calloc(4,8) refused\n'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('baseline', 'compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--case', required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == a.compiler_sha256
	rows = [row for row in json.loads(a.baseline.read_text()) if row['name'] == a.case]
	assert len(rows) == 1 and rows[0]['baseline_complete']; row = rows[0]
	sources = [Path(source['path']) for source in row['sources']]
	assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
	commands = []
	def run(argv, name, expected):
		start = time.monotonic(); environment = dict(os.environ, CCACHE_DISABLE='1')
		environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, timeout=180, env=environment)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-1800:]); return r
	injector = ROOT/'tests/selfhost-classstorage/allocation-fail.c'; obj = a.build/'allocation-fail.o'
	deps = subprocess.check_output(['gcc', '-M', injector], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
	inputs = {str(path):sha(path) for path in deps}
	run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-c', injector, '-o', obj], 'injector-build', 0)
	products = {label:a.build/(label+'-failure') for label in ('native', 'C0')}
	native = row['products']['object']; assert sha(native['path']) == native['sha256']
	run(['gcc', native['path'], obj, '-Wl,--wrap=calloc', '-o', products['native']], 'native-link-injector', 0)
	c0_object = a.build/'C0-failure.o'
	run([a.compiler, '-'+row['mode'], '--entry-object', *sources, '-o', c0_object], 'C0-emit-entry-object', 0)
	run(['gcc', c0_object, obj, '-Wl,--wrap=calloc', '-o', products['C0']], 'C0-link-injector', 0)
	observations = []
	for label, app in products.items():
		plain = run([app], label+'-exhaustion', -signal.SIGILL)
		assert plain.stdout == b'' and plain.stderr == MARKER
		xml = a.runtime/(label+'.xml')
		# The wrapper has a separate linker symbol; Memcheck still observes
		# the real libc allocator without bypassing the test refusal.
		memory = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml), app], label+'-instrumented-exhaustion', -signal.SIGILL)
		assert memory.stdout == b'' and memory.stderr.count(MARKER) == 1
		tree = ET.parse(xml).getroot(); kinds = [entry.findtext('kind') for entry in tree.findall('error')]
		assert all(kind.startswith('Leak_') for kind in kinds), kinds
		assert tree.find('fatal_signal') is not None and tree.findall('./status/state')[-1].text == 'FINISHED'
		observations.append(dict(role=label, application_sha256=sha(app), failure='SIGILL before reserve transfer/publication', valgrind_error_kinds=kinds, valgrind_xml_sha256=sha(xml), no_invalid_access_or_free=True, limitation='Fatal process termination does not unwind owners. Raw leak observations remain visible and are not a normal-exit memory-clean result.'))
	assert all(sha(path) == value for path,value in inputs.items())
	(a.runtime/'result.json').write_text(json.dumps(dict(status='MATCHED_C0_FATAL_ALLOCATION_POLICY', mode=row['mode'], baseline=dict(path=str(a.baseline),sha256=sha(a.baseline)), sources=row['sources'], compiler_sha256=sha(a.compiler), injector_inputs=inputs, injector_object_sha256=sha(obj), observations=observations, limitation='Only the explicitly selected default-allocator failure is tested. Fallible custom allocation and constructor rollback remain deferred.'), indent=2)+'\n')
	print(row['mode'], 'native/C0 default allocation failure both trap; raw fatal-exit leak observations retained')


if __name__ == '__main__':
	main()
