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
import re
import shutil
import subprocess
import sys
import time
import tarfile
import zipfile

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


def language_modes():
	fixed = load(RUNTIME/'fixed-source.json'); rows = []
	for source in fixed['source_rows']:
		path = ROOT/source['path']; assert sha(path) == source['sha256']
		text = path.read_text()
		while True:
			before = text
			text = re.sub(r'^\s*(?://[^\n]*(?:\n|$)|/\*.*?\*/)', '', text, count=1, flags=re.S)
			if before == text: break
		match = re.match(r'\s*language\s+(astra27b|legacy27a)\s*;', text)
		directive = match[1] if match else None
		rows.append(dict(path=source['path'], sha256=source['sha256'], git_blob=source['git_blob'], explicit_directive=directive, effective_profile=1 if directive == 'astra27b' else 0, effective_mode='astra27b' if directive == 'astra27b' else 'legacy27a'))
	write(RUNTIME/'language-modes.json', dict(format='astra27d-exact-language-modes/1', fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), source_revision=BASE, source_rows=rows, interpretation='Authoritative per-file parser profiles, derived from authenticated source bytes. The initial fixed-source row label astra27c-modern describes the source population, not a parser language directive; that imprecise metadata label is retained unchanged. Source bytes, command inputs, source revision and the original manifest hash are unchanged. No source candidate restart or repin.'))
	print('EXACT_LANGUAGE_MODES', {mode:sum(row['effective_mode'] == mode for row in rows) for mode in ('astra27b', 'legacy27a')}, flush=True)


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
			imports = subprocess.check_output(['nm', '-D', '--undefined-only', argv[0]], text=True)
			for line in imports.splitlines():
				name = line.split()[-1].split('@', 1)[0]
				assert name not in ('system', 'popen', 'fork', 'vfork', 'execve', 'execvp', 'posix_spawn', 'posix_spawnp')
			rows.append(dict(pid=int(process.name), mode=mode, UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), argv=argv, executable_sha256=sha(process/'exe'), LLVM=llvm, status=(process/'status').read_text(), process_maps=maps, proc_stat=(process/'stat').read_text(), dynamic_imports=imports, process_launch_imports=[]))
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
	if stage == 3 and mode == 'O2':
		plans.append(('source-owner-consumers', modern/'component.py', [*linked, '--producer-kind', 'astra', '--layer', 'semantic', '--mode', 'O0', '--mode', 'O2', '--semantic-oracle-inputs', str(WORK/'runtime/selfhost27c-dev20/inputs.json')]))
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


