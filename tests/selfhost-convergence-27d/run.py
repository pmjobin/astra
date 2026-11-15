#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound 27-D generation receipts over the existing production driver."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
RUNTIME = WORK/'runtime/selfhost27d'
BUILD = WORK/'build/selfhost27d'
BASE = '0060fa319f0e72ea402ab64af87e3b3d2cab62b9'
TREE = '8569db6bf75f673fbea70a8c8fc45a1626ae3ace'
SEED = WORK/'build/selfhost27c/dev21/astrac-O2'
SEED_SHA = 'b35a9ca0f7bcc54fbb4dc632a7004fa0f5f14bb5797c75f5e9468d3eda1ce857'
PRIOR = WORK/'runtime/selfhost27c-dev21'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, sha, tool_identity, write
from audit import preservation


def git(*args):
	return subprocess.check_output(['git', '-C', ROOT, *args])


def load(path):
	return json.loads(Path(path).read_text())


def environment():
	env = dict(os.environ)
	env.update({k:v for k, v in load(PRIOR/'build-identity.json')['environment'].items() if v is not None})
	env.update(CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	return env


def authenticate():
	assert sha(SEED) == SEED_SHA
	prior = load(PRIOR/'build-identity.json')
	for group in ('sources', 'objects', 'tools'):
		assert all(sha(path) == digest for path, digest in prior[group].items()), group
	for row in load(PRIOR/'snapshot.json')['sources']:
		assert sha(row['input_path']) == row['sha256'] == sha(row['original_path'])
	for obj in prior['objects']:
		cached = load(Path(obj).with_suffix('.identity.json'))
		assert sha(obj) == cached['sha256']
		for group in ('dependencies', 'tools'):
			assert all(sha(path) == digest for path, digest in cached['identity'][group].items())
	assert subprocess.check_output(['llvm-config', '--version'], env=environment()).strip() == b'23.1.4'
	assert git('rev-parse', BASE+'^{tree}').decode().strip() == TREE
	compiler = [n for n in git('ls-tree', '-r', '--name-only', BASE, 'compiler').decode().splitlines() if n.endswith('.astra')]
	libraries = [str(Path(n).relative_to(PRIOR/'source-inputs')) for n in prior['sources'] if '/lib/astra/' in n]
	assert len(compiler) == 220 and len(libraries) == 10
	assert not git('diff', 'fbfd9828fc679f0408a1acd15d096ee3b2597371', BASE, '--', 'compiler', 'lib').strip()
	rows = []
	for name in [*compiler, *libraries]:
		path = ROOT/name
		data = git('show', BASE+':'+name)
		assert path.read_bytes() == data
		rows.append(dict(path=name, input_path=str(path), bytes=len(data), sha256=sha(path), git_blob=git('rev-parse', BASE+':'+name).decode().strip(), language_mode='astra27c-modern'))
	return rows, prior


def intake():
	assert git('rev-parse', 'HEAD').decode().strip() == BASE
	rows, prior = authenticate()
	packet = WORK/'runtime/native-current/input'
	archive = ROOT.parent/'codex/submissions/ASTRA-SELFHOST-27D-FINAL-SELFHOST-CONVERGENCE-SUBMISSION.zip'
	assert sha(archive) == 'b64f6fd11cf44c48b95d81a07d7c32eeeb79babb3249320074430ff3461081d0'
	check = execute([sys.executable, '-B', packet/'VERIFY-OFFLINE.py', archive], RUNTIME/('offline-'+str(time.time_ns())), env=environment())
	assert check['status'] == 'EXPECTED_OUTCOME'
	witnesses = []
	for path in sorted((packet/'reference/report27c/source').rglob('*')):
		if not path.is_file(): continue
		name = str(path.relative_to(packet/'reference/report27c/source'))
		assert path.read_bytes() == git('show', BASE+':'+name)
		# scope contains only this task's new recipe registration after the initial
		# interactive check authenticated all 156 live witnesses before any edit.
		if name != 'format/scope.json': assert path.read_bytes() == (ROOT/name).read_bytes()
		witnesses.append(name)
	assert len(witnesses) == 156
	protected = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	write(RUNTIME/'preservation-initial.json', protected)
	fixed = dict(format='astra27d-fixed-source/1', revision=BASE, tree=TREE, compiler_sources=220, libraries=10, source_rows=rows, sources={row['input_path']:row['sha256'] for row in rows}, providers=prior['objects'], toolchain=prior['tools'], seed=dict(path=str(SEED), sha256=SEED_SHA, source_revision=load(PRIOR/'result.json')['revision'], actual_producer=load(PRIOR/'result.json')['producer']), optimization_profiles=['O0', 'O2'], next_generation_producer_profile='O2', source_selection='LIVE_COMMITTED_SOURCE; every generation reauthenticates all bytes before and after execution')
	write(RUNTIME/'fixed-source.json', fixed)
	write(RUNTIME/'intake.json', dict(status='LIVE_27D_INTAKE_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), HEAD=BASE, tree=TREE, git_common=str((ROOT/git('rev-parse', '--git-common-dir').decode().strip()).resolve()), worktree_status=git('status', '--porcelain=v1', '--untracked-files=all').decode(), witnesses=witnesses, token=next(row for row in rows if row['path'] == 'compiler/syntax/token.astra'), offline=check, preservation=protected, fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), G8='PENDING_AFTER_PUBLICATION'))
	print('LIVE_27D_INTAKE_PASS', sha(RUNTIME/'fixed-source.json'), flush=True)


def generate(stage):
	rows, prior = authenticate()
	fixed = load(RUNTIME/'fixed-source.json')
	assert rows == fixed['source_rows']
	producer = SEED if stage == 1 else BUILD/('stage'+str(stage-1))/'astrac-O2'
	producer_sha = SEED_SHA if stage == 1 else load(RUNTIME/('stage'+str(stage-1))/'result.json')['products']['O2']['sha256']
	assert sha(producer) == producer_sha
	runtime = RUNTIME/('stage'+str(stage)); build = BUILD/('stage'+str(stage))
	runtime.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	tools = tool_identity([producer, sys.executable, '/usr/bin/time', '/usr/bin/cc', '/usr/bin/readelf'])
	write(runtime/'identity.json', dict(producer=dict(path=str(producer), sha256=producer_sha), fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), sources=fixed['sources'], provider_objects=prior['objects'], tools=tools, recipe_sha256=sha(__file__), environment={k:environment().get(k) for k in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'CCACHE_DISABLE', 'LD_PRELOAD', 'VALGRIND_OPTS')}))
	def profile(mode):
		leaf = runtime/mode; leaf.mkdir()
		obj = build/('astrac-'+mode+'.o'); exe = build/('astrac-'+mode)
		assert not obj.exists() and not exe.exists()
		argv = list(map(str, [producer, '-c', '-'+mode, '-o', obj, *fixed['sources']]))
		write(leaf/'plan.json', dict(argv=argv, producer_sha256=producer_sha, fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), output_preexisting=False, monotonic_start=time.monotonic()))
		# The maintained primitive retains stdout, stderr, exact exit and CPU/wall/RSS.
		outcome = execute(argv, leaf/'compile', timeout=14400, env=environment())
		write(leaf/'compile-receipt.json', dict(argv=argv, result=outcome))
		assert outcome['status'] == 'EXPECTED_OUTCOME', (stage, mode, outcome)
		link = list(map(str, ['cc', '-no-pie', obj, *prior['objects'], prior['library'], '-o', exe]))
		linked = execute(link, leaf/'link', env=environment())
		assert linked['status'] == 'EXPECTED_OUTCOME'
		elf = execute(['readelf', '-h', '-S', '-d', '-s', exe], leaf/'ELF', env=environment())
		assert elf['status'] == 'EXPECTED_OUTCOME'
		help_result = execute([exe, '--help'], leaf/'help', env=environment())
		assert help_result['status'] == 'EXPECTED_OUTCOME'
		assert b'Explicit sources form one program' in (leaf/'help/stdout').read_bytes()
		product = dict(path=str(exe), sha256=sha(exe), object=str(obj), object_sha256=sha(obj), compile=outcome, link_argv=link, link=linked, ELF=elf, actual_execution=help_result)
		write(leaf/'result.json', product)
		print('STAGE', stage, mode, 'GENERATED_NOT_QUALIFIED', product['sha256'], flush=True)
		return mode, product
		# Two isolated compiler profiles, under 8 GiB combined expected RSS; no duplicate job.
	with ThreadPoolExecutor(max_workers=2) as pool:
		products = dict(pool.map(profile, ('O0', 'O2')))
	assert authenticate()[0] == rows and sha(producer) == producer_sha
	assert all(sha(path) == digest for path, digest in tools.items())
	write(runtime/'result.json', dict(status='FRESH_FIXED_SOURCE_PRODUCTION_GENERATION_NOT_QUALIFIED', stage=stage, producer=dict(path=str(producer), sha256=producer_sha), fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), source_revision=BASE, products=products, provider_cache='Seven authenticated C provider objects from byte-identical F, with retained dependency and tool receipts; no cached Astra compiler object or ELF', identity_sha256=sha(runtime/'identity.json')))


