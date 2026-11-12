#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One-shot, measured development builds, reusable artifacts and parallel tests."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from run import ROOT, WORK, C0_SHA256, sha
from acceleration import authenticate, cached_product, environment, execute, expected_product_identity, fingerprint, output_path, process_sample, restored_command, run_jobs, write


def leaf(args, name):
	assert args.version.isalnum()
	parent = output_path(args.runtime_root, WORK/'runtime')
	assert parent.is_dir()
	path = parent/(name+'-'+args.version)
	path.mkdir()
	write(path/'request.json', dict(argv=sys.argv, recipe_sha256=sha(__file__), support_sha256=sha(Path(__file__).with_name('acceleration.py')), UTC_ns=time.time_ns(), qualification_credit=0))
	return path


def compile_plan(args):
	output = leaf(args, 'accelerated-build')
	assert args.timeout_seconds > 0
	plan = json.loads(args.identity.read_text())
	assert Path(plan['argv'][0]).is_file() and sha(plan['argv'][0]) == C0_SHA256
	assert plan['argv'][1] in ('-O0', '-O2') and plan['argv'][-2] == '-o'
	assert os.environ.get('CCACHE_DISABLE') == '1'
	authenticate(expected_product_identity(plan))
	lock_dir = args.runtime_root/'acceleration-locks'; lock_dir.mkdir(exist_ok=True)
	with (lock_dir/(fingerprint(plan['argv'])+'.lock')).open('a') as lock:
		fcntl.flock(lock, fcntl.LOCK_EX)
		product = cached_product(plan)
		if product is None and args.join_result is None:
			pending = []
			for record in args.runtime_root.glob('compile-plan-*/plan.json'):
				data = json.loads(record.read_text())
				if data['original_plan_sha256'] == sha(args.identity) and not record.with_name('result.json').exists():
					pending.append(record.parent)
			assert len(pending) <= 1, 'multiple incomplete matching builds require diagnosis; no duplicate started'
			if pending:
				args.join_result = pending[0]/'result.json'
				args.join_running = pending[0]/'running.json'
		if product is not None:
			result = dict(status='EXACT_PRODUCT_REUSED', fresh_execution=False, product=product, cold_build=False, qualification_credit=0)
		elif args.join_result:
			assert args.join_running
			running = json.loads(args.join_running.read_text())
			assert running['argv'] == plan['argv']
			pid = running['pid']; initial = process_sample(pid)
			assert initial is not None, 'no matching running build'
			command = Path('/proc/'+str(pid)+'/cmdline').read_bytes().split(b'\0')
			command = [value.decode() for value in command if value]
			assert command[-len(plan['argv']):] == plan['argv'], 'running PID command mismatch'
			started = time.monotonic()
			while not args.join_result.exists():
				current = process_sample(pid)
				assert current is not None and current['start_ticks'] == initial['start_ticks'], 'build ended without its result; preserve receipts and diagnose'
				assert time.monotonic()-started < args.timeout_seconds, 'join observation timeout; existing build was not killed'
				write(output/'progress.json', dict(status='JOINING_EXISTING_BUILD', waited_seconds=time.monotonic()-started, process=current, fresh_execution=False))
				time.sleep(1)
			actual = json.loads(args.join_result.read_text())
			assert actual['exit'] == 0 and not actual['timed_out']
			product = cached_product(plan); assert product
			result = dict(status='EXISTING_BUILD_JOINED', fresh_execution=False, product=product, original_result=str(args.join_result), original_result_sha256=sha(args.join_result), qualification_credit=0)
		else:
			command = [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/compile-plan.py', '--identity', args.identity, '--runtime-root', args.runtime_root, '--version', args.version, '--timeout-seconds', str(args.timeout_seconds)]
			if args.profile:
				command = ['perf', 'record', '--no-buildid-cache', '-m', '8', '-e', 'cycles:u', '-F', '49', '-o', output/'perf.data', '--', *restored_command(plan['environment'], command)]
			result = execute(command, output/'execution', timeout=args.timeout_seconds+60, env=environment(plan['environment']))
			if result['status'] != 'EXPECTED_OUTCOME':
				write(output/'result.json', result)
				raise RuntimeError('compile failed; failed receipts retained and no automatic duplicate build launched')
			product = cached_product(plan); assert product
			result.update(status='FRESH_PRODUCT_BUILT', product=product, cold_build=True, sampled=args.profile)
	write(output/'result.json', result)
	print(result['status'], output, flush=True)
	return result


def profile_command(args):
	output = leaf(args, 'profiled-command')
	plan = json.loads(args.identity.read_text())
	assert plan['argv'] and sha(plan['argv'][0]) == C0_SHA256
	authenticate(plan)
	command = ['perf', 'record', '--no-buildid-cache', '-m', '8', '-e', 'cycles:u', '-F', '49', '-o', output/'perf.data', '--', *restored_command(plan['environment'], plan['argv'])]
	result = execute(command, output/'execution', timeout=args.timeout_seconds, expected=args.expected_exit, env=environment(plan['environment']))
	authenticate(plan)
	result.update(sampled_command=plan['argv'], identity_sha256=sha(args.identity), perf_sha256=sha(shutil.which('perf')), perf_data_sha256=sha(output/'perf.data') if (output/'perf.data').exists() else None)
	write(output/'result.json', result)
	assert result['status'] == 'EXPECTED_OUTCOME', result
	print('PROFILED_EXPECTED_OUTCOME', output, flush=True)


def jobs(args):
	assert args.version.isalnum()
	spec = json.loads(args.spec.read_text())
	result = run_jobs(spec, args.runtime_root/('jobs-'+args.version), args.build_root/('jobs-'+args.version), args.runtime_root/'artifact-cache', jobs=args.jobs, max_jobs=args.max_jobs, reserve_bytes=args.reserve_GiB*1024**3, reuse=args.reuse)
	print(result['status'], len(result['jobs']), 'jobs;', result['artifact_reuse_count'], 'reused;', result['execution_interval_union_seconds'], 'active wall seconds', flush=True)
	assert not result['failed_jobs'], result['failed_jobs']


def qualification(args):
	identity = json.loads(args.component.with_suffix('.identity.json').read_text())
	assert sha(args.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+args.mode
	authenticate(identity['identity'])
	native = args.runtime_root/('native-frontiers-'+args.version+'-'+args.mode)/'result.json'
	extra = WORK/('runtime/effects25-r5-resume/native-frontiers-errorextra1-'+args.mode+'/result.json')
	assert extra.is_file()
	entries = [
		('original-and-owner-native', 'recover-native-frontiers', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('source-stage-mutations', 'recover-stage-frontiers', ['--observer', args.component, '--version', args.version+args.mode, '--fixtures', native]),
		('array-source-negatives', 'recover-array-source-negative', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('owner-source-negatives', 'recover-owner-source-negative', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('dynamic-source-faults', 'recover-dynamic-faults', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('error-order', 'recover-error-order-native', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('error-lifetime', 'recover-error-lifetime', ['--component', args.component, '--mode', args.mode, '--version', args.version, '--fixtures', extra]),
		('frontier-physical', 'recover-frontier-physical-proof', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('error-physical', 'recover-error-physical-proof', ['--component', args.component, '--mode', args.mode, '--version', args.version, '--valid-field-receiver']),
		('exact-identity-reuse', 'recover-r5-warm', ['--component', args.component, '--mode', args.mode, '--version', args.build_version]),
		('retained-41-recipes', 'recover-resume-retained', ['--component', args.component, '--mode', args.mode, '--version', args.version]),
		('strict-raw-drift', 'recover-resume-retained', ['--recipe', 'recover-r5-drift', '--mode', args.mode, '--version', args.version]),
	]
	dependencies = {'source-stage-mutations':['original-and-owner-native'], 'strict-raw-drift':['retained-41-recipes']}
	selected = set(args.focus or [row[0] for row in entries])
	assert selected <= {row[0] for row in entries}
	for name in list(selected):
		selected.update(dependencies.get(name, ()))
	tools = {str(Path(sys.executable).resolve()):sha(Path(sys.executable).resolve()), str(args.component):sha(args.component)}
	inputs = {str(args.component.with_suffix('.identity.json')):sha(args.component.with_suffix('.identity.json')), str(extra):sha(extra)}
	env = {key:None for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE')}; env['CCACHE_DISABLE'] = '1'
	items = []
	for name, recipe, arguments in entries:
		if name not in selected:
			continue
		argv = [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/route.py', '--build-root', args.build_root, '--runtime-root', args.runtime_root, recipe, *arguments]
		items.append(dict(id=name, argv=list(map(str, argv)), needs=dependencies.get(name, []), inputs=inputs, tools=tools, environment=env, expected_exit=0, timeout_seconds=7200, cache='fresh', estimated_RSS_bytes=6*1024**3))
	spec = dict(format='astra-native-jobs/1', jobs=items, total_campaign_jobs=len(entries), selected_jobs=sorted(selected), profile=args.mode, historical_R5_failures_unchanged=True)
	request = leaf(args, 'qualification-request')
	write(request/'jobs.json', spec)
	result = run_jobs(spec, args.runtime_root/('parallel-qualification-'+args.version+'-'+args.mode), args.build_root/('parallel-qualification-'+args.version+'-'+args.mode), args.runtime_root/'artifact-cache', jobs=args.jobs, max_jobs=args.max_jobs, reserve_bytes=args.reserve_GiB*1024**3, reuse=False)
	write(request/'result.json', dict(**result, total_campaign_jobs=len(entries), selected_jobs=sorted(selected), component_sha256=identity['sha256'], limitation='Fresh selected recipe outcomes only; no subset or process exit proves full compiler completeness. Historical failed campaigns retain their status.'))
	assert not result['failed_jobs'], result['failed_jobs']


def status(args):
	rows = []
	for path in args.receipt:
		if not path.exists():
			rows.append(dict(path=str(path), status='PENDING'))
			continue
		data = json.loads(path.read_text())
		row = dict(path=str(path), modified_UTC_ns=path.stat().st_mtime_ns, update_age_seconds=max(0, time.time()-path.stat().st_mtime))
		if isinstance(data, list):
			row['latest_events'] = data[-4:]
		else:
			row.update({key:data[key] for key in ('status', 'actual_exit', 'native_exit', 'seconds', 'elapsed_seconds', 'overall_acceptance', 'full_original_native_profiles', 'total', 'completed', 'active', 'pending', 'worker_limit', 'cold_execution_count', 'artifact_reuse_count', 'failed_jobs', 'active_stage_functions') if key in data})
			if 'jobs' in data:
				row['job_outcomes'] = {name:{key:value for key, value in job.items() if key in ('status', 'exit', 'seconds', 'fresh_execution', 'metrics')} for name, job in data['jobs'].items()}
			if 'pid' in data:
				row['process'] = process_sample(data['pid'])
				if row['process'] is not None and 'monotonic_start' in data:
					row['observed_elapsed_seconds'] = time.monotonic()-data['monotonic_start']
			if data and all(key.isdigit() and isinstance(value, dict) and 'stage' in value for key, value in data.items()):
				row['active_stage_functions'] = data
		rows.append(row)
	print(json.dumps(dict(UTC_ns=time.time_ns(), receipts=rows), indent=2))


def authenticated_inputs(args):
	manifest = json.loads(args.inputs.read_text())
	inputs = manifest.get('original', manifest.get('inputs', manifest))
	assert inputs and all(sha(path) == digest and Path(path).stat().st_mode & 0o222 == 0 for path, digest in inputs.items())
	if args.scope == 'original':
		from run import BASE, population, git
		expected = {row['path']:row['baseline_sha256'] for row in population()['files']}
		actual = {path.split('/original-inputs/', 1)[1]:digest for path, digest in inputs.items()}
		assert len(actual) == len(inputs) and actual == expected, 'original full source closure differs'
		assert all(__import__('hashlib').sha256(git('show', BASE+':'+path)).hexdigest() == digest for path, digest in actual.items())
	if args.scope == 'current':
		from run import population, git
		assert manifest['format'] == 'astra-current-inputs/1'
		revision = manifest['revision']; assert git('rev-parse', '--verify', revision).decode().strip() == revision
		expected = {name for name in git('ls-tree', '-r', '--name-only', revision, 'compiler').decode().splitlines() if name.endswith('.astra')}
		expected.update(row['path'] for row in population()['files'] if row['path'].startswith('lib/astra/'))
		actual = {path.split('/source-inputs/', 1)[1]:digest for path, digest in inputs.items()}
		assert len(actual) == len(inputs) and set(actual) == expected, 'current full source closure differs'
		assert all(__import__('hashlib').sha256(git('show', revision+':'+path)).hexdigest() == digest for path, digest in actual.items())
	return inputs


def source_scope(args):
	inputs = authenticated_inputs(args)
	print(json.dumps(dict(status='VALIDATED_SOURCE_SCOPE', scope=args.scope, input_count=len(inputs), manifest_sha256=sha(args.inputs), full_original_native_credit=0), indent=2))


def probe(args):
	native_timeout = getattr(args, 'native_timeout_seconds', 7200)
	assert native_timeout > 0, 'Explicit native timeout must be positive'
	identity = json.loads(args.component.with_suffix('.identity.json').read_text())
	assert sha(args.component) == identity['sha256']
	authenticate(identity['identity'])
	inputs = authenticated_inputs(args)
	tools = dict(identity['identity']['tools']); tools[str(args.component)] = sha(args.component)
	for name in ('opt', 'llc', 'readelf'):
		path = Path(shutil.which(name)).resolve(); tools[str(path)] = sha(path)
	producer = [str(args.component), '--native-module', '{work}/module.ll', *inputs]
	if args.core_map:
		producer = [sys.executable, '-B', str(Path(__file__).with_name('native-profile.py')), '--host', str(args.component), '--core-map', str(args.core_map), '--profile-dir', '{runtime}/stages', '--timeout-seconds', str(native_timeout), '--', '--native-module', '{work}/module.ll', *inputs]
		inputs = {**inputs, str(args.core_map):sha(args.core_map), str(Path(__file__).with_name('native-profile.py')):sha(Path(__file__).with_name('native-profile.py'))}
	items = [dict(id='native', argv=producer, inputs=inputs, tools=tools, environment=identity['identity']['environment'], cache='fresh', artifacts={'raw':'{work}/module.ll'}, sentinels={'module.ll':'Complete compiler refusal destination sentinel\n'}, expected_exit=0, timeout_seconds=native_timeout+(30 if args.core_map else 0), estimated_RSS_bytes=2*1024**3, required_stdout=['RECOVER_SSA_VALID', 'RECOVER_LLVM_WRITTEN'])]
	def step(name, argv, needs, artifacts=None, required=None):
		items.append(dict(id=name, argv=argv, needs=needs, artifacts=artifacts or {}, required_stdout=required or [], tools=tools, inputs={}, cache='fresh', expected_exit=0, timeout_seconds=7200, estimated_RSS_bytes=2*1024**3))
	step('verify-raw', ['opt', '-passes=verify', '-disable-output', '{artifact:native:raw}'], ['native'])
	for mode in ('O0', 'O2'):
		step(mode+'-optimize', ['opt', '-passes=default<'+mode+'>', '-S', '{artifact:native:raw}', '-o', '{work}/optimized.ll'], ['native', 'verify-raw'], {'optimized':'{work}/optimized.ll'})
		step(mode+'-verify', ['opt', '-passes=verify', '-disable-output', '{artifact:'+mode+'-optimize:optimized}'], [mode+'-optimize'])
		step(mode+'-object', ['llc', '-filetype=obj', '-'+mode, '{artifact:'+mode+'-optimize:optimized}', '-o', '{work}/module.o'], [mode+'-optimize', mode+'-verify'], {'object':'{work}/module.o'})
		step(mode+'-ELF', ['readelf', '-h', '{artifact:'+mode+'-object:object}'], [mode+'-object'], required=['ELF64', 'REL (Relocatable file)', 'X86-64'])
	result = run_jobs(dict(format='astra-native-jobs/1', jobs=items), args.runtime_root/('native-probe-'+args.version), args.build_root/('native-probe-'+args.version), args.runtime_root/'artifact-cache', jobs=4, max_jobs=8, reserve_bytes=8*1024**3, reuse=False)
	write(args.runtime_root/('native-probe-'+args.version)/'source-scope.json', dict(scope=args.scope, component_sha256=identity['sha256'], input_manifest_sha256=sha(args.inputs), input_count=len(inputs)-(2 if args.core_map else 0), object_profiles=['O0', 'O2'], native_timeout_seconds=native_timeout, full_original_native_credit=0, limitation='Actual source emission/LLVM/object evidence; independent ABI/linked usage/memory/regression/delivery qualification remains separate.'))
	assert not result['failed_jobs'], result['failed_jobs']


def cycle(args):
	from concurrent.futures import ThreadPoolExecutor
	import importlib.util
	request = leaf(args, 'development-cycle')
	plan = json.loads(args.identity.read_text())
	selection_reason = 'Explicit primary plan; no applicable measured alternative supplied'
	if args.selection and args.alternate_identity:
		module_spec = importlib.util.spec_from_file_location('compiler26_cost_context', Path(__file__).with_name('iteration-benchmark.py'))
		module = importlib.util.module_from_spec(module_spec); module_spec.loader.exec_module(module)
		selection = json.loads(args.selection.read_text()); alternative = json.loads(args.alternate_identity.read_text())
		primary_context = fingerprint(module.context(expected_product_identity(plan), Path(plan['argv'][-1])))
		alternate_context = fingerprint(module.context(expected_product_identity(alternative), Path(alternative['argv'][-1])))
		if primary_context == alternate_context == selection['context_sha256']:
			if alternative['argv'][1] == '-'+selection['selected_profile']:
				args.identity = args.alternate_identity; plan = alternative
			selection_reason = 'Matched measured build-plus-diagnostic context'
		else:
			selection_reason = 'Measurement belongs to another source/tool context; preserving the explicit primary plan'
	write(request/'selection.json', dict(identity=str(args.identity), selected_host_profile=plan['argv'][1], reason=selection_reason))
	args.component = Path(plan['argv'][-1])
	if args.core_map:
		compile_plan(args)
	else:
		def core_map():
			sources = [value for value in plan['argv'] if value.endswith('.astra')]
			key = fingerprint(dict(compiler=sha(plan['argv'][0]), sources=[(path, sha(path)) for path in sources], environment=plan['environment']))
			parent = args.runtime_root/'core-map-cache'; parent.mkdir(exist_ok=True)
			output = parent/key
			with (parent/(key+'.lock')).open('a') as lock:
				fcntl.flock(lock, fcntl.LOCK_EX)
				if output.exists():
					previous = json.loads((output/'result.json').read_text())
					assert previous['exit'] == 0 and sha(output/'stdout') == previous['stdout_sha256']
				else:
					result = execute([plan['argv'][0], '--dump-core', *sources], output, timeout=600, env=environment(plan['environment']))
					assert result['status'] == 'EXPECTED_OUTCOME'
			return output/'stdout'
		with ThreadPoolExecutor(max_workers=2) as pool:
			compiled = pool.submit(compile_plan, args); mapping = pool.submit(core_map)
			compiled.result(); args.core_map = mapping.result()
	try:
		probe(args)
	except Exception as error:
		write(request/'result.json', dict(status='DEVELOPMENT_PROBE_REFUSED', error=repr(error), component=str(args.component), component_sha256=sha(args.component), scope=args.scope, probe_result=str(args.runtime_root/('native-probe-'+args.version)/'result.json'), full_original_native_credit=0))
		raise
	write(request/'result.json', dict(status='DEVELOPMENT_OBJECTS_OBSERVED', component=str(args.component), component_sha256=sha(args.component), core_map=str(args.core_map), scope=args.scope, full_original_native_credit=0, limitation='One authenticated development host and both object optimization profiles for the stated inputs. Final normal O0/O2 qualification, current source, representative linkage, independent audit and delivery remain separate.'))


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	p.add_argument('--environment-restored', action='store_true', help=argparse.SUPPRESS)
	subs = p.add_subparsers(dest='command', required=True)
	def common(command):
		command.add_argument('--runtime-root', type=Path, required=True)
		command.add_argument('--version', required=True)
	def pool(command):
		common(command); command.add_argument('--build-root', type=Path, required=True)
		command.add_argument('--jobs', type=int, default=4)
		command.add_argument('--max-jobs', type=int, default=8)
		command.add_argument('--reserve-GiB', type=int, default=8)
	c = subs.add_parser('compile'); common(c)
	c.add_argument('--identity', type=Path, required=True); c.add_argument('--profile', action='store_true')
	c.add_argument('--join-result', type=Path); c.add_argument('--join-running', type=Path)
	c.add_argument('--timeout-seconds', type=int, default=7200); c.set_defaults(run=compile_plan)
	c = subs.add_parser('profile'); common(c)
	c.add_argument('--identity', type=Path, required=True); c.add_argument('--expected-exit', type=int, default=0)
	c.add_argument('--timeout-seconds', type=int, default=7200); c.set_defaults(run=profile_command)
	c = subs.add_parser('jobs'); pool(c)
	c.add_argument('--spec', type=Path, required=True); c.add_argument('--reuse', action='store_true'); c.set_defaults(run=jobs)
	c = subs.add_parser('qualify'); pool(c)
	c.add_argument('--component', type=Path, required=True); c.add_argument('--mode', choices=('O0', 'O2'), required=True)
	c.add_argument('--build-version', required=True); c.add_argument('--focus', action='append'); c.set_defaults(run=qualification)
	c = subs.add_parser('status'); c.add_argument('--receipt', type=Path, action='append', required=True); c.set_defaults(run=status)
	c = subs.add_parser('scope'); c.add_argument('--inputs', type=Path, required=True)
	c.add_argument('--scope', choices=('original', 'current', 'focused'), required=True); c.set_defaults(run=source_scope)
	c = subs.add_parser('probe'); common(c); c.add_argument('--build-root', type=Path, required=True)
	c.add_argument('--component', type=Path, required=True); c.add_argument('--inputs', type=Path, required=True)
	c.add_argument('--core-map', type=Path); c.add_argument('--scope', choices=('original', 'current', 'focused'), required=True); c.set_defaults(run=probe)
	c.add_argument('--native-timeout-seconds', type=int, default=7200, help='Bounded source-to-LLVM budget; set explicitly for demonstrated long O0 runs')
	c = subs.add_parser('cycle'); common(c); c.add_argument('--build-root', type=Path, required=True)
	c.add_argument('--identity', type=Path, required=True); c.add_argument('--inputs', type=Path, required=True)
	c.add_argument('--scope', choices=('original', 'current', 'focused'), default='original')
	c.add_argument('--core-map', type=Path); c.add_argument('--profile', action='store_true')
	c.add_argument('--selection', type=Path); c.add_argument('--alternate-identity', type=Path)
	c.add_argument('--join-result', type=Path); c.add_argument('--join-running', type=Path)
	c.add_argument('--timeout-seconds', type=int, default=7200); c.set_defaults(run=cycle)
	c.add_argument('--native-timeout-seconds', type=int, default=7200, help='Independent source-to-LLVM budget after host construction')
	args = p.parse_args()
	if args.capsule_prefix and not args.inside_capsule:
		assert args.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		prefix = json.loads(args.capsule_prefix.read_text())
		assert isinstance(prefix, list) and all(isinstance(item, str) for item in prefix)
		command = [*prefix, '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]
		raise SystemExit(subprocess.call(command))
	if args.command in ('compile', 'profile', 'qualify', 'probe', 'cycle'):
		path = args.component.with_suffix('.identity.json') if args.command in ('qualify', 'probe') else args.identity
		record = json.loads(path.read_text())
		if args.command in ('qualify', 'probe'):
			record = record['identity']
		contract = dict(record['environment']); contract['CCACHE_DISABLE'] = record.get('CCACHE_DISABLE', '1')
		changed = [key for key, value in contract.items() if os.environ.get(key) != value]
		if changed and not args.environment_restored:
			print('Restoring recorded child environment:', ','.join(changed), flush=True)
			child_environment = environment(contract)
			raise SystemExit(subprocess.call([sys.executable, '-B', str(Path(__file__).resolve()), '--environment-restored', *sys.argv[1:]], env=child_environment))
	args.run(args)


if __name__ == '__main__':
	main()
