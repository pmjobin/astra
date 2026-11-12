#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Choose a development profile from matched build plus diagnostic costs."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from run import ROOT, WORK, sha
from acceleration import fingerprint, run_jobs, write


def context(identity, host):
	# Only the intentional host optimization level and its private output/provider
	# directory differ. Source bytes, source order, tools, flags and environment
	# must otherwise agree. This comparison normalization is never a cache key.
	def name(value):
		return str(value).replace(str(host.parent), '<HOST_DIR>')
	argv = [name(value) for value in identity['argv']]
	argv[1] = '<HOST_OPTIMIZATION>'
	argv[-1] = '<HOST_OUTPUT>'
	return dict(argv=argv, sources={name(path):digest for path, digest in identity['sources'].items()}, tools=identity['tools'], environment=identity['environment'], CCACHE_DISABLE=identity['CCACHE_DISABLE'])


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--O0', type=Path, required=True)
	p.add_argument('--O2', type=Path, required=True)
	p.add_argument('--cold-O0', type=Path, required=True)
	p.add_argument('--cold-O2', type=Path, required=True)
	p.add_argument('--inputs', type=Path, required=True)
	p.add_argument('--expected-exit', type=int, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	args = p.parse_args()
	assert args.version.isalnum()
	if args.capsule_prefix and not args.inside_capsule:
		assert args.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(args.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	inputs = json.loads(args.inputs.read_text())
	inputs = inputs.get('original', inputs.get('inputs', inputs))
	assert inputs and all(Path(path).is_file() and sha(path) == digest and Path(path).stat().st_mode & 0o222 == 0 for path, digest in inputs.items())
	contexts = []; cold = {}; items = []
	for mode in ('O0', 'O2'):
		host = getattr(args, mode); record_path = host.with_suffix('.identity.json')
		record = json.loads(record_path.read_text()); identity = record['identity']
		assert sha(host) == record['sha256'] and identity['argv'][1] == '-'+mode
		assert all(sha(path) == digest for group in ('sources', 'tools') for path, digest in identity[group].items())
		contexts.append(context(identity, host))
		cost_path = getattr(args, 'cold_'+mode)
		cost = json.loads(cost_path.read_text())
		assert cost['status'] == 'C0_NORMAL_TEST_HOST_BUILT' and cost['mode'] == mode and cost['exit'] == 0
		step = next(row for row in cost['steps'] if row['label'] == 'cold-'+mode)
		assert step['exit'] == 0 and sha(cost_path.parent/(step['label']+'.time')) == step['time_sha256']
		cold[mode] = dict(seconds=step['seconds'], receipt=str(cost_path), receipt_sha256=sha(cost_path))
		items.append(dict(id=mode, argv=[str(host), '--native-module', '{work}/probe.ll', *inputs], inputs={**inputs, str(record_path):sha(record_path)}, tools={str(host):sha(host)}, environment=identity['environment'], expected_exit=args.expected_exit, timeout_seconds=7200, estimated_RSS_bytes=1024**3, cache='fresh'))
	assert contexts[0] == contexts[1], 'host sources/tools/flags/environments are not comparable; no profile recommendation'
	common = fingerprint(contexts[0])
	result = run_jobs(dict(format='astra-native-jobs/1', jobs=items), args.runtime_root/('iteration-benchmark-'+args.version), args.build_root/('iteration-benchmark-'+args.version), args.runtime_root/'benchmark-cache', jobs=2, max_jobs=2, reserve_bytes=8*1024**3, reuse=False)
	assert not result['failed_jobs'], result['failed_jobs']
	totals = {mode:cold[mode]['seconds']+result['jobs'][mode]['seconds'] for mode in ('O0', 'O2')}
	selection = dict(status='MATCHED_ITERATION_COST_OBSERVED', context_sha256=common, input_manifest_sha256=sha(args.inputs), input_count=len(inputs), cold=cold, diagnostics={mode:dict(seconds=result['jobs'][mode]['seconds'], actual_exit=result['jobs'][mode]['exit'], metrics=result['jobs'][mode]['metrics']) for mode in ('O0', 'O2')}, total_iteration_seconds=totals, selected_profile=min(totals, key=totals.get), sample_count_per_profile=1, full_original_native_credit=0, applicability='Only this exact compiler source/tool/flag context and diagnostic input set. Refusal timings are not compiler acceptance. Repeat when the source context changes; do not apply these costs to another host closure or claim a repeated statistical speedup.')
	write(args.runtime_root/('iteration-benchmark-'+args.version)/'selection.json', selection)
	print(json.dumps(selection, indent=2))


if __name__ == '__main__':
	main()
