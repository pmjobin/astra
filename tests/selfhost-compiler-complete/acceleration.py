#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measured, identity-bound execution for compiler development and qualification."""
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from run import ROOT, WORK, sha


def write(path, value):
	temporary = path.with_name(path.name+'.tmp-'+str(os.getpid()))
	temporary.write_text(json.dumps(value, indent=2)+'\n')
	temporary.replace(path)


def fingerprint(value):
	return sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def tool_identity(paths):
	result = {}
	for path in paths:
		path = Path(path).resolve()
		result[str(path)] = sha(path)
		loaded = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
		assert 'not found' not in loaded.stdout, (path, loaded.stdout)
		for word in loaded.stdout.split():
			if word.startswith('/') and Path(word).is_file():
				dependency = Path(word).resolve()
				result[str(dependency)] = sha(dependency)
	return result


def output_path(path, parent):
	path = Path(path)
	assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()), path
	assert not any(p.is_symlink() for p in (path, *path.parents)), path
	return path


def environment(recorded, base=None):
	result = dict(os.environ if base is None else base)
	for key, value in recorded.items():
		if value is None:
			result.pop(key, None)
		else:
			result[key] = value
	return result


def restored_command(recorded, argv):
	# perf adds its own directory to PATH. Restore the entire recorded contract
	# in the sampled child, without changing the parent or any user setting.
	unset = [item for key, value in recorded.items() if value is None for item in ('-u', key)]
	values = [key+'='+value for key, value in recorded.items() if value is not None]
	return ['/usr/bin/env', *unset, *values, *map(str, argv)]


def authenticate(identity):
	for group in ('sources', 'tools'):
		for name, expected in identity[group].items():
			assert Path(name).is_file() and sha(name) == expected, (group, name)
	assert all(os.environ.get(key) == value for key, value in identity['environment'].items())


def expected_product_identity(plan):
	identity = dict(plan)
	identity['sources'] = dict(plan['sources'])
	legacy_recipe = ROOT/'tests/selfhost-compiler-complete/compile-plan.py'
	identity['sources'][str(legacy_recipe)] = sha(legacy_recipe)
	return identity


def cached_product(plan):
	identity = expected_product_identity(plan)
	authenticate(identity)
	target = Path(identity['argv'][-1])
	metadata = target.with_suffix('.identity.json')
	if not target.exists() and not metadata.exists():
		return None
	assert target.is_file() and metadata.is_file(), 'incomplete existing product; use a fresh output leaf'
	actual = json.loads(metadata.read_text())
	assert actual['identity'] == identity, 'existing product has a different identity; use a fresh plan'
	assert sha(target) == actual['sha256'], 'existing product bytes changed; preserve it and use a fresh output leaf'
	return dict(path=str(target), sha256=actual['sha256'], identity_sha256=sha(metadata))


def time_metrics(path):
	text = path.read_text()
	fields = {}
	for key, label in [('user_seconds', 'User time (seconds)'), ('system_seconds', 'System time (seconds)'), ('peak_RSS_KiB', 'Maximum resident set size (kbytes)'), ('exit_status', 'Exit status')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)', text)
		if match:
			fields[key] = float(match[1]) if 'seconds' in key else int(match[1])
	return fields


def interval_union(intervals):
	end = None
	total = 0.0
	for first, last in sorted(intervals):
		assert first <= last
		if end is None or first >= end:
			total += last-first
		else:
			total += max(0, last-end)
		end = last if end is None else max(end, last)
	return total


def process_sample(pid):
	try:
		text = Path('/proc/'+str(pid)+'/stat').read_text().rsplit(')', 1)[1].split()
		rows = {}
		for entry in Path('/proc').iterdir():
			if not entry.name.isdigit():
				continue
			try:
				fields = (entry/'stat').read_text().rsplit(')', 1)[1].split()
				rows[int(entry.name)] = fields
			except (FileNotFoundError, ProcessLookupError, PermissionError):
				pass
		family = {pid}; before = set()
		while before != family:
			before = set(family)
			family.update(child for child, fields in rows.items() if int(fields[1]) in family)
		cpu = 0.0; rss = 0; active = []
		for child in family:
			if child not in rows:
				continue
			fields = rows[child]
			cpu += (int(fields[11])+int(fields[12]))/os.sysconf('SC_CLK_TCK')
			rss += int(fields[21])*os.sysconf('SC_PAGE_SIZE')//1024
			if fields[0] == 'R':
				active.append(child)
		return dict(pid=pid, state=text[0], start_ticks=int(text[19]), active_tree_CPU_seconds=cpu, active_tree_RSS_KiB=rss, descendants=len(family)-1, running_pids=sorted(active))
	except (FileNotFoundError, ProcessLookupError, PermissionError):
		return None