def fixed_corpus():
	"""Replay Stage3 on the exact absolute inputs already compiled by Stage2."""
	assert authenticate()[0] == load(RUNTIME/'fixed-source.json')['source_rows']
	runtime = RUNTIME/'fixed-path-corpus'; build = BUILD/'fixed-path-corpus'
	resuming = runtime.exists()
	if resuming:
		assert (runtime/'comparisons.json').is_file() and (runtime/'execution-recipe-identity.json').is_file()
		check_streams(runtime)
	else:
		runtime.mkdir(); build.mkdir()
	commands = load(runtime/'commands.json') if resuming else []
	comparisons = load(runtime/'comparisons.json') if resuming else []
	completed = {}; raw_inputs = {}
	for row in comparisons:
		assert all(sha(path) == digest for path, digest in {**row['sources'], **row['cached_C_support_objects']}.items())
		assert sha(row['Stage3_object']) == sha(row['Stage2_object']) == row['object_sha256']
		assert sha(row['Stage3_ELF']) == sha(row['Stage2_ELF']) == row['ELF_sha256']
		assert sha(row['raw_LLVM']['path']) == sha(row['raw_LLVM']['Stage2_path']) == row['raw_LLVM']['sha256']
		completed[(row['host_profile'], row['suite'], row['case'])] = row
		raw_inputs[(row['host_profile'], row['suite'], tuple(row['sources']))] = row['raw_LLVM']
	stamp = 'resume-'+str(time.time_ns()) if resuming else 'executed-recipe'
	(runtime/(stamp+'.py.txt')).write_bytes(Path(__file__).read_bytes())
	write(runtime/(stamp+'-identity.json'), dict(recipe_sha256=sha(__file__), fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), reauthenticated_completed_program_profiles=len(completed), reused_generation_products=False))
	def run(name, argv, expected=0, overrides=None, memory=False):
		argv = list(map(str, argv))
		outcome = execute(argv, runtime/name, expected=expected, timeout=900, env=dict(environment(), **(overrides or {})))
		commands.append(dict(name=name, argv=argv, result=outcome, environment_overrides=overrides or {}))
		write(runtime/'commands.json', commands)
		assert outcome['status'] == 'EXPECTED_OUTCOME', (name, outcome)
		stdout = (runtime/name/'stdout').read_bytes(); stderr = (runtime/name/'stderr').read_bytes()
		if memory:
			assert all(marker in stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			stderr = re.sub(rb'^==\d+==[^\n]*\n', b'', stderr, flags=re.M)
		return stdout, stderr
	for host in ('O0', 'O2'):
		left = load(RUNTIME/'stage2/result.json')['products'][host]
		right = load(RUNTIME/'stage3/result.json')['products'][host]
		assert sha(left['path']) == left['sha256'] and sha(right['path']) == right['sha256']
		for suite in ('named', 'match', 'range', 'format', 'collection', 'old-native', 'workloads', 'legacy'):
			old = RUNTIME/('stage2-'+host+'-regression')/suite
			result = load(old/'result.json'); recorded = load(old/'commands.json')
			by_name = {row['name']:row for row in recorded}
			identity = load(old/'identity.json') if (old/'identity.json').exists() else {}
			sources = {**identity.get('inputs', {}), **identity.get('sources', {}), **result.get('source_inputs', {})}
			products = {**identity.get('products', {}), **result.get('products', {})}
			if (old/'products.json').exists(): products.update(load(old/'products.json'))
			if (old/'programs.json').exists():
				for program in load(old/'programs.json'):
					sources.update(program['sources']); products.update(program['products'])
			for original in recorded:
				argv = original.get('argv', [])
				if not argv: continue
				if argv[0] != left['path'] or argv[1] != '-c': continue
				assert argv[2] in ('-O0', '-O2') and argv[3] == '-o'
				assert original['result']['status'] == 'EXPECTED_OUTCOME'
				inputs = argv[5:]
				assert inputs and all(sha(path) == sources[path] for path in inputs)
				assert sha(argv[4]) == products[argv[4]]
				prefix = original['name'].removesuffix('-compile')
				if (host, suite, prefix) in completed:
					assert completed[(host, suite, prefix)]['original_compile_argv'] == argv
					continue
				label = host+'-'+suite+'-'+prefix
				bucket = build/host/suite; bucket.mkdir(parents=True, exist_ok=True)
				obj = bucket/Path(argv[4]).name; target = bucket/prefix
				actual = [right['path'], *argv[1:4], str(obj), *inputs]
				run(label+'-compile', actual)
				assert obj.read_bytes() == Path(argv[4]).read_bytes(), ('fixed-path object difference', label)
				link = by_name[prefix+'-link']['argv']; output_index = link.index('-o')+1
				old_target = link[output_index]
				assert sha(old_target) == products[old_target]
				helpers = {path:sha(path) for path in link if path.endswith('.o') and path != argv[4]}
				linked = [str(obj) if part == argv[4] else str(target) if index == output_index else part for index, part in enumerate(link)]
				run(label+'-link', linked)
				assert target.read_bytes() == Path(old_target).read_bytes(), ('fixed-path ELF difference', label)
				if suite == 'workloads':
					native = next(row for row in recorded if 'result' in row and row['argv'][0] == old_target and row['result']['expected_exit'] == 0)
					expected = tuple((old/native['name']/stream).read_bytes() for stream in ('stdout', 'stderr'))
					expected_file = Path(native['argv'][2]).read_bytes()
					for memory in (False, True):
						name = label+('-memory' if memory else '-native')
						destination = build/(name+'.output')
						overrides = dict(native.get('environment_overrides', {}), CS_IO_REPORT=str(build/(name+'-io.json')))
						invocation = [str(target), native['argv'][1], str(destination)]
						if memory: invocation = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *invocation]
						assert run(name, invocation, overrides=overrides, memory=memory) == expected
						assert destination.read_bytes() == expected_file
				else:
					native = by_name[prefix+'-native']; expected_exit = native['result']['expected_exit']
					expected = tuple((old/native['name']/stream).read_bytes() for stream in ('stdout', 'stderr'))
					assert run(label+'-native', [target], expected_exit) == expected
					assert run(label+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], expected_exit, memory=True) == expected
				key = (host, suite, tuple(inputs))
				if key not in raw_inputs:
					old_ir = None
					for row in recorded:
						arguments = row.get('argv', [])
						if '--emit-llvm' not in arguments: continue
						at = arguments.index('--emit-llvm')
						if arguments[at+1:at+2] == ['-o'] and arguments[at+3:] == inputs:
							old_ir = arguments[at+2]; break
					assert old_ir is not None
					assert sha(old_ir) == products[old_ir]
					ir = bucket/Path(old_ir).name
					run(label+'-LLVM', [right['path'], '--emit-llvm', '-o', ir, *inputs])
					assert ir.read_bytes() == Path(old_ir).read_bytes(), ('fixed-path raw LLVM difference', label)
					run(label+'-LLVM-verify', ['opt', '-passes=verify', '-disable-output', ir])
					raw_inputs[key] = dict(path=str(ir), sha256=sha(ir), Stage2_path=old_ir, bitwise_equal=True)
				assert all(sha(path) == digest for path, digest in helpers.items())
				comparisons.append(dict(host_profile=host, target_profile=argv[2], suite=suite, case=prefix, Stage2_producer=left['path'], Stage3_producer=right['path'], sources={path:sources[path] for path in inputs}, exact_source_argument_identity=True, original_compile_argv=argv, actual_compile_argv=actual, Stage2_object=argv[4], Stage3_object=str(obj), object_sha256=sha(obj), Stage2_ELF=old_target, Stage3_ELF=str(target), ELF_sha256=sha(target), bitwise_object_equal=True, bitwise_ELF_equal=True, cached_C_support_objects=helpers, raw_LLVM=raw_inputs[key]))
				write(runtime/'comparisons.json', comparisons)
			print('FIXED_PATH', host, suite, 'PASS', flush=True)
	assert comparisons and all(sha(path) == digest for row in comparisons for path, digest in row['sources'].items())
	write(runtime/'result.json', dict(status='FIXED_PATH_STAGE2_STAGE3_CORPUS_BYTE_AND_NATIVE_MEMORY_PASS', fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), program_profiles=len(comparisons), reauthenticated_completed_program_profiles=len(completed), fresh_program_profiles=len(comparisons)-len(completed), exact_raw_LLVM_modules=len(raw_inputs), comparison_sha256=sha(runtime/'comparisons.json'), commands_sha256=sha(runtime/'commands.json'), source_selection='Exact Stage2 absolute source argument lists and recorded bytes; only producer and output destination change. C support objects are authenticated caches, never reused Astra objects or ELFs.', artifact_normalization='NONE'))


