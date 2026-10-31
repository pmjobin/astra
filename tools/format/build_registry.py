#!/usr/bin/env python3
"""Build current registered products in batches; retire only our intermediates.

This recipe is for a fresh task-owned external Meson build, with unchanged
sources throughout. It does not run tests or change Meson settings.
"""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--jobs', type=int, default=8)
	p.add_argument('--batch-size', type=int, default=8, help='products per batch; reduce near the storage ceiling')
	p.add_argument('--min-free-bytes', type=int, required=True, help='free space required before each batch')
	p.add_argument('--max-build-bytes', type=int, required=True, help='maximum size of this task-owned build leaf')
	p.add_argument('--resume', action='store_true')
	p.add_argument('--allow-helper-change', action='append', default=[],
		help='reviewed formatter Python helper change; never a compiled or configuration input')
	a = p.parse_args()
	build, runtime = a.build.resolve(), a.runtime.resolve()
	assert not build.is_relative_to(ROOT) and not runtime.is_relative_to(ROOT)
	assert 1 <= a.jobs <= 16
	assert 1 <= a.batch_size <= 8
	assert os.environ.get('CCACHE_DISABLE') == '1'
	runtime.mkdir(parents=True, exist_ok=True)
	receipt = runtime/'registry-build.json'
	assert receipt.exists() == a.resume, 'Use --resume only for a preserved interrupted build receipt'
	assert Path(json.loads(subprocess.check_output(['meson', 'introspect', str(build), '--buildsystem-files']))[0]).resolve() == ROOT/'meson.build'
	targets = json.loads(subprocess.check_output(['meson', 'introspect', str(build), '--targets']))
	targets = [t for t in targets if t['type'] != 'run']
	assert all(t['type'] in ('executable', 'custom', 'static library') for t in targets)
	assert len({t['name'] for t in targets}) == len(targets)
	commands = subprocess.check_output(['ninja', '-C', str(build), '-t', 'commands', 'astrac'], text=True).splitlines()
	c = [shlex.split(s) for s in commands if ' -c ' in s]
	assert c and all('-DVALA_STRICT_C' in row and '-Werror' in row for row in c)
	assert all('--fatal-warnings' in s for s in commands if s.startswith('valac '))
	names = [os.fsdecode(n) for n in subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).split(b'\0') if n]
	def sources():
		return {n: hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
	initial = sources()
	assert a.min_free_bytes >= 0 and a.max_build_bytes > 0
	limits = dict(min_free_bytes=a.min_free_bytes, max_build_bytes=a.max_build_bytes)
	model = dict(source_commit=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
		sources=initial, targets=len(targets), production_c_commands=len(c), storage_limits=limits, completed=[], started=time.time(), jobs=a.jobs)
	first = 0
	if a.resume:
		previous = json.loads(receipt.read_text())
		assert previous['jobs'] == a.jobs and previous['targets'] == len(targets)
		assert previous['storage_limits'] == limits, 'storage limits changed during continuation'
		changed = {n for n in initial.keys() | previous['sources'].keys() if initial.get(n) != previous['sources'].get(n)}
		assert changed <= set(a.allow_helper_change), 'unreviewed source change during continuation'
		compiled_inputs = {str(Path(n).resolve()) for t in targets for group in t['target_sources']
			for n in group.get('sources', []) + group.get('generated_sources', [])}
		configuration_inputs = {str(Path(n).resolve()) for n in json.loads(subprocess.check_output(['meson', 'introspect', str(build), '--buildsystem-files']))}
		for name in changed:
			assert name.startswith('tools/format/') and name.endswith('.py')
			assert str((ROOT/name).resolve()) not in compiled_inputs | configuration_inputs
			# Meson configuration and generated command graph must predate the
			# original build. We never reuse products across a reconfiguration.
		assert all((build/n).stat().st_mtime <= previous['started'] for n in ('build.ninja', 'meson-private/coredata.dat'))
		assert all(row['exit'] == 0 for row in previous['completed'])
		first = sum(len(row['command']) - 6 for row in previous['completed'])
		assert first <= len(targets)
		assert [n for row in previous['completed'] for n in row['command'][6:]] == [t['name'] for t in targets[:first]]
		for target in targets[:first]:
			assert all(Path(n).is_file() for n in target['filename'])
		model['completed'] = previous['completed']
		model['started'] = previous['started']
		model['continuation_history'] = previous.get('continuation_history', []) + ([previous['continuation']] if 'continuation' in previous else [])
		model['continuation'] = dict(prior_source_commit=previous['source_commit'],
			helper_changes={n: dict(before=previous['sources'][n], after=initial[n]) for n in sorted(changed)},
			proof='No compiled/configuration input changed; original command graph retained')
	model['batch_size'] = a.batch_size
	for start in range(first, len(targets), a.batch_size):
		assert sources() == initial, 'source changed during build'
		assert shutil.disk_usage(build).free >= limits['min_free_bytes'], 'free-space limit'
		used = int(subprocess.check_output(['du', '-sb', str(build)], text=True).split()[0])
		assert used < limits['max_build_bytes'], 'task build storage limit'
		batch = targets[start:start+a.batch_size]
		argv = ['meson', 'compile', '-C', str(build), '-j', str(a.jobs), *[t['name'] for t in batch]]
		log = runtime/(('build-small-%03d.log' if a.batch_size != 8 else 'build-%03d.log') % start)
		begin = time.monotonic()
		with log.open('xb') as stream:
			result = subprocess.run(argv, stdout=stream, stderr=subprocess.STDOUT)
		model['completed'].append(dict(command=argv, exit=result.returncode, seconds=time.monotonic()-begin,
			log=log.name, sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
		receipt.write_text(json.dumps(model, indent=2)+'\n')
		assert result.returncode == 0, 'build failed: ' + str(log)
		for target in batch:
			for product in target['filename']:
				assert Path(product).is_file() and Path(product).is_relative_to(build)
				# Retire only the private intermediates generated by this recipe's
				# just-completed targets. Keep products and the compiler C evidence.
			if target['type'] == 'executable' and target['name'] != 'astrac':
				private = Path(target['filename'][0] + '.p')
				if private.exists():
					assert private.is_dir() and not private.is_symlink() and private.is_relative_to(build)
					shutil.rmtree(private)
		print('built', min(start+a.batch_size, len(targets)), '/', len(targets), flush=True)
	assert sources() == initial
	model.update(finished=time.time(), status='BUILT_NOT_TESTED')
	receipt.write_text(json.dumps(model, indent=2)+'\n')


if __name__ == '__main__':
	main()
