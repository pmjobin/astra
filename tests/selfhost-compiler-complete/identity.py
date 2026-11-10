#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep literal source/IR/ELF identities, including the original caller filename."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(name) == h for group in ('sources', 'tools') for name, h in identity['identity'][group].items())
	leaf = a.runtime_root/('identity-'+a.version+'-'+a.mode)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	old_path = WORK/('runtime/effects25-r5-resume/native-frontiers-repair2-'+a.mode+'/result.json')
	new_path = a.runtime_root/('native-frontiers-'+a.version+'-'+a.mode)/'result.json'
	old = json.loads(old_path.read_text())
	new = json.loads(new_path.read_text())
	assert new['component_sha256'] == sha(a.component)
	before = {row['name']:row for row in old['programs']}
	after = {row['name']:row for row in new['programs']}
	assert set(before) == set(after) and len(before) == len(old['programs']) == len(new['programs']) == 71
	comparisons = []
	for name, row in before.items():
		current = after[name]
		for item in (row, current):
			assert all(sha(source['path']) == source['sha256'] for source in item['inputs'])
			assert item['C0']['exit'] == item['Astra']['actual_execution'] == 42
		for item, directory in ((row, WORK/('build/effects25-r5-resume/native-frontiers-repair2-'+a.mode)), (current, a.build_root/('native-frontiers-'+a.version+'-'+a.mode))):
			assert sha(directory/(name+'.ll')) == item['Astra']['raw_LLVM_sha256']
			assert sha(directory/(name+'-optimized.ll')) == item['Astra']['optimized_LLVM_sha256']
			assert all(sha(directory/(name+'-'+producer)) == item[producer]['ELF_sha256'] for producer in ('C0', 'Astra'))
		comparisons.append(dict(name=name, original_inputs=row['inputs'], current_inputs=current['inputs'], source_bytes_equal=[v['sha256'] for v in row['inputs']] == [v['sha256'] for v in current['inputs']], R5_raw_LLVM_sha256=row['Astra']['raw_LLVM_sha256'], current_raw_LLVM_sha256=current['Astra']['raw_LLVM_sha256'], raw_LLVM_equal=row['Astra']['raw_LLVM_sha256'] == current['Astra']['raw_LLVM_sha256'], R5_Astra_ELF_sha256=row['Astra']['ELF_sha256'], current_Astra_ELF_sha256=current['Astra']['ELF_sha256'], Astra_ELF_equal=row['Astra']['ELF_sha256'] == current['Astra']['ELF_sha256'], R5_C0_ELF_sha256=row['C0']['ELF_sha256'], current_C0_ELF_sha256=current['C0']['ELF_sha256'], C0_ELF_equal=row['C0']['ELF_sha256'] == current['C0']['ELF_sha256']))
	assert [row['name'] for row in comparisons if not row['source_bytes_equal']] == ['caller-all']
	# CallerFilePath is observable. Do not rewrite its literal or relocate the
	# original source and then label that new program byte-identical to R5.
	inputs = [Path(row['path']) for row in before['caller-all']['inputs']]
	assert str(inputs[0]).encode() in inputs[0].read_bytes()
	objects = [a.build_root/('native-frontiers-'+a.version+'-'+a.mode)/(name+'.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap', 'provider')]
	assert all(path.is_file() for path in objects)
	commands = []
	env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(name, None)
	def run(argv, name, expected=0):
		argv = list(map(str, argv))
		started = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(300)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				code = process.wait()
		commands.append(dict(name=name, argv=argv, exit=code, timed_out=timed_out, start=started, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		assert not timed_out and code == expected, (name, code)
		return (leaf/(name+'.stdout')).read_bytes()
	links = [word for obj in objects for word in ('--link-object', obj)]
	oracle = build/'caller-all-C0'
	run([a.compiler, '-'+a.mode, *inputs, *links, '-o', oracle], 'C0-build')
	physical = build/'caller-all.ll'
	physical.write_text('Original caller identity sentinel\n')
	run([a.component, '--native', physical, *inputs], 'Astra-emit')
	run(['opt', '-passes=verify', '-disable-output', physical], 'verify')
	optimized = build/'caller-all-optimized.ll'
	run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], 'optimize')
	run(['opt', '-passes=verify', '-disable-output', optimized], 'optimized-verify')
	obj = build/'caller-all.o'
	run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'object')
	exe = build/'caller-all-Astra'
	run(['cc', '-no-pie', obj, *objects, '-o', exe], 'link')
	for who, product in (('C0', oracle), ('Astra', exe)):
		run([product], who+'-execute', 42)
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], who+'-memory', 42)
		data = (leaf/(who+'-memory.stderr')).read_bytes()
		assert all(marker in data for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	for stream in ('stdout', 'stderr'):
		assert (leaf/('Astra-execute.'+stream)).read_bytes() == (leaf/('C0-execute.'+stream)).read_bytes()
	stages = run([a.component, '--shared-stages', *inputs], 'original-source-stages', 42)
	assert b'SHARED_SSA_VALID' in stages and b'FLOW_LEAF ' not in stages
	assert all(sha(source['path']) == source['sha256'] for source in before['caller-all']['inputs'])
	write(leaf/'result.json', dict(status='EXACT_R5_SOURCE_IDENTITIES_RETAINED', profile=a.mode, component_sha256=sha(a.component), old_receipt=dict(path=str(old_path), sha256=sha(old_path)), primary_receipt=dict(path=str(new_path), sha256=sha(new_path)), comparisons=comparisons, source_byte_identical_primary=70, original_source_identities_retained=71, exact_original_caller=dict(inputs=before['caller-all']['inputs'], actual_C0_exit=42, actual_Astra_exit=42, returning_unsuppressed_clean_memory=True, stage_exit=42, raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized), object_sha256=sha(obj), C0_ELF_sha256=sha(oracle), Astra_ELF_sha256=sha(exe), provider_objects=[dict(path=str(path), sha256=sha(path)) for path in objects]), limitation='The primary self-filename successor is kept as an additional program, not called the original source. Original R5 caller-all bytes are executed at their original physical path with the current host and independent C0. The other 70 original source identities are byte-exact primary replays. Raw LLVM and ELF differences remain literal hashes, never normalized identity. No bounded source set proves full original compiler completeness.'))
	print(a.mode, 'all 71 original R5 source identities retained; original caller path independently replayed', flush=True)


if __name__ == '__main__':
	main()