def convergence():
	assert authenticate()[0] == load(RUNTIME/'fixed-source.json')['source_rows']
	(RUNTIME/'comparison-executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	fixed = load(RUNTIME/'fixed-path-corpus/result.json')
	assert fixed['status'] == 'FIXED_PATH_STAGE2_STAGE3_CORPUS_BYTE_AND_NATIVE_MEMORY_PASS'
	assert sha(RUNTIME/'fixed-path-corpus/comparisons.json') == fixed['comparison_sha256']
	fixed_rows = load(RUNTIME/'fixed-path-corpus/comparisons.json')
	covered = {row[key] for row in fixed_rows for key in ('Stage2_object', 'Stage2_ELF')}
	pairs = []
	for first, second in ((1, 2), (2, 3)):
		left = load(RUNTIME/('stage'+str(first))/'result.json')
		right = load(RUNTIME/('stage'+str(second))/'result.json')
		assert left['fixed_source_sha256'] == right['fixed_source_sha256'] == sha(RUNTIME/'fixed-source.json')
		assert right['producer'] == {key:left['products']['O2'][key] for key in ('path', 'sha256')}
		for mode in ('O0', 'O2'):
			for kind, key in (('ELF', 'sha256'), ('object', 'object_sha256')):
				one = left['products'][mode][key]; two = right['products'][mode][key]
				pairs.append(dict(generations=[first, second], profile=mode, artifact=kind, first_sha256=one, second_sha256=two, bitwise_equal=one == two))
	write(RUNTIME/'generation-comparison.json', pairs)
	assert all(row['bitwise_equal'] for row in pairs), 'Retained native-generation difference requires investigation'
	differences = []; artifacts = []; behaviors = []; source_rows = []
	for mode in ('O0', 'O2'):
		left_root = BUILD/('stage2-'+mode+'-regression'); right_root = BUILD/('stage3-'+mode+'-regression')
		left_runtime = RUNTIME/('stage2-'+mode+'-regression'); right_runtime = RUNTIME/('stage3-'+mode+'-regression')
		for root in (left_runtime, right_runtime): assert load(root/'result.json')['status'] == 'ALL_RETAINED_CURRENT_SUITES_PASS'
		for path in sorted(left_runtime.rglob('*.astra')):
			relative = path.relative_to(left_runtime)
			if relative.parts[0] == 'jobs': continue
			other = right_runtime/relative
			assert other.is_file() and path.read_bytes() == other.read_bytes(), ('corpus source bytes changed', relative)
			source_rows.append(dict(host_profile=mode, path=str(relative), sha256=sha(path), byte_equal=True))
		def canonical_ir(data):
			for prefix in (str(left_runtime), str(right_runtime), str(left_root), str(right_root)):
				needle = prefix.encode()
				for line in data.splitlines():
					if needle in line:
						assert line.startswith((b'; ModuleID =', b'source_filename =')) or line.startswith(b'@') and b'constant' in line and b'c"' in line, ('unexpected path in LLVM instructions', line)
				canonical = prefix.replace('stage2-', 'stageN-').replace('stage3-', 'stageN-').encode()
				assert len(canonical) == len(needle)
				data = data.replace(needle, canonical)
			return data
			# Stage3's additional whole source/owner consumer build has separate proof.
		for path in sorted(left_root.rglob('*')):
			if not path.is_file(): continue
			name = path.relative_to(left_root)
			if name.parts[0] == 'jobs': continue
			other = right_root/name
			if not other.is_file(): differences.append(dict(profile=mode, missing=str(name))); continue
			if path.suffix not in ('.ll', '.o') and path.read_bytes()[:4] != b'\x7fELF': continue
			row = dict(host_profile=mode, path=str(name), first_sha256=sha(path), second_sha256=sha(other), bitwise_equal=sha(path) == sha(other))
			if not row['bitwise_equal']:
				if path.suffix == '.ll':
					one = canonical_ir(path.read_bytes()); two = canonical_ir(other.read_bytes())
					row.update(comparison='SOURCE_ORIGIN_AND_MODULE_FILENAME_METADATA_ONLY', normalized_equal=one == two, first_normalized_sha256=hashlib.sha256(one).hexdigest(), second_normalized_sha256=hashlib.sha256(two).hexdigest())
					if one != two: differences.append(row)
				elif str(path) in covered:
					row['comparison'] = 'DIFFERENT_FIXTURE_PATHS; EXACT_NATIVE_BYTES_PROVED_BY_FIXED_PATH_REPLAY'
				elif re.search(r'-C0(?:\.o)?$', path.name) or '-baseline-' in path.name or path.name in ('observe.o', 'observer.o', 'allocation-observer.o', 'bridge.o'):
					row['comparison'] = 'C0_OR_GCC_TEST_SUPPORT; RAW_DIFFERENCE_RETAINED; NO_STAGE3_BYTE_IDENTITY_CREDIT'
				else:
					row['comparison'] = 'UNEXPLAINED_NATIVE_DIFFERENCE'
					differences.append(row)
			artifacts.append(row)
		for commands in sorted(left_runtime.glob('*/commands.json')):
			relative = commands.relative_to(left_runtime); other_commands = right_runtime/relative
			if not other_commands.is_file(): differences.append(dict(missing_commands=str(relative))); continue
			one = load(commands); two = load(other_commands)
			assert [row['name'] for row in one] == [row['name'] for row in two]
			for a, b in zip(one, two):
				# Raw argv cases carry explicit exit/expected fields; their execution
				# is independently checked by the retained application recipe.
				if 'result' not in a:
					assert (a['exit'], a['expected_exit']) == (b['exit'], b['expected_exit'])
					continue
				assert (a['result']['exit'], a['result']['expected_exit']) == (b['result']['exit'], b['result']['expected_exit'])
				name = a['name']; suite = relative.parts[0]
				for stream in ('stdout', 'stderr'):
					p = left_runtime/suite/name/stream; q = right_runtime/suite/name/stream
					if not p.exists(): continue
					before = p.read_bytes(); after = q.read_bytes()
					if stream == 'stderr' and any(Path(part).name == 'valgrind' for part in a['argv']):
						# Zero live bytes/errors/suppressions are independently asserted;
						# remove only Valgrind's process-statistics lines for diagnostics.
						for raw in (before, after):
							assert all(marker in raw for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
						before = re.sub(rb'^==\d+==[^\n]*\n', b'', before, flags=re.M)
						after = re.sub(rb'^==\d+==[^\n]*\n', b'', after, flags=re.M)
						# Normalize only known task output roots; spans/messages stay exact.
					for prefix in (str(left_runtime), str(right_runtime), str(left_root), str(right_root)):
						before = before.replace(prefix.encode(), b'{generation-root}')
						after = after.replace(prefix.encode(), b'{generation-root}')
					row = dict(host_profile=mode, suite=suite, command=name, stream=stream, normalized_equal=before == after, first_raw_sha256=sha(p), second_raw_sha256=sha(q))
					behaviors.append(row)
					if not row['normalized_equal']: differences.append(row)
	write(RUNTIME/'corpus-artifact-comparison.json', artifacts)
	write(RUNTIME/'corpus-input-identity.json', source_rows)
	write(RUNTIME/'corpus-unfixed-raw-differences.json', [row for row in artifacts if not row['bitwise_equal']])
	write(RUNTIME/'corpus-behavior-comparison.json', behaviors)
	write(RUNTIME/'convergence-differences.json', differences)
	assert artifacts and behaviors and not differences, 'Retained corpus difference requires investigation'
	write(RUNTIME/'convergence.json', dict(status='FIXED_SOURCE_GENERATION_AND_CORPUS_CONVERGENCE_PASS', fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), generation_pairs=len(pairs), unfixed_path_artifacts=len(artifacts), unfixed_path_raw_byte_equal=sum(row['bitwise_equal'] for row in artifacts), unfixed_path_raw_differences=sum(not row['bitwise_equal'] for row in artifacts), fixed_path_program_profiles=fixed['program_profiles'], fixed_path_exact_raw_LLVM_modules=fixed['exact_raw_LLVM_modules'], fixed_path_proof_sha256=sha(RUNTIME/'fixed-path-corpus/result.json'), normalized_behavior_streams=len(behaviors), normalization='Compiler generation objects/ELFs and the same-absolute-input corpus replay LLVM/objects/ELFs are byte-exact with no artifact normalization. Independent per-suite fixtures have different absolute source paths: retain all raw differences, compare LLVM only after equal-length replacement of declared source/output roots in origin constants and module filename metadata, and compare diagnostics after declared root replacement. No binary normalization is used. C0/GCC observer/oracle artifacts receive no Stage3 byte-identity credit. Strict Valgrind stderr markers are checked before omitting PID/statistics lines; stdout is compared as program output.', generation_comparison_sha256=sha(RUNTIME/'generation-comparison.json'), artifact_comparison_sha256=sha(RUNTIME/'corpus-artifact-comparison.json'), behavior_comparison_sha256=sha(RUNTIME/'corpus-behavior-comparison.json'), differences_sha256=sha(RUNTIME/'convergence-differences.json')))


def check_streams(directory):
	count = 0
	for path in directory.rglob('result.json'):
		data = load(path)
		if not isinstance(data, dict) or 'stdout_sha256' not in data: continue
		assert data['status'] == 'EXPECTED_OUTCOME' and not data['timed_out'], path
		for stream, name in (('stdout', 'stdout'), ('stderr', 'stderr'), ('time', 'time' if 'metrics' in data else 'time.txt')):
			assert sha(path.parent/name) == data[stream+'_sha256'], path
		count += 1
	return count


def audit():
	rows, prior = authenticate()
	modes = load(RUNTIME/'language-modes.json')
	assert modes['fixed_source_sha256'] == sha(RUNTIME/'fixed-source.json')
	assert {row['path']:row['sha256'] for row in modes['source_rows']} == {row['path']:row['sha256'] for row in rows}
	converged = load(RUNTIME/'convergence.json')
	assert converged['status'] == 'FIXED_SOURCE_GENERATION_AND_CORPUS_CONVERGENCE_PASS'
	assert (RUNTIME/'comparison-executed-recipe.py.txt').read_bytes() == Path(__file__).read_bytes()
	for name, key in (('generation-comparison.json', 'generation_comparison_sha256'), ('corpus-artifact-comparison.json', 'artifact_comparison_sha256'), ('corpus-behavior-comparison.json', 'behavior_comparison_sha256'), ('convergence-differences.json', 'differences_sha256'), ('fixed-path-corpus/result.json', 'fixed_path_proof_sha256')):
		assert sha(RUNTIME/name) == converged[key]
	assert not load(RUNTIME/'convergence-differences.json')
	fixed = load(RUNTIME/'fixed-path-corpus/result.json')
	for name, key in (('comparisons.json', 'comparison_sha256'), ('commands.json', 'commands_sha256')):
		assert sha(RUNTIME/'fixed-path-corpus'/name) == fixed[key]
	for row in load(RUNTIME/'fixed-path-corpus/comparisons.json'):
		assert all(sha(path) == digest for path, digest in {**row['sources'], **row['cached_C_support_objects']}.items())
		assert sha(row['Stage2_object']) == sha(row['Stage3_object']) == row['object_sha256']
		assert sha(row['Stage2_ELF']) == sha(row['Stage3_ELF']) == row['ELF_sha256']
		assert sha(row['raw_LLVM']['path']) == sha(row['raw_LLVM']['Stage2_path']) == row['raw_LLVM']['sha256']
	assert not git('diff', '--name-only').strip() and not git('diff', '--cached', '--name-only').strip()
	stages = []; measurements = []; memory = []; physical = []
	for stage in (1, 2, 3):
		directory = RUNTIME/('stage'+str(stage)); result = load(directory/'result.json')
		assert sha(directory/'identity.json') == result['identity_sha256']
		identity = load(directory/'identity.json')
		assert sha(directory/'executed-recipe.py.txt') == identity['recipe_sha256']
		assert identity['sources'] == load(RUNTIME/'fixed-source.json')['sources']
		for group in ('tools', 'provider_objects', 'sources'):
			assert all(sha(path) == digest for path, digest in identity[group].items())
		for mode in ('O0', 'O2'):
			product = result['products'][mode]
			assert sha(product['path']) == product['sha256'] and sha(product['object']) == product['object_sha256']
			plan = load(directory/mode/'plan.json'); receipt = load(directory/mode/'compile-receipt.json')
			assert receipt['argv'] == plan['argv'] and receipt['result']['fresh_execution']
			assert plan['argv'][5:] == list(identity['sources']) and not plan['output_preexisting']
			metrics = {}
			for line in (directory/mode/'compile/time.txt').read_text().splitlines():
				for key in ('User time (seconds)', 'System time (seconds)', 'Elapsed (wall clock) time (h:mm:ss or m:ss)', 'Maximum resident set size (kbytes)', 'Exit status'):
					if line.strip().startswith(key+':'): metrics[key] = line.strip()[len(key)+1:].strip()
			measurements.append(dict(stage=stage, host_profile=mode, producer=result['producer'], product_sha256=product['sha256'], fixed_source_sha256=result['fixed_source_sha256'], GNU_time=metrics))
			regression = RUNTIME/('stage'+str(stage)+'-'+mode+'-regression')
			campaign = load(regression/'result.json')
			assert campaign['status'] == 'ALL_RETAINED_CURRENT_SUITES_PASS'
			for suite in campaign['suites']:
				root = regression/suite['name']; proof = load(root/'result.json')
				assert sha(root/'result.json') == suite['receipt_sha256']
				assert suite['result']['status'] == 'EXPECTED_OUTCOME'
				if 'compiler_sha256' in proof: assert proof['compiler_sha256'] == product['sha256']
				for name, key in (('identity.json', 'identity_sha256'), ('commands.json', 'commands_sha256'), ('programs.json', 'programs_sha256'), ('observations.json', 'observations_sha256')):
					if key in proof: assert sha(root/name) == proof[key]
				suite_identity = load(root/'identity.json') if (root/'identity.json').exists() else {}
				for model in (proof, suite_identity):
					for group in ('inputs', 'sources', 'actual_sources', 'source_inputs', 'providers', 'tools', 'products'):
						for path, digest in model.get(group, {}).items():
							if isinstance(digest, dict):
								assert sha(digest['path']) == digest['sha256']
							else: assert sha(path) == digest
				if (root/'products.json').exists():
					assert all(sha(path) == digest for path, digest in load(root/'products.json').items())
				if (root/'programs.json').exists():
					for program in load(root/'programs.json'):
						assert all(sha(path) == digest for group in ('sources', 'products') for path, digest in program[group].items())
			for row in load(regression/'plans.json'): assert sha(row['recipe']) == row['recipe_sha256']
			for path in regression.rglob('stderr'):
				data = path.read_bytes()
				if b'ERROR SUMMARY:' not in data: continue
				assert all(marker in data for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), path
				memory.append(dict(path=str(path), sha256=sha(path)))
			for path in regression.glob('physical-*/result.json'):
				proof = load(path); assert proof['status'] == 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'
				observations = load(path.with_name('observations.json'))
				assert len(observations) == proof['mutations']+proof['controls']
				for row in observations:
					assert row['observations']['structural-return']['returned'] == 0
					assert row['observations']['inferior-exit']['exit'] == int(not row['action'].endswith('control'))
				physical.append(dict(stage=stage, host_profile=mode, path=str(path), sha256=sha(path), mutations=proof['mutations'], controls=proof['controls']))
		observed = set()
		for path in directory.glob('process-observation-*.json'):
			for row in load(path):
				assert row['executable_sha256'] == result['producer']['sha256']
				assert set(row['LLVM'].values()) == {'3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d'}
				observed.add(row['mode'])
		assert observed == {'O0', 'O2'}
		stages.append(result)
	protected = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	write(RUNTIME/'preservation-final.json', protected)
	write(RUNTIME/'measurements.json', measurements)
	write(RUNTIME/'strict-memory-streams.json', memory)
	write(RUNTIME/'physical-receipts.json', physical)
	streams = check_streams(RUNTIME)
	costs = []
	for path in sorted(RUNTIME.rglob('result.json')):
		result = load(path)
		if not isinstance(result, dict) or 'stdout_sha256' not in result: continue
		metrics = {}
		for line in path.with_name('time' if 'metrics' in result else 'time.txt').read_text().splitlines():
			for key in ('User time (seconds)', 'System time (seconds)', 'Elapsed (wall clock) time (h:mm:ss or m:ss)', 'Maximum resident set size (kbytes)', 'Exit status'):
				if line.strip().startswith(key+':'): metrics[key] = line.strip()[len(key)+1:].strip()
		costs.append(dict(execution=str(path.parent.relative_to(RUNTIME)), result_sha256=sha(path), GNU_time=metrics, monotonic_wall_seconds=result['seconds'], actual_exit=result['exit'], expected_exit=result['expected_exit']))
	write(RUNTIME/'execution-costs.json', dict(format='astra27d-execution-costs/1', executions=costs, overlapping_intervals_not_summed=True))
	write(RUNTIME/'engineering-audit.json', dict(format='astra27d-engineering-audit/1', status='ENGINEERING_G0_G7_PASS_G8_PENDING', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), HEAD=git('rev-parse', 'HEAD').decode().strip(), tree=git('rev-parse', 'HEAD^{tree}').decode().strip(), fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), source_revision=BASE, source_tree=TREE, gates={**{'G'+str(n):'PASS' for n in range(8)}, 'G8':'PENDING_SEPARATE_AFTER_PUBLICATION_CHECK'}, stages=stages, GNU_time_measurements=measurements, raw_execution_streams_reauthenticated=streams, strict_returning_memory_streams=len(memory), physical_mutations=sum(row['mutations'] for row in physical), physical_controls=sum(row['controls'] for row in physical), preservation=protected, history=dict(milestone27B='HISTORICAL_PARTIAL', missing_original_raw_proof_files=1044, original_C0='LOST', rebuilt_C0_strict_all_kinds_process_memory='NOT_PASS_REACHABLE_GLIB_LLVM_GLOBALS', new_27B_delivery_G5='PASS_RETAINED', current_27C_delivery_G7='PASS_RETAINED_SEPARATE_FROM_IMMUTABLE_PREPUBLICATION_PENDING', release_owner_decision='REQUIRED_FOR_MILESTONE28; NOT_WAIVED'), LLVM='23.1.4_BYTE_AUTHENTICATED', E25_A_v1='d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e', generic_ceiling=256, SSA_work=8000000, release_credit=False))
	print('ENGINEERING_G0_G7_PASS_G8_PENDING', flush=True)


