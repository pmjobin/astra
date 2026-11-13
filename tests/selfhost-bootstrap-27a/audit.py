#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently bind the bounded bootstrap gates to delivered native evidence.

This is a prepublication engineering audit. G7 necessarily remains pending.
Run in the exact existing LLVM capsule, with explicit task work roots.
"""
import argparse
import ast
import datetime
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import C0_SHA256, WORK, git, sha
from acceleration import environment, execute, output_path, write
import audit as historical


def load(path):
	return json.loads(path.read_text())


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('inputs', 'stage1', 'rebuild', 'qualification', 'smoke', 'call-controls', 'borrow-controls', 'runtime', 'build'):
		p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	assert not git('diff', '--name-only').strip() and not git('diff', '--cached', '--name-only').strip()
	head = git('rev-parse', 'HEAD').decode().strip(); tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', '26542cf0760b788fcf56e46a375408540cf37f31', head]).returncode == 0
	frozen = load(a.inputs/'snapshot.json'); manifest = load(a.inputs/'inputs.json')
	# Reconstruct the full source population from Git, not the claimed product.
	compiler = {n for n in git('ls-tree', '-r', '--name-only', frozen['revision'], 'compiler').decode().splitlines() if n.endswith('.astra')}
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	libraries = next(ast.literal_eval(n.value) for n in model.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'LIBRARIES' for t in n.targets))
	expected = compiler | {'lib/astra/'+n+'.astra' for n in libraries}
	assert len(compiler) == 196 and len(libraries) == 10 and 'compiler/driver/main.astra' in compiler
	rows = {str(Path(v['original_path']).relative_to(ROOT)):v for v in frozen['sources']}
	assert {n for n in rows if rows[n]['input_path'] in manifest['inputs']} == expected
	assert len(manifest['inputs']) == len(expected)
	for name, row in rows.items():
		path = Path(row['input_path']); raw = git('show', frozen['revision']+':'+name)
		assert path.read_bytes() == raw == (ROOT/name).read_bytes() == git('show', head+':'+name)
		assert sha(path) == row['sha256'] and not path.stat().st_mode & 0o222
		if name in expected: assert manifest['inputs'][str(path)] == row['sha256']
	plan = load(a.inputs/'ownflow-O2-input-identity.json'); identity = load(a.stage1.with_suffix('.identity.json'))
	assert sha(plan['argv'][0]) == C0_SHA256 and Path(plan['argv'][-1]) == a.stage1
	assert identity['sha256'] == sha(a.stage1)
	assert {p for p in plan['argv'] if p.endswith('.astra')} == set(manifest['inputs'])
	assert all(sha(p) == h for p, h in plan['sources'].items())
	assert all(sha(p) == h for p, h in plan['tools'].items())
	expected_identity = {**plan, 'sources':{**plan['sources'], str(ROOT/'tests/selfhost-compiler-complete/compile-plan.py'):sha(ROOT/'tests/selfhost-compiler-complete/compile-plan.py')}}
	assert identity['identity'] == expected_identity
	seed_execution = load(a.inputs/('accelerated-build-'+a.inputs.name)/'execution/result.json')
	assert seed_execution['status'] == 'EXPECTED_OUTCOME' and seed_execution['exit'] == 0
	stage1_hash = sha(a.stage1)
	for path, status in [(a.smoke, 'REAL_SEED_DRIVER_FOCUSED_PASS'), (a.call_controls, 'INDEPENDENT_RECOVERED_CALL_CONTROLS_PASS'), (a.borrow_controls, 'INDEPENDENT_CAUGHT_MESSAGE_BORROW_CONTROLS_PASS')]:
		result = load(path/'result.json'); assert result['status'] == status
		assert result['producer']['sha256'] == stage1_hash and Path(result['producer']['path']) == a.stage1
	second = load(a.rebuild/'result.json'); commands = load(a.rebuild/'commands.json')
	assert second['status'] == 'NATIVE_COMPILER_REBUILT_REQUIRES_BEHAVIORAL_QUALIFICATION'
	assert second['producer_sha256'] == stage1_hash and Path(second['producer']) == a.stage1
	assert second['source_revision'] == manifest['revision'] and second['frozen_manifest_sha256'] == sha(a.inputs/'inputs.json')
	translation = next(v for v in commands if v['name'] == 'source-to-LLVM')
	assert Path(translation['argv'][0]) == a.stage1
	assert translation['argv'][1:3] == ['--emit-llvm', '-o']
	assert translation['argv'][4:] == list(manifest['inputs'])
	assert translation['input_hashes'] == {str(a.stage1):stage1_hash, **manifest['inputs']}
	for row in commands:
		assert row['result']['status'] == 'EXPECTED_OUTCOME' and row['result']['exit'] == 0
		assert all(sha(p) == h for p, h in row['input_hashes'].items())
	products = {}
	for mode in ('O0', 'O2'):
		items = second['products'][mode]
		for path, record in items.items(): assert sha(path) == record['sha256'] and Path(path).stat().st_size == record['bytes']
		products[mode] = next(Path(n) for n in items if Path(n).name == 'astrac-stage2-'+mode)
	qualified = load(a.qualification/'result.json')
	assert qualified['status'] == 'STAGE1_AND_STAGE2_BEHAVIOR_ABI_MEMORY_VERIFIED'
	assert qualified['stages']['stage1'] == dict(path=str(a.stage1), sha256=stage1_hash)
	assert qualified['stages']['stage2'] == dict(path=str(products['O2']), sha256=sha(products['O2']))
	assert len(qualified['programs']) == 13 and len(qualified['independent_negative_controls']) == 7
	for row in qualified['programs']:
		assert row['native_exit'] == 42 and row['strict_returning_memory']
		assert row['raw_LLVM']['stage1'] == row['raw_LLVM']['stage2']
		assert all(sha(p) == h for p, h in row['sources'].items())
		for group in row['products'].values(): assert all(sha(p) == h for p, h in group.items())
	assert all(sha(p) == h for p, h in qualified['provider_objects'].items())
	env = environment(dict(LD_PRELOAD=None, VALGRIND_OPTS=None, CCACHE_DISABLE='1'))
	def run(name, argv, expected=0):
		result = execute(argv, leaf/name, expected=expected, timeout=300, env=env)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
		return result
	for name, exe in [('stage1', a.stage1), *products.items()]:
		assert exe.read_bytes()[:4] == b'\x7fELF'
		for suffix, argv in [('ELF', ['readelf', '-h', exe]), ('symbols', ['nm', '-an', exe]), ('machine-code', ['objdump', '-d', exe])]: run(name+'-'+suffix, argv)
		# O0 is also an actual compiler host, in addition to its native link proof.
	source = build/'independent42.astra'; source.write_text('int main() { return 6 * 7; }\n')
	ir = build/'O0-host.ll'; obj = build/'O0-host.o'; exe = build/'O0-host-program'
	run('O0-host-emit', [products['O0'], '--emit-llvm', '-o', ir, source])
	run('O0-host-verify', ['opt', '-passes=verify', '-disable-output', ir])
	run('O0-host-object', ['llc', '-filetype=obj', '-O2', ir, '-o', obj])
	run('O0-host-link', ['cc', '-no-pie', obj, '-o', exe]); run('O0-host-native', [exe], 42)
	run('O0-host-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', products['O0'], '--emit-llvm', '-o', ir, source])
	log = (leaf/'O0-host-memory/stderr').read_bytes()
	assert all(x in log for x in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	protection = historical.preservation(); write(leaf/'preservation.json', protection)
	assert protection['paths'] == 451 and protection['donor_files'] == 6622 and protection['historical_proof_hashes'] == 1044
	assert sha(a.runtime/'G0/predecessor-delivered-report.zip') == 'a33409156483fdb2ba70572997ac221e68454f6c5bc332ea3537327605beac00'
	assert load(a.runtime/'G0/verdict.json')['status'] == 'PASS'
	failures = []
	for path in sorted(a.runtime.rglob('result.json')):
		row = load(path)
		if row.get('status') == 'UNEXPECTED_OUTCOME': failures.append(dict(path=str(path), sha256=sha(path), exit=row.get('exit'), timed_out=row.get('timed_out'), seconds=row.get('seconds')))
	for path in sorted(a.runtime.glob('capsule-run-*.json')):
		row = load(path)
		if row['exit'] != 0: failures.append(dict(path=str(path), sha256=sha(path), exit=row['exit'], classification='Outer task command failed or a test harness stopped; inner execution receipts remain separately preserved.'))
	write(leaf/'preserved-unexpected-executions.json', failures)
	assert sha(a.stage1) == stage1_hash and not git('diff', '--name-only').strip()
	write(leaf/'result.json', dict(status='BOUNDED_27A_ENGINEERING_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), HEAD=head, tree=tree, frozen_revision=manifest['revision'], frozen_source_manifest_sha256=sha(a.inputs/'inputs.json'), compiler_sources=len(compiler), library_sources=len(libraries), stages=dict(stage1=dict(path=str(a.stage1), sha256=stage1_hash), stage2={mode:dict(path=str(exe), sha256=sha(exe)) for mode, exe in products.items()}), gates={**{'G'+str(i):dict(status='PASS') for i in range(6)}, 'G6':dict(status='ENGINEERING_PASS_PUBLICATION_PENDING'), 'G7':dict(status='PENDING', reason='Requires separate verification after installed publication.')}, full_milestone27_credit=False, release_credit=False, first_identical_source_self_build=True, preserved_unexpected_execution_count=len(failures), receipts={str(path/'result.json'):sha(path/'result.json') for path in (a.smoke, a.call_controls, a.borrow_controls, a.rebuild, a.qualification)}, limitation='Initial fixed-source self-build only. No Stage3/final 27-D convergence or 27-B/C migration. Flow/SSA diagnostics identify the rejecting phase without source spans; Typecore byte positions are independently checked. G7 cannot be credited before delivery.'))
	print('BOUNDED_27A_ENGINEERING_PASS_G7_PENDING', flush=True)


if __name__ == '__main__':
	main()
