#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe replacement retirement before taken-owner retirement, independently."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
TRACE = b'retire old 4\nretire result 9\n'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('baseline', 'compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	rows = [row for row in json.loads(a.baseline.read_text()) if row['name'] == 'class-replace']; assert len(rows) == 1 and rows[0]['baseline_complete']; row = rows[0]
	assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
	commands = []
	def run(argv, name, expected):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-1800:]); return r
	observer = ROOT/'tests/selfhost-genclass/retirement.c'; obj = a.build/'retirement.o'
	run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-c', observer, '-o', obj], 'observer-build', 0)
	objects = {'native':Path(row['products']['object']['path']), 'C0':a.build/'C0.o'}
	assert sha(objects['native']) == row['products']['object']['sha256']
	run([a.compiler, '-'+row['mode'], '--entry-object', *[source['path'] for source in row['sources']], '-o', objects['C0']], 'C0-entry-object', 0)
	observations = []
	for label, source in objects.items():
		app = a.build/label
		run(['gcc', source, obj, '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-o', app], label+'-link', 0)
		plain = run([app], label+'-execute', 9); assert plain.stdout == b'' and plain.stderr == TRACE
		xml = a.runtime/(label+'.xml')
		memory = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--xml=yes', '--xml-file='+str(xml), app], label+'-memory', 9)
		assert memory.stdout == b'' and memory.stderr == TRACE
		tree = ET.parse(xml).getroot(); assert not tree.findall('error') and tree.findall('./status/state')[-1].text == 'FINISHED'
		observations.append(dict(role=label, object_sha256=sha(source), application_sha256=sha(app), trace=TRACE.decode(), xml_sha256=sha(xml), invalid_access_free_and_leaks=0))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=row['mode'], baseline_sha256=sha(a.baseline), source=row['sources'], observer_sha256=sha(observer), observations=observations, limitation='A linker observer records real scalar-payload frees. It supplies no application construction, transfer, slot operation or destructor body.'), indent=2)+'\n')
	print(row['mode'], 'replacement and taken-owner retirement traces match C0; unsuppressed memory controls clean')


if __name__ == '__main__':
	main()