def package():
	proof = load(RUNTIME/'engineering-audit.json')
	assert proof['HEAD'] == git('rev-parse', 'HEAD').decode().strip()
	publication = WORK/'runtime/selfhost27d-publication'; publication.mkdir(exist_ok=False)
	snapshot = publication/'payload'; snapshot.mkdir()
	aliases = []
	for label, root in (('runtime', RUNTIME), ('build', BUILD)):
		for path in sorted(root.rglob('*')):
			# This concatenation is reconstructed byte-exactly from the embedded
			# predecessor report's segments; avoid transporting it twice.
			if path == RUNTIME/'predecessor-transport.tar.xz': continue
			if path.is_symlink():
				aliases.append(dict(path=label+'/'+str(path.relative_to(root)), target=os.readlink(path)))
				continue
			if not path.is_file(): continue
			destination = snapshot/label/path.relative_to(root)
			destination.parent.mkdir(parents=True, exist_ok=True)
			shutil.copy2(path, destination)
	write(snapshot/'symlink-aliases.json', aliases)
	paths = {row['path'] for row in load(RUNTIME/'fixed-source.json')['source_rows']}
	paths.update(git('diff', '--name-only', BASE, 'HEAD').decode().splitlines())
	paths.update(str(Path(row['original_path']).relative_to(ROOT)) for row in load(PRIOR/'snapshot.json')['sources'])
	for name in sorted(paths):
		destination = snapshot/'source'/name; destination.parent.mkdir(parents=True, exist_ok=True)
		destination.write_bytes((ROOT/name).read_bytes())
	packet = WORK/'runtime/native-current/input'
	for name in ('27c-delivered-report.zip', '27c-original-submission.zip', '27c-post-delivery-G7.json'):
		destination = snapshot/'predecessor'/name; destination.parent.mkdir(parents=True, exist_ok=True)
		shutil.copy2(packet/'reference/previous'/name, destination)
	for name in ('build-identity.json', 'snapshot.json', 'result.json', 'link.json'):
		destination = snapshot/'seed'/name; destination.parent.mkdir(parents=True, exist_ok=True)
		shutil.copy2(PRIOR/name, destination)
	assert sha(SEED) == SEED_SHA
	shutil.copy2(SEED, snapshot/'seed/astrac-O2')
	for obj in load(PRIOR/'build-identity.json')['objects']:
		path = Path(obj)
		for source in (path, path.with_suffix('.identity.json')): shutil.copy2(source, snapshot/'seed'/source.name)
	sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
	from evidence import pack, verify
	archive = publication/'evidence.tar.xz'
	transport = pack(['payload='+str(snapshot)], archive, publication)
	transport['reconstruction'] = verify(archive, publication)
	delivery = publication/'attachments'; delivery.mkdir()
	segments = []
	with archive.open('rb') as stream:
		while block := stream.read(2*1024**2):
			name = 'transport-'+str(len(segments)).zfill(3)+'.indices'
			(delivery/name).write_bytes(block)
			segments.append(dict(path=name, bytes=len(block), sha256=sha(delivery/name)))
	transport['segments'] = segments
	write(delivery/'transport.json', transport)
	for name in ('engineering-audit.json', 'fixed-source.json', 'language-modes.json', 'convergence.json', 'measurements.json', 'preservation-final.json', 'intake.json'):
		shutil.copy2(RUNTIME/name, delivery/name)
	index = dict(format='pm-next-evidence/1', files=[dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(delivery.iterdir())])
	write(delivery/'INDEX.json', index)
	print('REPORT_EVIDENCE_READY', transport['archive_bytes'], len(segments), flush=True)