def observe(stage):
	runtime = RUNTIME/('stage'+str(stage)); fixed = load(RUNTIME/'fixed-source.json')
	rows = []
	for process in Path('/proc').iterdir():
		if not process.name.isdigit(): continue
		try:
			argv = [part.decode() for part in (process/'cmdline').read_bytes().split(b'\0') if part]
			if len(argv) < 6 or argv[1] != '-c' or str(BUILD/('stage'+str(stage)))+'/' not in argv[4]: continue
			mode = argv[2][1:]; plan = load(runtime/mode/'plan.json')
			assert argv == plan['argv'] and argv[5:] == list(fixed['sources'])
			assert sha(process/'exe') == plan['producer_sha256']
			env = dict(entry.split(b'=', 1) for entry in (process/'environ').read_bytes().split(b'\0') if b'=' in entry)
			assert env.get(b'CCACHE_DISABLE') == b'1' and not env.get(b'LD_PRELOAD') and not env.get(b'VALGRIND_OPTS')
			maps = (process/'maps').read_text()
			libraries = {line.split()[-1] for line in maps.splitlines() if len(line.split()) >= 6 and line.split()[-1].startswith('/')}
			llvm = {name:sha(name) for name in libraries if 'libLLVM' in name}
			assert set(llvm.values()) == {'3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d'}
			rows.append(dict(pid=int(process.name), mode=mode, UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), argv=argv, executable_sha256=sha(process/'exe'), LLVM=llvm, status=(process/'status').read_text(), process_maps=maps, proc_stat=(process/'stat').read_text()))
		except (FileNotFoundError, PermissionError, ProcessLookupError): pass
	assert rows, 'No matching live producer; no fabricated process observation'
	write(runtime/('process-observation-'+str(time.time_ns())+'.json'), rows)
	print([{key:row[key] for key in ('pid', 'mode', 'UTC', 'executable_sha256')} for row in rows], flush=True)


