#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 oracle and Source/Flow controls for module-wide lexical storage."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write


def source():
	parameters = ', '.join(f'int p{i}' for i in range(16))
	expression = ' + '.join(f'p{i}' for i in range(16))
	lines = [f'int storage_function_{i}({parameters}) {{ return {expression}; }}' for i in range(600)]
	arguments = ', '.join(['27', *['1']*15])
	lines += ['int main() {', f'\tif (storage_function_0({arguments}) != 42 || storage_function_599({arguments}) != 42) return 1;', '\treturn 42;', '}']
	return '\n'.join(lines)+'\n'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--phase', choices=('prepare', 'observe'), required=True)
	p.add_argument('--component', type=Path)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('storage-module-'+a.version)
	build = a.build_root/leaf.name
	if a.phase == 'prepare':
		leaf.mkdir()
		build.mkdir()
	else:
		assert a.component and leaf.is_dir() and build.is_dir()
	commands = []
	def run(argv, name, expected):
		argv = list(map(str, argv))
		start = time.monotonic()
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
		try:
			out, err = process.communicate(timeout=300)
		except subprocess.TimeoutExpired:
			os.killpg(process.pid, signal.SIGKILL)
			out, err = process.communicate()
			(leaf/(name+'.stdout')).write_bytes(out)
			(leaf/(name+'.stderr')).write_bytes(err)
			raise
		(leaf/(name+'.stdout')).write_bytes(out)
		(leaf/(name+'.stderr')).write_bytes(err)
		commands.append(dict(name=name, argv=argv, exit=process.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/(a.phase+'-commands.json'), commands)
		assert process.returncode == expected, (name, process.returncode, out[-1500:], err[-3000:])
		return out, err
	program = leaf/'main.astra'
	if a.phase == 'prepare':
		program.write_text(source())
		program.chmod(0o444)
		rows = []
		for mode in ('O0', 'O2'):
			target = build/('C0-'+mode)
			run([a.compiler, '-'+mode, program, '-o', target], mode+'-build', 0)
			run([target], mode+'-execute', 42)
			_, memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], mode+'-memory', 42)
			assert all(marker in memory for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			rows.append(dict(profile=mode, ELF_sha256=sha(target), execution=42, unsuppressed_memory=True))
		write(leaf/'oracles.json', dict(status='C0_MODULE_STORAGE_ORACLES', inputs={str(program): sha(program)}, functions=601, required_slots=9600, slots_per_function=16, profiles=rows, C0_sha256=sha(a.compiler), Astra_native_credit=0))
		return
	oracle = json.loads((leaf/'oracles.json').read_text())
	assert sha(program) == oracle['inputs'][str(program)]
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	for group in ('sources', 'tools'):
		assert all(sha(path) == expected for path, expected in identity['identity'][group].items())
	for mode, marker in (('flow', b'FLOW 0 '), ('storage-controls', b'STORAGE_CONTROLS correspondence=5 per_function=1 restored=1')):
		out, _ = run([a.component, '--'+mode, program], mode, 42)
		assert marker in out
	write(leaf/'result.json', dict(status='MODULE_STORAGE_SOURCE_CONTROLS_PASS', component_sha256=sha(a.component), oracle_sha256=sha(leaf/'oracles.json'), inputs=oracle['inputs'], functions=601, required_slots=9600, source_mutations=6, Astra_native_credit=0, limitation='Focused Source/Flow module-storage evidence. Full original source and native backend qualification remain pending.'))


if __name__ == '__main__':
	main()