def delivery():
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	started = time.time_ns(); assert started > report.stat().st_mtime_ns
	intake = load(WORK/'runtime/native-current/pm-next-intake.json')
	assert intake['published'] and intake['milestone_id'] == 'ASTRA-SELFHOST-27D-FINAL-SELFHOST-CONVERGENCE'
	sys.path.insert(0, str(Path.home()/'.agents/skills/pm-next/scripts'))
	from common import verify_zip
	manifest, digest = verify_zip(report, 'pm-codex-report/1')
	assert digest == intake['report_sha256']
	head = git('rev-parse', 'HEAD').decode().strip(); tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	assert intake['final_commit'] == head and intake['final_tree'] == tree
	assert not git('status', '--porcelain=v1', '--untracked-files=no').strip()
	assert authenticate()[0] == load(RUNTIME/'fixed-source.json')['source_rows']
	runtime = WORK/'runtime/selfhost27d-delivery-G8'; build = WORK/'build/selfhost27d-delivery-G8'
	runtime.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	write(runtime/'start.json', dict(UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), started_UTC_ns=started, publication_UTC=intake['published_utc'], report_sha256=digest, HEAD=head, tree=tree, recipe_sha256=sha(__file__)))
	archive = runtime/'published-evidence.tar.xz'
	with zipfile.ZipFile(report) as packed:
		result = json.loads(packed.read('RESULT.json'))
		assert result['status'] == 'PASS' and result['final_commit'] == head and result['final_tree'] == tree
		assert result['submission_sha256'] == intake['submission_sha256']
		audit = json.loads(packed.read('evidence/engineering-audit.json'))
		assert audit['gates']['G8'] == 'PENDING_SEPARATE_AFTER_PUBLICATION_CHECK'
		assert packed.read('evidence/engineering-audit.json') == (RUNTIME/'engineering-audit.json').read_bytes()
		assert packed.read('evidence/fixed-source.json') == (RUNTIME/'fixed-source.json').read_bytes()
		index = json.loads(packed.read('evidence/INDEX.json'))
		for row in index['files']:
			raw = packed.read('evidence/'+row['path'])
			assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
		transport = json.loads(packed.read('evidence/transport.json'))
		with archive.open('xb') as out:
			for row in transport['segments']:
				raw = packed.read('evidence/'+row['path'])
				assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
				out.write(raw)
		assert sha(archive) == transport['archive_sha256']
	sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
	from evidence import verify
	reconstruction = verify(archive, runtime)
	write(runtime/'reconstruction.json', reconstruction)
	with tarfile.open(archive, 'r|xz') as packed:
		model = None
		for member in packed:
			if member.name == 'INDEX.json': model = json.load(packed.extractfile(member))
	assert model is not None
	for row in load(RUNTIME/'fixed-source.json')['source_rows']:
		proof = model['files']['payload/source/'+row['path']]
		assert proof['sha256'] == sha(ROOT/row['path']) == row['sha256'] and proof['bytes'] == row['bytes']
	stage = load(RUNTIME/'stage3/result.json')
	for mode, product in stage['products'].items():
		assert model['files']['payload/build/stage3/astrac-'+mode]['sha256'] == sha(product['path']) == product['sha256']
	c0 = WORK/'build/selfhost27b/c0-recovery-safealloc2/astrac'
	commands = []
	for mode, product in stage['products'].items():
		identity = ['--compiler', product['path'], '--compiler-sha256', product['sha256']]
		linked = [*identity, '--c0', str(c0), '--c0-sha256', sha(c0), '--link', str(PRIOR/'link.json'), '--oracle-library-inputs', str(WORK/'runtime/selfhost27c-dev20/inputs.json')]
		modern = ROOT/'tests/selfhost-expressive-language-27c'
		for name, recipe, extra in (
			('range', modern/'named.py', [*linked, '--feature', 'range', '--case', 'range-collect-literal', '--case', 'range-stride']),
			('match', modern/'named.py', [*linked, '--feature', 'match']),
			('physical', modern/'physical.py', [*identity, '--feature', 'range']),
		):
			label = mode+'-'+name
			argv = [sys.executable, '-B', str(recipe), *extra, '--build', str(build/label), '--runtime', str(runtime/label)]
			outcome = execute(argv, runtime/(label+'-controller'), timeout=3600, env=environment())
			commands.append(dict(name=label, argv=argv, result=outcome, receipt_sha256=sha(runtime/label/'result.json') if (runtime/label/'result.json').exists() else None))
			write(runtime/'commands.json', commands)
			assert outcome['status'] == 'EXPECTED_OUTCOME', (label, outcome)
		negative = runtime/(mode+'-range')/'range-slice-escape-negative.astra'
		negative_identity = load(runtime/(mode+'-range')/'identity.json')
		assert sha(negative) == negative_identity['inputs'][str(negative)]
		marker = b'27D_POST_PUBLICATION_NEGATIVE_MEMORY_REFUSAL\n'
		destination = build/(mode+'-negative-memory.ll'); destination.write_bytes(marker)
		argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product['path'], '--emit-llvm', '-o', destination, negative]
		label = mode+'-negative-compiler-memory'
		outcome = execute(argv, runtime/label, expected=1, timeout=300, env=environment())
		assert outcome['status'] == 'EXPECTED_OUTCOME' and destination.read_bytes() == marker
		log = (runtime/label/'stderr').read_bytes()
		assert b': error:' in log and all(value in log for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		commands.append(dict(name=label, argv=list(map(str, argv)), result=outcome)); write(runtime/'commands.json', commands)
	consumer = load(RUNTIME/'stage3-O2-regression/source-owner-consumers/result.json')
	consumer_root = RUNTIME/'stage3-O2-regression/source-owner-consumers'
	assert model['files']['payload/runtime/stage3-O2-regression/source-owner-consumers/result.json']['sha256'] == sha(consumer_root/'result.json')
	assert model['files']['payload/runtime/stage3-O2-regression/source-owner-consumers/identity.json']['sha256'] == sha(consumer_root/'identity.json') == consumer['identity_sha256']
	consumer_identity = load(consumer_root/'identity.json')
	for group in ('sources', 'actual_sources', 'providers', 'tools'):
		assert all(sha(path) == value for path, value in consumer_identity[group].items())
	for mode, product in consumer['products'].items():
		assert sha(product['path']) == product['sha256']
		assert model['files']['payload/build/stage3-O2-regression/source-owner-consumers/component-'+mode]['sha256'] == product['sha256']
		for memory in (False, True):
			label = 'source-owner-'+mode+('-memory' if memory else '-native')
			argv = [product['path']]
			if memory: argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
			outcome = execute(argv, runtime/label, expected=42, timeout=600, env=environment())
			assert outcome['status'] == 'EXPECTED_OUTCOME'
			assert b'MEMBER_DISPATCH_SOURCE_AND_CONSUMER_CONTROLS_PASS' in (runtime/label/'stdout').read_bytes()
			if memory:
				log = (runtime/label/'stderr').read_bytes()
				assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			commands.append(dict(name=label, argv=argv, result=outcome)); write(runtime/'commands.json', commands)
	assert sha(report) == digest and git('rev-parse', 'HEAD').decode().strip() == head
	check_streams(runtime)
	write(runtime/'result.json', dict(status='POST_DELIVERY_27D_G8_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), verification_started_UTC_ns=started, publication_UTC=intake['published_utc'], report=dict(path=str(report), bytes=report.stat().st_size, sha256=digest, indexed_payloads=len(manifest['files'])), HEAD=head, tree=tree, fixed_source_sha256=sha(RUNTIME/'fixed-source.json'), transport_sha256=sha(archive), reconstruction=reconstruction, Stage3=stage, commands_sha256=sha(runtime/'commands.json'), immutable_prepublication_G8='PENDING', release_credit=False))
	print('POST_DELIVERY_27D_G8_PASS', digest, flush=True)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('command', choices=('intake', 'modes', 'generate', 'observe', 'regress', 'fixed-corpus', 'compare', 'audit', 'package', 'delivery'))
	p.add_argument('--stage', type=int, choices=(1, 2, 3))
	p.add_argument('--mode', choices=('O0', 'O2'), default='O2')
	a = p.parse_args()
	if a.command == 'intake': intake()
	elif a.command == 'modes': language_modes()
	elif a.command == 'compare': convergence()
	elif a.command == 'fixed-corpus': fixed_corpus()
	elif a.command == 'audit': audit()
	elif a.command == 'package': package()
	elif a.command == 'delivery': delivery()
	else:
		assert a.stage
		if a.command == 'generate': generate(a.stage)
		elif a.command == 'observe': observe(a.stage)
		else: regress(a.stage, a.mode)


if __name__ == '__main__':
	main()