def regress(stage, mode):
	rows, prior = authenticate()
	product = load(RUNTIME/('stage'+str(stage))/'result.json')['products'][mode]
	compiler = Path(product['path']); assert sha(compiler) == product['sha256']
	label = 'stage'+str(stage)+'-'+mode
	runtime = RUNTIME/(label+'-regression'); build = BUILD/(label+'-regression')
	runtime.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	identity = ['--compiler', str(compiler), '--compiler-sha256', product['sha256']]
	c0 = WORK/'build/selfhost27b/c0-recovery-safealloc2/astrac'
	linked = [*identity, '--c0', str(c0), '--c0-sha256', sha(c0), '--link', str(PRIOR/'link.json')]
	oracle = ['--oracle-library-inputs', str(WORK/'runtime/selfhost27c-dev20/inputs.json')]
	old = ROOT/'tests/selfhost-ownership-syntax-27b'; modern = ROOT/'tests/selfhost-expressive-language-27c'
	plans = [(feature, modern/'named.py', [*linked, *oracle, '--feature', feature]) for feature in ('named', 'match', 'range', 'format', 'collection')]
	plans.append(('freestanding', modern/'named.py', [*linked, *oracle, '--feature', 'range', '--freestanding-only']))
	plans.append(('old-native', old/'native.py', [*linked, *oracle, *[part for feature in ('initial', 'records', 'conditional', 'compound', 'weak', 'borrowed', 'workload', 'errors') for part in ('--feature', feature)]]))
	plans.append(('intrinsic', old/'intrinsic.py', linked))
	historical = WORK/'runtime/selfhost27a/qualification1/programs.json'
	assert sha(historical) == '025b36707a9a80059d4a4473888588d0c7f7e9e24128af66b52ca9038bd4ea28'
	plans.append(('legacy', old/'legacy.py', [*linked, '--historical', str(historical), '--historical-sha256', sha(historical)]))
	plans.append(('C-client', Path(__file__).with_name('c-client.py'), [*identity, '--link', str(PRIOR/'link.json')]))
	plans.append(('workloads', Path(__file__).with_name('workloads.py'), identity))
	plans.append(('physical-old', old/'physical.py', identity))
	plans.extend(('physical-'+feature, modern/'physical.py', [*identity, '--feature', feature]) for feature in ('existing', 'range', 'format', 'lazy', 'collection', 'enum'))
	write(runtime/'plans.json', [dict(name=name, recipe=str(recipe), recipe_sha256=sha(recipe), options=options) for name, recipe, options in plans])
	# Resolve the maintained runner's three context imports (ROOT/WORK/sha)
	# through this tracked recipe. Never import the protected untracked run.py.
	assert Path(importlib.util.find_spec('run').origin).resolve() == Path(__file__).resolve()
	path = ROOT/'tests/selfhost-compiler-complete/acceleration.py'
	spec = importlib.util.spec_from_file_location('astra27d_acceleration', path)
	runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
	env = {k:environment().get(k) for k in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'CCACHE_DISABLE', 'PYTHONDONTWRITEBYTECODE', 'LD_PRELOAD', 'VALGRIND_OPTS', 'LC_ALL', 'LANG')}
	tools = tool_identity([compiler, sys.executable])
	items = []
	for name, recipe, options in plans:
		argv = [sys.executable, '-B', str(recipe), *options, '--build', str(build/name), '--runtime', str(runtime/name)]
		items.append(dict(id=name, argv=argv, inputs={str(recipe):sha(recipe), str(path):sha(path)}, tools=tools, environment=env, cache='fresh', expected_exit=0, timeout_seconds=14400, estimated_RSS_bytes=2*1024**3))
	batch = runner.run_jobs(dict(format='astra-native-jobs/1', jobs=items), runtime/'jobs', build/'jobs', RUNTIME/'artifact-cache', jobs=4, max_jobs=4, reuse=False)
	results = []
	for name, recipe, options in plans:
		result = batch['jobs'][name]
		row = dict(name=name, result=result, receipt_sha256=sha(runtime/name/'result.json') if (runtime/name/'result.json').exists() else None)
		results.append(row)
		print(label, name, result['status'], flush=True)
	assert authenticate()[0] == rows and sha(compiler) == product['sha256']
	write(runtime/'result.json', dict(status='ALL_RETAINED_CURRENT_SUITES_PASS' if all(row['result']['status'] == 'EXPECTED_OUTCOME' for row in results) else 'RETAINED_CURRENT_SUITE_FAILURE', compiler=product, stage=stage, host_mode=mode, suites=results, historical_411='Retained historical qualification only; seven surviving byte-exact native groups freshly replayed. No reconstruction of absent 1044 proof files.'))
	assert all(row['result']['status'] == 'EXPECTED_OUTCOME' for row in results)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('command', choices=('intake', 'generate', 'observe', 'regress'))
	p.add_argument('--stage', type=int, choices=(1, 2, 3))
	p.add_argument('--mode', choices=('O0', 'O2'), default='O2')
	a = p.parse_args()
	if a.command == 'intake': intake()
	else:
		assert a.stage
		if a.command == 'generate': generate(a.stage)
		elif a.command == 'observe': observe(a.stage)
		else: regress(a.stage, a.mode)


if __name__ == '__main__':
	main()
