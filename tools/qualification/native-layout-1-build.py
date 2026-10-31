#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Incrementally rebuild the layout repair's source/dependency closure in place.

Use the verified existing Meson tree. Keep unchanged products and prior private
files; retire only intermediate files created by a successful helper rebuild.
This is a task recipe, not a process supervisor or a replacement test runner.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--base', required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--jobs', type=int, default=8)
	p.add_argument('--resume', action='store_true')
	a = p.parse_args()
	build, runtime = a.build.resolve(), a.runtime.resolve()
	assert not build.is_relative_to(ROOT) and not runtime.is_relative_to(ROOT)
	assert 1 <= a.jobs <= 8 and os.environ.get('CCACHE_DISABLE') == '1'
	runtime.mkdir(parents=True, exist_ok=True)
	check = lambda args: subprocess.check_output(args, cwd=ROOT, text=True)
	assert Path(json.loads(check(['meson', 'introspect', str(build), '--buildsystem-files']))[0]).resolve() == ROOT/'meson.build'
	changed = {str((ROOT/n).resolve()) for n in check(['git', 'diff', '--name-only', a.base, 'HEAD']).splitlines()}
	targets = [t for t in json.loads(check(['meson', 'introspect', str(build), '--targets'])) if t['type'] != 'run']
	assert len({t['name'] for t in targets}) == len(targets)
	def inputs(t):
		return {str(Path(n).resolve()) for g in t['target_sources'] for n in g.get('sources', [])+g.get('generated_sources', [])}
	selected = {t['id'] for t in targets if inputs(t) & changed}
	while True:
		closure = selected | {t['id'] for t in targets if set(t['depends']) & selected}
		if closure == selected:
			break
		selected = closure
	products = [Path(n) for t in targets for n in t['filename']]
	sources = {n: digest(Path(n)) for t in targets for n in inputs(t) if Path(n).is_file()}
	config = {n: digest(build/n) for n in ('build.ninja', 'meson-private/coredata.dat')}
	receipt = runtime/'dependency-build.json'
	model = dict(base=a.base, head=check(['git', 'rev-parse', 'HEAD']).strip(), jobs=a.jobs, sources=sources, config=config,
		selected=[t['name'] for t in targets if t['id'] in selected], initial_products={}, completed=[], started=time.time())
	if a.resume:
		previous = json.loads(receipt.read_text())
		assert all(model[n] == previous[n] for n in ('base', 'head', 'jobs', 'sources', 'config', 'selected'))
		model = previous
		assert all(row['exit'] == 0 for row in model['completed'])
	else:
		assert not receipt.exists()
		model['initial_products'] = {str(n): digest(n) for n in products if n.is_file()}
		receipt.write_text(json.dumps(model, indent=2)+'\n')
	done = {row['target'] for row in model['completed']}
	for target in targets:
		if target['id'] not in selected or target['name'] in done:
			continue
		assert all(digest(Path(n)) == h for n, h in sources.items()), 'compiled input changed'
		assert shutil.disk_usage(build).free >= 20*1024**3
		# This existing build has the predecessor's explicit 16 GiB local
		# allowance; this recipe neither changes nor enlarges that allowance.
		used = int(check(['du', '-sb', str(build.parent)]).split()[0])
		assert used < 16*1024**3, 'existing build storage allowance reached'
		private = Path(target['filename'][0]+'.p')
		before = {n for n in private.rglob('*') if n.is_file()} if private.is_dir() else set()
		command = ['meson', 'compile', '-C', str(build), '-j', str(a.jobs), target['name']]
		log = runtime/(target['name']+'.log')
		start = time.monotonic()
		with log.open('w') as f:
			result = subprocess.run(command, stdout=f, stderr=subprocess.STDOUT)
		row = dict(target=target['name'], command=command, seconds=time.monotonic()-start, exit=result.returncode, log_sha256=digest(log), retired_bytes=0)
		model['completed'].append(row)
		receipt.write_text(json.dumps(model, indent=2)+'\n')
		assert result.returncode == 0, str(log)
		row['products'] = {n: digest(Path(n)) for n in target['filename']}
		if target['name'] != 'astrac' and target['type'] == 'executable' and private.is_dir():
			assert private.is_relative_to(build) and not private.is_symlink()
			for n in private.rglob('*'):
				if n.is_file() and n not in before:
					row['retired_bytes'] += n.stat().st_size
					n.unlink()
					# Preserve the original directory and all pre-existing files.
		print('built', len(model['completed']), '/', len(selected), target['name'], '%.2fs' % row['seconds'], flush=True)
		receipt.write_text(json.dumps(model, indent=2)+'\n')
	assert all(digest(Path(n)) == h for n, h in sources.items())
	changed_products = {n for row in model['completed'] for n in row['products']}
	assert all(digest(Path(n)) == h for n, h in model['initial_products'].items() if n not in changed_products), 'unaffected product changed'
	model.update(finished=time.time(), status='BUILT_NOT_TESTED')
	receipt.write_text(json.dumps(model, indent=2)+'\n')


if __name__ == '__main__':
	main()
