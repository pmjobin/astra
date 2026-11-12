#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real C0/unit/cache/profile integration checks; no whole-compiler credit."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

from run import ROOT, WORK, sha, declarations
from acceleration import execute, run_jobs, write


def selected_function(path, name):
	text = path.read_text(); first = text.index('int '+name+'(')
	brace = text.index('{', first); depth = 1; at = brace+1
	while depth:
		if text[at] == '{':
			depth += 1
		elif text[at] == '}':
			depth -= 1
		at += 1
	return text[first:at]+'\n'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	args = p.parse_args(); assert args.version.isalnum()
	leaf = args.runtime_root/('acceleration-checks-'+args.version); build = args.build_root/leaf.name
	assert leaf.resolve().is_relative_to((WORK/'runtime').resolve()) and build.resolve().is_relative_to((WORK/'build').resolve())
	leaf.mkdir(); build.mkdir(); source = leaf/'sources'; source.mkdir()
	subprocess.run([sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', args.compiler, '--receipt', leaf/'toolchain.json'], check=True)
	results = []
	def run(name, argv, expected=0):
		result = execute(argv, leaf/name, expected=expected, timeout=300, env=dict(os.environ, CCACHE_DISABLE='1', LD_PRELOAD=''))
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result, (leaf/name/'stderr').read_text()[-1500:])
		results.append(dict(name=name, **result)); write(leaf/'checks.json', results)
		return result
	diagnostics = ROOT/'lib/runtime/platform/diagnostics-trap.c'
	provider = build/'diagnostics.o'
	run('provider', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', diagnostics, '-o', provider])
	growth_source = ROOT/'compiler/syntax/arena-support.astra'; capacity_source = ROOT/'compiler/semantic/recover-model.astra'
	growth = selected_function(growth_source, 'syntax_grown_capacity'); capacity = selected_function(capacity_source, 'recover_module_capacity')
	(source/'syntax.astra').write_text('namespace AccelSyntax;\n'+(ROOT/'lib/astra/base/diagnostics.astra').read_text()+growth)
	(source/'model.astra').write_text('namespace AccelModel;\nusing AccelSyntax;\n'+capacity)
	(source/'independent.astra').write_text('namespace AccelIndependent;\nint unchanged(int value) { return value; }\n')
	(source/'main.astra').write_text('using AccelModel;\nusing AccelIndependent;\nint main() {\n if (recover_module_capacity(0, 1) != 4) return 1;\n if (recover_module_capacity(1, 17) != 32) return 2;\n if (recover_module_capacity(1, 8000001) != 8000000) return 3;\n return 42 + unchanged(0);\n}\n')
	# Actual parser declaration hashes authenticate the compiler helper bodies.
	for label, original, selected in [('growth', growth_source, source/'syntax.astra'), ('capacity', capacity_source, source/'model.astra')]:
		run(label+'-original-AST', [args.compiler, '--dump-syntax', original]); run(label+'-selected-AST', [args.compiler, '--dump-syntax', selected])
		full = declarations((leaf/(label+'-original-AST')/'stdout').read_text()); subset = declarations((leaf/(label+'-selected-AST')/'stdout').read_text())
		assert sum(row in full for row in subset) >= 1
	module_path = Path(__file__).with_name('incremental-units.py')
	module_spec = importlib.util.spec_from_file_location('compiler26_incremental_units', module_path)
	module = importlib.util.module_from_spec(module_spec); module_spec.loader.exec_module(module)
	units = [
		dict(id='syntax', namespace='AccelSyntax', exports=['AccelSyntax.syntax_grown_capacity'], sources=[str(source/'syntax.astra')], mode='O2'),
		dict(id='model', namespace='AccelModel', exports=['AccelModel.recover_module_capacity'], sources=[str(source/'model.astra')], mode='O2', needs=['syntax']),
		dict(id='independent', namespace='AccelIndependent', exports=['AccelIndependent.unchanged'], sources=[str(source/'independent.astra')], mode='O2'),
		dict(id='application', sources=[str(source/'main.astra')], mode='O2', needs=['model', 'independent'], link_objects=[str(provider)]),
	]
	spec = dict(format='astra-native-units/1', units=units)
	write(leaf/'units.json', spec)
	def campaign(name):
		jobs = module.make_jobs(spec, args.compiler)
		result = run_jobs(jobs, leaf/name, build/name, leaf/'cache', jobs=2, max_jobs=4, reserve_bytes=8*1024**3, reuse=True)
		assert not result['failed_jobs'], (name, result['failed_jobs'])
		return result
	cold = campaign('cold'); assert cold['cold_execution_count'] == 4 and cold['artifact_reuse_count'] == 0
	warm = campaign('warm'); assert warm['cold_execution_count'] == 0 and warm['artifact_reuse_count'] == 4
	assert cold['execution_interval_union_seconds'] < cold['summed_process_seconds'], 'independent C0 units did not overlap'
	assert cold['jobs']['model']['monotonic_start'] >= cold['jobs']['syntax']['monotonic_end']
	assert cold['jobs']['application']['monotonic_start'] >= cold['jobs']['model']['monotonic_end']
	original = (source/'model.astra').read_bytes()
	try:
		(source/'model.astra').write_bytes(b'// Harmless incremental change; original restored below.\n'+original)
		(leaf/'changed-model.astra').write_bytes((source/'model.astra').read_bytes())
		incremental = campaign('incremental')
		assert incremental['cold_execution_count'] == 2 and incremental['artifact_reuse_count'] == 2
		assert incremental['jobs']['syntax']['status'] == incremental['jobs']['independent']['status'] == 'ARTIFACT_REUSED'
	finally:
		(source/'model.astra').write_bytes(original)
	assert (source/'model.astra').read_bytes() == original
	for label, result in [('cold', cold), ('incremental', incremental)]:
		exe = Path(result['jobs']['application']['artifacts']['application_elf']['path'])
		run(label+'-execute', [exe], 42)
		run(label+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 42)
		assert all(value in (leaf/(label+'-memory')/'stderr').read_bytes() for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	for mode in ('O0', 'O2'):
		exe = build/('monolithic-'+mode)
		run(mode+'-monolithic-build', [args.compiler, '-'+mode, *(source/name for name in ('syntax.astra', 'model.astra', 'independent.astra', 'main.astra')), '--link-object', provider, '-o', exe])
		run(mode+'-monolithic-execute', [exe], 42)
		# Preserve a deliberately damaged cache artifact and prove consumers do not
		# receive a stale success. Restore only this test-owned output afterwards.
	artifact = Path(cold['jobs']['syntax']['artifacts']['syntax_o']['path']); intact = artifact.read_bytes()
	try:
		artifact.write_bytes(b'X'+intact[1:])
		corrupt = run_jobs(module.make_jobs(spec, args.compiler), leaf/'corrupt-cache', build/'corrupt-cache', leaf/'cache', jobs=2, max_jobs=4, reserve_bytes=8*1024**3, reuse=True)
		assert corrupt['jobs']['syntax']['status'] == 'HARNESS_FAILURE'
		assert corrupt['jobs']['model']['status'] == corrupt['jobs']['application']['status'] == 'DEPENDENCY_FAILED'
	finally:
		artifact.write_bytes(intact)
	assert sha(artifact) == cold['jobs']['syntax']['artifacts']['syntax_o']['sha256']
	# The sampled child must survive perf's PATH prefix without changing the
	# build contract. Exercise the real original compiler, not a fake build.
	tiny = source/'tiny.astra'; tiny.write_text('int main() { return 42; }\n')
	env_keys = ('CC', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'PATH', 'LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'LD_LIBRARY_PATH', 'LC_ALL', 'LANG')
	identity = dict(argv=[str(args.compiler), '-O2', str(tiny), '-o', str(build/'sampled.elf')], sources={str(tiny):sha(tiny)}, tools={str(args.compiler):sha(args.compiler)}, environment={key:os.environ.get(key) for key in env_keys})
	write(leaf/'profile-input.json', identity)
	run('profile-launch', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/accelerate.py', 'profile', '--identity', leaf/'profile-input.json', '--runtime-root', args.runtime_root, '--version', args.version+'sample', '--timeout-seconds', '120'])
	run('sampled-execute', [build/'sampled.elf'], 42)
	run('C0-stages', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/native-profile.py', '--bootstrap', '--host', args.compiler, '--profile-dir', leaf/'C0-stage-profile', '--timeout-seconds', '120', '--', '-O2', tiny, '-o', build/'staged.elf'])
	stages = json.loads((leaf/'C0-stage-profile/stages.json').read_text()); assert {'semantic', 'Core', 'SSA', 'LLVM_build', 'LLVM_write'} <= {row['stage'] for row in stages}
	run('staged-execute', [build/'staged.elf'], 42)
	invalid = source/'invalid.astra'; invalid.write_text('int main() { return "wrong result type"; }\n')
	checks = [
		dict(id='refusal', argv=[str(args.compiler), '-O2', str(invalid), '-o', '{work}/destination'], inputs={str(invalid):sha(invalid)}, tools={str(args.compiler):sha(args.compiler)}, expected_exit=1, sentinels={'destination':'Unchanged refusal destination\n'}, cache='fresh'),
		dict(id='missing-witness', argv=[str(args.compiler), '--dump-semantics', str(tiny)], inputs={str(tiny):sha(tiny)}, tools={str(args.compiler):sha(args.compiler)}, expected_exit=0, required_stdout=['Astra qualification witness deliberately absent'], cache='fresh'),
		dict(id='forbidden-consumer', argv=[str(build/'staged.elf')], tools={str(build/'staged.elf'):sha(build/'staged.elf')}, needs=['missing-witness'], expected_exit=42, cache='fresh'),
	]
	controls = run_jobs(dict(format='astra-native-jobs/1', jobs=checks), leaf/'witness-controls', build/'witness-controls', leaf/'witness-cache', jobs=2, max_jobs=2, reserve_bytes=8*1024**3, reuse=False)
	assert controls['jobs']['refusal']['status'] == 'EXPECTED_OUTCOME' and controls['jobs']['refusal']['refusal_destination_preserved']
	assert controls['jobs']['missing-witness']['status'] == 'HARNESS_FAILURE'
	assert controls['jobs']['forbidden-consumer']['status'] == 'DEPENDENCY_FAILED'
	write(leaf/'result.json', dict(status='ACCELERATION_INTEGRATION_CHECKS_PASSED', source_helpers=[dict(path=str(growth_source), sha256=sha(growth_source)), dict(path=str(capacity_source), sha256=sha(capacity_source))], cold_compilations=4, warm_compilations=0, changed_unit_compilations=2, unchanged_units_reused=2, dependencies_ordered=True, independent_units_overlapped=True, corrupt_artifact_refused=True, missing_witness_refused=True, refusal_destination_preserved=True, changed_source_restored=True, original_source_bytes_unchanged=True, modular_and_monolithic_execution=42, strict_memory_streams=2, profiled_C0_launch_verified=True, C0_stage_intervals=len(stages), full_original_native_credit=0, limitation='Exact compiler scalar helper bodies in namespaced C0 native-unit test views plus an independent branch and small application. This proves incremental execution/cache/profiling mechanics, not decomposition or Astra translation of the full compiler.'))
	print('ACCELERATION_INTEGRATION_CHECKS_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
