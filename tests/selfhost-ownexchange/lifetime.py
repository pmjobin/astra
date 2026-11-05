#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe allocation identity and exact cleanup without implementing exchange."""
import argparse
import json
import os
from pathlib import Path
import resource
import re
import signal
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, C0, read, sha
from corpus import BOX


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--name', required=True); a = p.parse_args()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	commands = []; rows = []
	def run(argv, name, expected=0):
		env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS', None); env.pop('LD_PRELOAD', None)
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=build, capture_output=True, timeout=180, env=env)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-2000:]); return r
	valid = next(row for row in read(RUNTIME/'corpus-v1/selection.json') if row['name'] == 'local-field'); normal = Path(valid['sources'][0]['path']).read_text()
	guard = BOX+'void exchange(borrowed Box a, borrowed Box b) { swap(a.data, b.data); }\n'
	cases = {'normal': (normal, 14, []), 'failed-later-replacement': (normal.replace('return 14;', 'grown = new int[9]; return 14;'), -signal.SIGILL, ['-DFAIL_REPLACEMENT']), 'left-null-guard': (guard+'int main() { var b = new Box(); exchange(null, b); return 99; }\n', -signal.SIGILL, []), 'right-null-guard': (guard+'int main() { var a = new Box(); exchange(a, null); return 99; }\n', -signal.SIGILL, [])}
	for name, (source, expected, defines) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		observer = build/(name+'-observer.o'); run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *defines, '-c', ROOT/'tests/selfhost-ownexchange/observer.c', '-o', observer], name+'-observer')
		objects = {'native': build/(name+'-native.o'), 'C0': build/(name+'-C0.o')}
		run([a.component, '--classstorage-emit-obj', a.mode, objects['native'], path], name+'-native-compile')
		run([C0, '-'+a.mode, '--entry-object', path, '-o', objects['C0']], name+'-C0-compile')
		observed = {}
		for role, obj in objects.items():
			app = build/(name+'-'+role); run(['gcc', obj, observer, '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-o', app], name+'-'+role+'-link')
			r = run([app], name+'-'+role+'-execute', expected); observed[role] = r.stderr.decode()
			xml = leaf/(name+'-'+role+'.xml'); memory = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--xml=yes', '--xml-file='+str(xml), app], name+'-'+role+'-memory', expected)
			assert memory.stdout == r.stdout
			trace_lines = [line for line in memory.stderr.decode().splitlines() if re.fullmatch(r'(?:A|F) [0-9]+ [0-9]+|FAIL 36', line)]
			assert ('\n'.join(trace_lines)+'\n').encode() == r.stderr
			if expected >= 0:
				assert memory.stderr == r.stderr and ET.parse(xml).getroot().find('error') is None
			rows.append(dict(name=name, role=role, exit=expected, source_sha256=sha(path), object_sha256=sha(obj), application_sha256=sha(app), trace=observed[role], xml_sha256=sha(xml), normal_exit_memory_clean=expected >= 0, limitation='Fatal traps retain allocations and do not unwind.' if expected < 0 else None))
		assert observed['native'] == observed['C0'], (name, observed)
		if name == 'normal': assert observed['native'] == 'A 1 32\nA 2 8\nA 3 12\nA 4 28\nF 2 8\nF 3 12\nF 4 28\nF 1 32\n'
		elif name == 'failed-later-replacement': assert observed['native'] == 'A 1 32\nA 2 8\nA 3 12\nA 4 28\nFAIL 36\n'
		else: assert observed['native'] == 'A 1 32\nA 2 8\nA 3 12\n'
		(leaf/'observations.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, 'allocation identities/cleanup C0 match', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), observer_sha256=sha(ROOT/'tests/selfhost-ownexchange/observer.c'), observations=rows, limitation='Test-only libc allocation/free observation performs no owner algorithm. Exact no-extra-allocation exchange region is independently checked in retained LLVM IR; guard control order is separately checked there. Fatal cases establish trap behavior, not normal cleanup.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
