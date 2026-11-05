#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent link observations of real text retirement and allocation edges."""
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
RETIREMENT = b'retire text old\nretire text new\n'
FIELDS = b'retire field right\nretire field left\n'
FAILURE = b'TEXTCLASS_TEST: one text byte refused\n'
RESERVE = b'TEXTCLASS_TEST: Bag reserve refused\n'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('baseline', 'compiler', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--gate', choices=('retirement', 'allocation', 'reserve'), required=True); a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	commands, observations = [], []
	def run(argv, name, expected):
		environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=environment, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest())); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-1800:]); return r
	observer = ROOT/'tests/selfhost-textclass'/dict(retirement='retirement.c', allocation='allocation-fail.c', reserve='reserve-fail.c')[a.gate]
	deps = subprocess.check_output(['gcc', '-M', observer], text=True).replace('\\\n', ' ').split(':', 1)[1].split(); inputs = {str(path):sha(path) for path in deps}
	cases = dict(retirement=['bag-replace', 'two-fields'], allocation=['empty-copy', 'one-byte'], reserve=['bag-reserve'])[a.gate]
	rows = json.loads(a.baseline.read_text())
	for name in cases:
		obj = a.build/(name+'-observer.o'); definitions = ['-DTWO_FIELDS'] if name == 'two-fields' else []
		run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *definitions, '-c', observer, '-o', obj], name+'-observer-build', 0)
		row = next(row for row in rows if row['name'] == name); assert row['baseline_complete']
		assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
		objects = {'native':Path(row['products']['object']['path']), 'C0':a.build/(name+'-C0.o')}; assert sha(objects['native']) == row['products']['object']['sha256']
		run([a.compiler, '-'+row['mode'], '--entry-object', *[source['path'] for source in row['sources']], '-o', objects['C0']], name+'-C0-entry-object', 0)
		expected = 3 if name == 'bag-replace' else 11 if name == 'two-fields' else 0 if name == 'empty-copy' else -signal.SIGILL
		trace = RETIREMENT if name == 'bag-replace' else FIELDS if name == 'two-fields' else RESERVE if name == 'bag-reserve' else b'' if name == 'empty-copy' else FAILURE
		for role, source in objects.items():
			prefix = name+'-'+role; app = a.build/prefix; wraps = ['-Wl,--wrap=calloc']
			if a.gate == 'retirement': wraps.append('-Wl,--wrap=free')
			run(['gcc', source, obj, *wraps, '-o', app], prefix+'-link', 0)
			plain = run([app], prefix+'-execute', expected); assert plain.stdout == b'' and plain.stderr == trace
			xml = a.runtime/(prefix+'.xml'); options = ['--command-line-only=yes', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml)]
			if expected >= 0: options.append('--errors-for-leak-kinds=all')
			else: options.append('--errors-for-leak-kinds=none')
			memory = run(['valgrind', *options, app], prefix+'-memory', expected); assert memory.stdout == b''
			markers = b''.join(line+b'\n' for line in memory.stderr.splitlines() if line.startswith((b'retire text ', b'retire field ', b'TEXTCLASS_TEST:'))); assert markers == trace
			tree = ET.parse(xml).getroot(); kinds = [error.findtext('kind') for error in tree.findall('error')]; assert tree.findall('./status/state')[-1].text == 'FINISHED'
			if expected < 0: assert tree.find('fatal_signal') is not None and all(kind.startswith('Leak_') for kind in kinds)
			else: assert kinds == [] and tree.find('fatal_signal') is None
			observations.append(dict(case=name, role=role, mode=row['mode'], exit=expected, application_sha256=sha(app), source=row['sources'], trace=trace.decode(), xml_sha256=sha(xml), raw_malloc_trace_sha256=sha(a.runtime/(prefix+'-memory.stderr')), valgrind_error_kinds=kinds, normal_exit_memory_clean=expected >= 0, fatal_leaks='Retained raw; fatal traps do not unwind owners.' if expected < 0 else None))
	assert all(sha(path) == value for path, value in inputs.items())
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, baseline_sha256=sha(a.baseline), recipe_sha256=sha(__file__), observer_inputs=inputs, observations=observations, limitation='Test-only libc observers supply no Astra construction, transfer, collection or retirement algorithm. Default text-copy and owner-slot allocation exhaustion are fatal/no-unwind in C0. Negative reserve extents returning false and fatal allocation failure are distinct. Fatal-path raw leaks are distinct from normal-exit memory checks.'), indent=2)+'\n')
	print(a.gate, 'native/C0 observations match; normal and fatal memory results kept separate')


if __name__ == '__main__':
	main()
