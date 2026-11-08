#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay the complete retained recipe set using explicit read-only prior inputs."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import state
from state import ROOT, read, sha, bounded_run


class RuntimeInputs:
	def __init__(self, current):
		self.current = current
		self.prior = current.parent/'effects25-r5'

	def __fspath__(self):
		return str(self.current)

	def __truediv__(self, part):
		name = Path(part)
		first = name.parts[0]
		if first == 'r4-history' or first.startswith(('original-before-', 'inherited-baseline-')):
			return self.prior/name
		return self.current/name

	def __getattr__(self, name):
		return getattr(self.current, name)


def install_inputs():
	previous = state.load_module
	def load(name, path):
		module = previous(name, path)
		if Path(path) == ROOT/'tests/selfhost-effects/recover-build.py':
			module.RUNTIME = RuntimeInputs(module.RUNTIME)
		return module
	state.load_module = load
	return load


def main():
	load = install_inputs()
	if len(sys.argv) > 2 and sys.argv[1] == '--recipe':
		name = sys.argv[2]
		assert name.startswith('recover-') and '/' not in name and '.' not in name
		sys.argv = [sys.argv[0], *sys.argv[3:]]
		module = load('resume_retained_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		if hasattr(module, 'main'):
			module.main()
		else:
			runner = load('resume_retained_corpus', ROOT/'tests/selfhost-effects/recover-qualify.py')
			runner.expanded_corpus = module.corpus
			sys.argv += ['--expanded']
			runner.main()
		return
	p = argparse.ArgumentParser()
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--job', action='append')
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.component.with_suffix('.identity.json'))
	assert a.component.name == 'astra-llvm-'+a.mode and sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load('resume_retained_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('resume-retained-'+a.version+'-'+a.mode)
	leaf.mkdir()
	jobs = [
		('recover-r5-inherited', a.version, []),
		('recover-r5-cohorts', a.version, []),
		('recover-qualify', a.version+'scalar', ['--expanded']),
		('recover-record-qualify', a.version+'record', []),
		('recover-owned-qualify', a.version+'owned', []),
		('recover-error-owned-qualify', a.version+'errors', []),
		('recover-loop-qualify', a.version+'loops', []),
		('recover-r3-qualify', a.version+'literal', []),
		('recover-r3-domain-qualify', a.version+'domain', []),
		('recover-adversarial', a.version, []),
		('recover-owner-adversarial', a.version, []),
		('recover-loop-adversarial', a.version, []),
		('recover-r3-adversarial', a.version, []),
		('recover-r3-domain-adversarial', a.version, []),
		('recover-class-policy', a.version, []),
		('recover-r4-policy', a.version, []),
		('recover-null-guard', a.version, []),
		('recover-r3-receiver-guard', a.version, []),
		('recover-r3-float-probe', a.version, []),
		('recover-success-probe', a.version, []),
		('recover-abi-limit', a.version+a.mode, []),
		('recover-original', a.version, ['--provider-build', str(a.component.parent)]),
		('recover-r3-original-view', a.version, ['--ledger-component', str(a.component)]),
		('recover-frontier', a.version, []),
		('recover-r3-fields', a.version+'fields', []),
		('recover-r3-source-oracles', a.version, []),
		('recover-r3-observe', a.version, ['--native-version', a.version+'literal']),
		('recover-r4-qualify', a.version+'fields', []),
		('recover-r4-adversarial', a.version, []),
		('recover-r4-message', a.version, []),
		('recover-r4-lifetime', a.version, []),
		('recover-r4-guard', a.version, []),
		('recover-r4-loans', a.version, []),
		('recover-r4-generic-proof', a.version, []),
		('recover-r4-original-view', a.version, ['--ledger-component', str(a.component)]),
		('recover-r4-source-policy', a.version, ['--original-version', a.version, '--view-version', a.version, '--minimal-view-version', a.version]),
		('recover-r4-layout', a.version, ['--provider-build', str(a.component.parent)]),
		('recover-r4-extra-policy', a.version, []),
		('recover-r5-prefix', a.version+'prefix', []),
		('recover-r5-prefix-negative', a.version, []),
		('recover-r5-prefix-literals', a.version, []),
	]
	assert len(jobs) == 41
	if a.job:
		assert set(a.job) <= {name for name, _, _ in jobs}
	commands = []
	env = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS'):
		env.pop(key, None)
	for name, version, extra in jobs:
		if a.job and name not in a.job:
			continue
		argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r5-resume.py', 'recover-resume-retained', '--recipe', name, '--version', version]
		if name != 'recover-abi-limit':
			argv += ['--mode', a.mode]
		if name not in ('recover-r3-observe', 'recover-r3-source-oracles', 'recover-r4-layout', 'recover-r4-extra-policy'):
			argv += ['--component', a.component]
		argv += extra
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=ROOT, env=env, capture_output=True, timeout=2400)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, version=version, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(a.mode, name, r.returncode, flush=True)
	failed = [row['name'] for row in commands if row['exit'] != 0]
	(leaf/'result.json').write_text(json.dumps(dict(status='RETAINED_RECIPES_COMPLETED' if not failed else 'RETAINED_RECIPES_PARTIAL', profile=a.mode, component_sha256=sha(a.component), selected_jobs=a.job, executed_jobs=len(commands), full_recipe_population=len(jobs), failed_jobs=failed, read_only_inputs=dict(r4_history=str(paths.RUNTIME.prior/'r4-history'), original_attempts=str(paths.RUNTIME.prior), relocated_predecessor_baseline=str(paths.RUNTIME.prior)), limitation='The unchanged 41-recipe R5 population extends the original 39 recipes. Read-only historical inputs are explicitly routed; every output and command receipt is new. A filter or passing recipes does not establish milestone completion. Original execution, all retained source identities, physical mutations and full gates require separate evidence.'), indent=2)+'\n')
	if failed:
		raise SystemExit(1)


if __name__ == '__main__':
	main()
