#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise a real seed compiler before its long complete-source self-rebuild."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import WORK, sha
from acceleration import environment, execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('producer', 'inputs', 'build', 'runtime'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--fixture', choices=('caught-message-call', 'caught-message-scalars'), default='caught-message-call')
	p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	manifest = json.loads((a.inputs/'inputs.json').read_text())['inputs']
	fixture = ROOT/('tests/selfhost-bootstrap-27a/'+a.fixture+'.astra')
	expected_stderr = b'caught message\n' if a.fixture == 'caught-message-call' else b'copied results\n'
	inputs = {str(fixture):sha(fixture), **{p:h for p, h in manifest.items() if p.endswith(('/lib/astra/base/errors.astra', '/lib/astra/hosted/text.astra'))}}
	link = json.loads((a.inputs/'link.json').read_text())
	providers = [p for p in link['objects'] if Path(p).name not in ('llvm-capi.o', 'arguments.o')]
	env = environment(dict(LD_PRELOAD=None, VALGRIND_OPTS=None, CCACHE_DISABLE='1'))
	commands = []
	def run(name, argv, expected=0):
		argv = list(map(str, argv)); result = execute(argv, leaf/name, expected=expected, timeout=300, env=env)
		commands.append(dict(name=name, argv=argv, result=result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
		print(name, result['exit'], flush=True)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		assert all(v in (leaf/name/'stderr').read_bytes() for v in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	run('version', [a.producer, '--version']); run('help', [a.producer, '--help'])
	raw = build/'caught-message.ll'
	run('emit', [a.producer, '--emit-llvm', '-o', raw, *inputs])
	run('verify', ['opt', '-passes=verify', '-disable-output', raw])
	memory('compiler-memory', [a.producer, '--emit-llvm', '-o', raw, *inputs], 0)
	for mode in ('O0', 'O2'):
		obj = build/(mode+'.o'); exe = build/('caught-message-'+mode)
		run(mode+'-object', [a.producer, '-c', '-'+mode, '-o', obj, *inputs])
		run(mode+'-link', ['cc', '-no-pie', obj, *providers, '-o', exe])
		run(mode+'-execute', [exe], 42)
		assert (leaf/(mode+'-execute')/'stderr').read_bytes() == expected_stderr
		memory(mode+'-memory', [exe], 42)
	bad = build/'invalid.astra'; bad.write_text('int main() { bool value = 42; return 0; }\n')
	destination = build/'sentinel.ll'; marker = b'27A_PRESERVED_FAILURE_OUTPUT\n'; destination.write_bytes(marker)
	run('invalid', [a.producer, '-o', destination, bad], 1)
	assert destination.read_bytes() == marker and not list(build.glob('sentinel.ll.??????'))
	assert all(sha(p) == h for p, h in inputs.items())
	write(leaf/'result.json', dict(status='REAL_SEED_DRIVER_FOCUSED_PASS', fixture=a.fixture, producer=dict(path=str(a.producer), sha256=sha(a.producer)), inputs=inputs, raw_LLVM_sha256=sha(raw), commands_sha256=sha(leaf/'commands.json'), limitation='A genuine compiler CLI and focused native/memory proof; this is not a self-build or full behavioral qualification.'))
	print('REAL_SEED_DRIVER_FOCUSED_PASS', flush=True)


if __name__ == '__main__':
	main()