def execute(argv, leaf, *, expected=0, timeout=7200, env=None, state=None):
	leaf.mkdir()
	argv = list(map(str, argv))
	start = time.monotonic()
	started = dict(argv=argv, expected_exit=expected, monotonic_start=start, UTC_start_ns=time.time_ns(), instrumentation='GNU time; no compiler verification or work-budget changes')
	write(leaf/'command.json', started)
	with (leaf/'stdout').open('wb') as out, (leaf/'stderr').open('wb') as err:
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/'time'), *argv], stdout=out, stderr=err, cwd=leaf, env=env, start_new_session=True)
		started.update(pid=process.pid, process=process_sample(process.pid))
		write(leaf/'running.json', started)
		timed_out = False
		while True:
			try:
				code = process.wait(timeout=min(1.0, max(0.01, timeout-(time.monotonic()-start))))
				break
			except subprocess.TimeoutExpired:
				if time.monotonic()-start >= timeout:
					timed_out = True
					os.killpg(process.pid, signal.SIGKILL)
					code = process.wait()
					break
				write(leaf/'live.json', dict(elapsed_seconds=time.monotonic()-start, process=process_sample(process.pid), status='RUNNING'))
				if state is not None:
					state()
	end = time.monotonic()
	result = dict(status='EXPECTED_OUTCOME' if not timed_out and code == expected else 'UNEXPECTED_OUTCOME', exit=code, expected_exit=expected, timed_out=timed_out, monotonic_start=start, monotonic_end=end, seconds=end-start, stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'), time_sha256=sha(leaf/'time'), metrics=time_metrics(leaf/'time'), fresh_execution=True, full_original_native_credit=0)
	write(leaf/'result.json', result)
	write(leaf/'live.json', dict(status=result['status'], elapsed_seconds=result['seconds']))
	return result


def available_memory():
	rows = Path('/proc/meminfo').read_text().splitlines()
	return next(int(row.split()[1])*1024 for row in rows if row.startswith('MemAvailable:'))


def run_jobs(spec, runtime, build, cache, *, jobs=4, max_jobs=8, reserve_bytes=8*1024**3, reuse=False):
	assert spec['format'] == 'astra-native-jobs/1' and 1 <= jobs <= max_jobs <= 8
	runtime = output_path(runtime, WORK/'runtime'); build = output_path(build, WORK/'build'); cache = output_path(cache, WORK/'runtime')
	runtime.mkdir(); build.mkdir(); cache.mkdir(parents=True, exist_ok=True)
	items = spec['jobs']; by_id = {item['id']: item for item in items}
	assert len(by_id) == len(items) and all(re.fullmatch(r'[A-Za-z0-9_-]+', name) for name in by_id)
	assert all(set(item.get('needs', ())) <= set(by_id) for item in items)
	resolved = set()
	while len(resolved) != len(items):
		added = {name for name, item in by_id.items() if name not in resolved and set(item.get('needs', ())) <= resolved}
		assert added, 'dependency cycle'
		resolved.update(added)
	completed = {}; pending = set(by_id); active = {}; limit = jobs
	memory_budget = max(0, available_memory()-reserve_bytes)
	def publish():
		write(runtime/'progress.json', dict(status='RUNNING', total=len(items), completed=len(completed), active=sorted(active.values()), pending=sorted(pending), worker_limit=limit, outcomes=completed))
	def perform(item):
		name = item['id']; dependencies = {key:completed[key] for key in item.get('needs', ())}
		def expand(value, work):
			value = str(value).replace('{work}', str(work)).replace('{runtime}', str(runtime/name))
			for dep, result in dependencies.items():
				for label, artifact in result['artifacts'].items():
					value = value.replace('{artifact:'+dep+':'+label+'}', artifact['path'])
			return value
		inputs = dict(item.get('inputs', {})); tools = dict(item['tools'])
		for dependency in dependencies.values():
			inputs.update({value['path']:value['sha256'] for value in dependency['artifacts'].values()})
		assert tools and all(Path(p).is_file() and sha(p) == h for group in (inputs, tools) for p, h in group.items()), name
		recorded = item.get('environment', {})
		effective_environment = environment(recorded)
		key_data = dict(argv=item['argv'], inputs=inputs, tools=tools, runner_sha256=sha(__file__), environment_sha256=fingerprint(effective_environment), expected_exit=item.get('expected_exit', 0), artifacts=item.get('artifacts', {}), sentinels=item.get('sentinels', {}), required_stdout=item.get('required_stdout', []), dependencies={dep:{label:artifact['sha256'] for label, artifact in row['artifacts'].items()} for dep, row in dependencies.items()})
		key = fingerprint(key_data); pointer = cache/(key+'.json')
		can_reuse = reuse and item.get('cache') == 'artifact'
		if can_reuse and pointer.exists():
			prior = json.loads(pointer.read_text()); assert prior['key_data'] == key_data
			assert prior['artifacts'] and all(Path(p['path']).is_file() and sha(p['path']) == p['sha256'] for p in prior['artifacts'].values()), 'cached artifact changed; preserve it and investigate'
			assert Path(prior['receipt']).is_file() and sha(prior['receipt']) == prior['receipt_sha256']
			return dict(id=name, status='ARTIFACT_REUSED', fresh_execution=False, key=key, artifacts=prior['artifacts'], original_receipt=prior['receipt'], metrics=prior['metrics'])
		work = build/(name+'-'+key[:12]+'-'+str(time.time_ns())); work.mkdir()
		args = [expand(part, work) for part in item['argv']]
		sentinels = {}
		for relative, text in item.get('sentinels', {}).items():
			path = output_path(work/relative, work); path.write_bytes(text.encode()); sentinels[path] = text.encode()
		result = execute(args, runtime/name, expected=item.get('expected_exit', 0), timeout=item.get('timeout_seconds', 7200), env=effective_environment)
		if result['status'] == 'EXPECTED_OUTCOME':
			assert all(text.encode() in (runtime/name/'stdout').read_bytes() for text in item.get('required_stdout', [])), 'required output witness missing'
			if result['exit'] == 0:
				assert all(path.read_bytes() != data for path, data in sentinels.items()), 'successful producer did not replace its destination sentinel'
			else:
				result['refusal_destination_preserved'] = all(path.read_bytes() == data for path, data in sentinels.items())
				assert result['refusal_destination_preserved'], 'refused producer changed its destination'
		else:
			result['refusal_destination_preserved'] = all(path.read_bytes() == data for path, data in sentinels.items())
			write(runtime/name/'result.json', result)
		assert all(sha(p) == h for group in (inputs, tools) for p, h in group.items()), 'concurrent input mutation'
		artifacts = {}
		if result['status'] == 'EXPECTED_OUTCOME':
			for label, path in item.get('artifacts', {}).items():
				path = output_path(Path(expand(path, work)), build)
				assert path.is_file(), path
				artifacts[label] = dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size)
			if item.get('cache') == 'artifact':
				assert artifacts, 'artifact reuse requires actual declared outputs'
				write(pointer, dict(key_data=key_data, receipt=str(runtime/name/'result.json'), receipt_sha256=sha(runtime/name/'result.json'), artifacts=artifacts, metrics=result['metrics']))
		return dict(id=name, key=key, artifacts=artifacts, **result)
	start = time.monotonic()
	with ThreadPoolExecutor(max_workers=max_jobs) as pool:
		while pending or active:
			changed = True
			while changed:
				changed = False
				for name in sorted(pending):
					needs = set(by_id[name].get('needs', ()))
					if needs <= completed.keys() and any(completed[dep]['status'] not in ('EXPECTED_OUTCOME', 'ARTIFACT_REUSED') for dep in needs):
						completed[name] = dict(id=name, status='DEPENDENCY_FAILED', artifacts={}, fresh_execution=False); pending.remove(name); changed = True
			ready = [name for name in sorted(pending) if set(by_id[name].get('needs', ())) <= completed.keys()]
			for name in ready:
				if len(active) >= limit:
					break
				estimate = by_id[name].get('estimated_RSS_bytes', 6*1024**3)
				assert estimate > 0
				reserved = sum(by_id[other].get('estimated_RSS_bytes', 6*1024**3) for other in active.values())
				if reserved+estimate > memory_budget or available_memory() < reserve_bytes+estimate:
					continue
				pending.remove(name); future = pool.submit(perform, by_id[name]); active[future] = name
			publish()
			if not active:
				assert not pending, 'memory reserve prevents scheduling; no checks were bypassed'
				break
			done, _ = wait(active, timeout=1, return_when=FIRST_COMPLETED)
			for future in done:
				name = active.pop(future)
				try:
					completed[name] = future.result()
				except Exception as error:
					completed[name] = dict(id=name, status='HARNESS_FAILURE', error=repr(error), artifacts={}, fresh_execution=False)
				if limit < max_jobs and completed[name]['status'] in ('EXPECTED_OUTCOME', 'ARTIFACT_REUSED'):
					limit += 1
	intervals = [(row['monotonic_start'], row['monotonic_end']) for row in completed.values() if row.get('fresh_execution') and 'monotonic_start' in row]
	failed = sorted(name for name, row in completed.items() if row['status'] not in ('EXPECTED_OUTCOME', 'ARTIFACT_REUSED'))
	result = dict(format='astra-native-jobs-result/1', status='JOB_OUTCOMES_MATCHED' if not failed else 'JOB_FAILURES', jobs=completed, failed_jobs=failed, elapsed_seconds=time.monotonic()-start, execution_interval_union_seconds=interval_union(intervals), summed_process_seconds=sum(last-first for first, last in intervals), cold_execution_count=sum(row.get('fresh_execution', False) for row in completed.values()), artifact_reuse_count=sum(row['status'] == 'ARTIFACT_REUSED' for row in completed.values()), full_original_native_credit=0)
	write(runtime/'result.json', result); write(runtime/'progress.json', result)
	return result
