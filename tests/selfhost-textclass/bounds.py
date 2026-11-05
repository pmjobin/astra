#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare text-owning Bag capacity/index traps with independent C0 oracles."""
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


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'frozen', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	provider = a.frozen/'bag-replace/provider.astra'; bag = ROOT/'lib/astra/collections/bag.astra'
	cases = [('append-without-capacity', 'var bag = new Bag<Note>(); var a = new Note("held"); bag.append(move a);'), ('take-outside-count', 'var bag = new Bag<Note>(); bool room = bag.reserve(1); var a = new Note("held"); bag.append(move a); var b = bag.take(1);')]
	commands, observations = [], []
	def run(argv, name, expected):
		environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=environment, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-1000:]); return r
	for name, body in cases:
		entry = a.runtime/(name+'.astra'); entry.write_text('int main() { '+body+' return 90; }\n'); sources = [bag, provider, entry]
		identities = [dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path)) for path in sources]
		oracle = a.build/(name+'-C0'); run([a.compiler, '-'+a.mode, *sources, '-o', oracle], name+'-C0-build', 0)
		expected = -signal.SIGILL; plain_C0 = run([oracle], name+'-C0-execute', expected)
		obj = a.build/(name+'.o'); run([a.component, '--classstorage-emit-obj', a.mode, obj, *sources], name+'-native-object', 0)
		app = a.build/(name+'-native'); run(['gcc', obj, '-o', app], name+'-native-link', 0); plain = run([app], name+'-native-execute', expected)
		assert plain.stdout == plain_C0.stdout == b''
		for role, product in (('C0', oracle), ('native', app)):
			xml = a.runtime/(name+'-'+role+'.xml')
			memory = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=none', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml), product], name+'-'+role+'-memory', expected)
			tree = ET.parse(xml).getroot(); kinds = [row.findtext('kind') for row in tree.findall('error')]
			assert memory.stdout == b'' and tree.find('fatal_signal') is not None and all(kind.startswith('Leak_') for kind in kinds)
			assert tree.findall('./status/state')[-1].text == 'FINISHED'
			observations.append(dict(case=name, role=role, mode=a.mode, sources=identities, application_sha256=sha(product), exit=expected, xml_sha256=sha(xml), raw_trace_sha256=sha(a.runtime/(name+'-'+role+'-memory.stderr')), valgrind_error_kinds=kinds, normal_exit_memory_clean_claim=False))
		assert all(sha(row['path']) == row['sha256'] for row in identities)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), observations=observations, limitation='Fatal capacity/index traps match C0. Raw no-unwind leaks are preserved and excluded only from fatal leak exit-code accounting; invalid memory errors remain failures. These cases do not count as normal-exit native baselines.'), indent=2)+'\n')
	print('C0/native text-owning Bag capacity and count traps agree; no normal-exit cleanup claim')


if __name__ == '__main__':
	main()
