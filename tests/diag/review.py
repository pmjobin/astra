# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare independently built compilers and inspect ordinary executable stages."""
from pathlib import Path
import json
import re
import sys

sys.dont_write_bytecode = True
from qualify import ROOT, LIB, HERE, STAGES, COMMANDS, process, run, sha, write_json


def phi_audit(data):
	# Derive predecessors from branches, independently of the compiler graph.
	count = 0
	for function in re.findall(rb'^define [\s\S]*?^}', data, re.M):
		blocks = {}; current = b'entry'; blocks[current] = []
		for line in function.splitlines()[1:]:
			match = re.match(rb'^([-a-zA-Z$._0-9]+):', line)
			if match:
				current = match[1]; blocks.setdefault(current, [])
			else:
				blocks[current].append(line)
		predecessors = {name: set() for name in blocks}
		for name, lines in blocks.items():
			for line in lines:
				if re.match(rb'\s*br ', line):
					for target in re.findall(rb'label %([-a-zA-Z$._0-9]+)', line):
						predecessors.setdefault(target, set()).add(name)
		for name, lines in blocks.items():
			for line in lines:
				if b' = phi ' in line:
					actual = re.findall(rb', %([-a-zA-Z$._0-9]+)\s*\]', line)
					assert len(actual) == len(set(actual)) and set(actual) == predecessors[name], (name, line, predecessors[name])
					count += 1
	return count


def qualify(baseline, candidate, independent, out):
	baseline = baseline.resolve(); candidate = candidate.resolve(); independent = independent.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	old = [(['examples/base/contracts.astra', 'lib/astra/base/order.astra', 'lib/astra/base/classify.astra', 'lib/astra/base/contracts.astra', 'lib/astra/base/clamp.astra'], []), (['tests/args/fixtures/golden.astra'], []), (['tests/text/fixtures/basics.astra'], []), (['examples/base/diagnostics.astra', 'lib/astra/hosted/equality.astra'], [])]
	comparisons = []
	for i, (sources, options) in enumerate(old):
		for stage in STAGES:
			values = [run([build / 'astrac', '--dump-' + stage, *sources, *options], cwd=ROOT) for build in [baseline, candidate, independent]]
			assert values[0] == values[1] == values[2], (i, stage)
			comparisons.append(dict(program=i, stage=stage, sha256=sha(values[0])))
	new_sources = ['tests/diag/fixtures/client.astra', 'tests/diag/fixtures/helper.astra', 'tests/diag/fixtures/wrapper.astra', 'lib/astra/base/diagnostics.astra']
	for stage in STAGES:
		left = run([candidate / 'astrac', '--dump-' + stage, *new_sources], cwd=ROOT)
		right = run([independent / 'astrac', '--dump-' + stage, *new_sources], cwd=ROOT)
		assert left == right, stage
		(out / ('new.' + stage)).write_bytes(left)
	objects = []; ir_comparisons = []; phi = []
	for base in ['qualification/failures', 'runtime/effects', 'runtime/ownership', 'runtime/ownership-output', 'components/components']:
		left = candidate / 'diag-1' / base; right = independent / 'diag-1' / base
		for path in sorted(left.glob('*.o')):
			other = right / path.name; assert path.read_bytes() == other.read_bytes(), path
			objects.append(dict(path=base + '/' + path.name, sha256=sha(path.read_bytes())))
		for path in sorted(left.glob('*.ll')):
			other = right / path.name
			# opt's input ModuleID comment is not executable provenance or data.
			first = re.sub(rb"^; ModuleID = '[^\n]*'\n", b'', path.read_bytes())
			second = re.sub(rb"^; ModuleID = '[^\n]*'\n", b'', other.read_bytes())
			assert first == second, path
			ir_comparisons.append(dict(path=base + '/' + path.name, sha256=sha(first)))
			count = phi_audit(first)
			if count:
				phi.append(dict(path=base + '/' + path.name, phis=count))
	assert phi
	ownership = (candidate / 'diag-1/runtime/ownership/ownership.entry.ll').read_bytes()
	assert b'store ptr null' in ownership and b'astra_host_args_dispose_v0' in ownership
	provider = candidate / 'lib/astra/diagnostics-hosted.o'
	providers = {name: dict(undefined=run(['nm', '-u', candidate / 'lib/astra' / name]).decode(), size=run(['size', '-A', candidate / 'lib/astra' / name]).decode(), sha256=sha((candidate / 'lib/astra' / name).read_bytes())) for name in ['diagnostics-hosted.o', 'diagnostics-trap.o', 'failure-hosted.o', 'failure-trap.o', 'args-posix.o', 'text-posix.o']}
	assert not providers['diagnostics-trap.o']['undefined']
	assert all(name not in providers['diagnostics-hosted.o']['undefined'] for name in ['LLVM', 'g_object', 'g_malloc', 'strlen', 'malloc'])
	for name in ['failure-hosted.o', 'failure-trap.o', 'args-posix.o', 'text-posix.o']:
		assert (baseline / 'lib/astra' / name).read_bytes() == (candidate / 'lib/astra' / name).read_bytes() == (independent / 'lib/astra' / name).read_bytes(), name
	result = dict(old_stage_comparisons=comparisons, new_stage_comparisons=len(STAGES), machine_objects=objects, llvm_comparisons=ir_comparisons, phi_predecessors=phi, ownership_nulling=True, providers=providers)
	write_json(out / 'results.json', result); write_json(out / 'commands.json', COMMANDS)
	print('DIAG-1 independent compiler/stage/object and predecessor review PASS')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(*map(Path, sys.argv[1:]))
