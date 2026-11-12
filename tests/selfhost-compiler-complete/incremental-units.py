#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Incremental native-unit compilation using C0's exact existing unit interface."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha
from acceleration import output_path, run_jobs, write, tool_identity


def make_jobs(spec, compiler):
	assert spec['format'] == 'astra-native-units/1' and sha(compiler) == C0_SHA256
	units = spec['units']; known = {unit['id']:unit for unit in units}
	assert len(known) == len(units)
	for unit in units:
		assert unit['mode'] in ('O0', 'O2')
		assert bool(unit.get('namespace')) == bool(unit.get('exports'))
		assert set(unit.get('needs', ())) <= set(known)
	resolved = {}; pending = dict(known)
	step = Path(__file__).with_name('native-unit-step.py')
	tool_paths = [compiler, Path(sys.executable).resolve(), *[Path(shutil.which(name)).resolve() for name in ('cc', 'gcc', 'as', 'ld')]]
	tools = tool_identity(tool_paths)
	while pending:
		ready = [name for name, unit in pending.items() if set(unit.get('needs', ())) <= resolved.keys()]
		assert ready, 'native-unit dependency cycle'
		for name in ready:
			unit = pending.pop(name); closure = set(unit.get('needs', ()))
			for dep in tuple(closure):
				closure.update(resolved[dep]['closure'])
			assert all(known[dep].get('namespace') for dep in closure), 'executables cannot be imported as units'
			dependencies = {}
			for dep in sorted(closure):
				# Each dependency job publishes its complete unchanged adjacent
				# closure. Native-module import validation is never skipped.
				provider = next(direct for direct in unit.get('needs', ()) if dep == direct or dep in resolved[direct]['closure'])
				for suffix in ('asti', 'o'):
					dependencies[dep+'.'+suffix] = '{artifact:'+provider+':'+dep+'_'+suffix+'}'
			request = dict(compiler=str(compiler), id=name, work='{work}', mode=unit['mode'], namespace=unit.get('namespace'), exports=unit.get('exports', []), imports=unit.get('needs', []), sources=unit['sources'], link_objects=unit.get('link_objects', []), dependencies=dependencies)
			artifacts = {dep+'_'+suffix:'{work}/'+dep+'.'+suffix for dep in closure for suffix in ('asti', 'o')}
			if unit.get('namespace'):
				artifacts.update({name+'_asti':'{work}/'+name+'.asti', name+'_o':'{work}/'+name+'.o'})
			else:
				artifacts[name+'_elf'] = '{work}/'+name+'.elf'
			inputs = {path:sha(path) for path in [*unit['sources'], *unit.get('link_objects', []), str(step), str(Path(__file__))]}
			resolved[name] = dict(closure=sorted(closure), job=dict(id=name, argv=[sys.executable, '-B', str(step), json.dumps(request, sort_keys=True)], needs=unit.get('needs', []), tools=tools, inputs=inputs, artifacts=artifacts, cache='artifact', expected_exit=0, timeout_seconds=unit.get('timeout_seconds', 7200), estimated_RSS_bytes=unit.get('estimated_RSS_bytes', 3*1024**3), environment={'CCACHE_DISABLE':'1', 'LD_PRELOAD':None}))
	return dict(format='astra-native-jobs/1', jobs=[resolved[unit['id']]['job'] for unit in units], semantics='Existing C0 module/interface/object/ABI validation; changed dependencies rebuild their consuming closure, independent units remain reusable', full_original_native_credit=0)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--spec', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--jobs', type=int, default=4)
	p.add_argument('--max-jobs', type=int, default=8)
	p.add_argument('--reserve-GiB', type=int, default=8)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	args = p.parse_args()
	assert args.version.isalnum()
	if args.capsule_prefix and not args.inside_capsule:
		assert args.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(args.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	runtime = output_path(args.runtime_root/('incremental-units-'+args.version), WORK/'runtime')
	build = output_path(args.build_root/('incremental-units-'+args.version), WORK/'build')
	# Authenticate before compiling any independent unit.
	tool_receipt = args.runtime_root/('incremental-toolchain-'+args.version+'.json')
	assert not tool_receipt.exists()
	subprocess.run([sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', args.compiler, '--receipt', tool_receipt], check=True)
	spec = make_jobs(json.loads(args.spec.read_text()), args.compiler)
	result = run_jobs(spec, runtime, build, args.runtime_root/'native-unit-cache', jobs=args.jobs, max_jobs=args.max_jobs, reserve_bytes=args.reserve_GiB*1024**3, reuse=True)
	write(runtime/'plan.json', spec)
	print(result['status'], 'compiled', result['cold_execution_count'], 'reused', result['artifact_reuse_count'], flush=True)
	assert not result['failed_jobs'], result['failed_jobs']


if __name__ == '__main__':
	main()
