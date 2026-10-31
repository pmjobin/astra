#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build application A with explicit outputs and optional opaque native units."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'build', 'runtime']: parser.add_argument('--' + name, required=True, type=Path)
	parser.add_argument('--optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--facts', choices=['off', 'on'], default='on')
	parser.add_argument('--layout', choices=['native', 'local'], default='native')
	parser.add_argument('--variant', choices=['base', 'renamed', 'state', 'fields', 'helpers', 'third', 'branch', 'escape'], default='base')
	parser.add_argument('--profile', choices=['sequential', 'threaded', 'uring'], default='sequential')
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra',
		help='Public Astra library/provider directory; installed SDK uses PREFIX/share/astra')
	parser.add_argument('--policy', choices=['strict', 'contract'], default='strict')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	library = args.library_root.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='telemetry-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='telemetry-', dir=args.runtime.resolve()))
	profiles = {'sequential': ['main'], 'threaded': ['context', 'worker', 'threaded'], 'uring': ['context', 'io-worker', 'io-cpu', 'io']}
	roles = ['leaf', 'middle', 'kernel', 'reports', 'lifetimes', 'driver', *profiles[args.profile]]
	originals = {name: HERE / ('telemetry-' + name + '.astra') for name in roles}
	libraries = [library / 'numerics' / (name + '.astra') for name in ['fir', 'filters', 'vectors']]
	libraries += [library / 'collections/vector.astra', library / 'base/errors.astra']
	providers, vapis = [], []
	if args.profile == 'threaded':
		libraries += [library / 'async/threaded.astra']
		providers = [library / 'runtime/context-17.c', library / 'async/threaded.c', library / 'platform/text-posix.c']
		vapis = [library / 'memory/contexts.vapi']
	elif args.profile == 'uring':
		assert args.uring_prefix is not None, '--uring-prefix is required for the actual io_uring profile'
		uring_prefix = args.uring_prefix.resolve(strict=True)
		libraries += [library / 'async/payload.astra']
		providers = [library / 'runtime/context-17.c', library / 'async/composed.c', library / 'async/linux.c', library / 'platform/text-posix.c', library / 'platform/args-posix.c']
		vapis = [library / 'memory/contexts.vapi', library / 'async/payload.vapi', library / 'async/composition.vapi']
	inputs = [*originals.values(), *libraries, *providers, *vapis, HERE / 'telemetry-host.c', Path(__file__).resolve()]
	if args.profile == 'uring': inputs += [uring_prefix / 'lib/liburing.a']
	receipt = dict(configuration=dict(layout=args.layout, variant=args.variant, profile=args.profile, policy=args.policy, optimization=args.optimization, application_facts=args.facts, producer_optimization='2', producer_facts='on'),
		compiler=dict(path=str(compiler), sha256=sha(compiler)), inputs={str(p.relative_to(ROOT) if p.is_relative_to(ROOT) else p): sha(p) for p in inputs}, commands=[], products={})
	texts = {name: path.read_text() for name, path in originals.items()}
	metadata_name = 'WindowMetadata'
	if args.variant == 'renamed':
		names = {'WindowMetadata': 'PacketMetadata18', 'WindowAudit18': 'PacketAudit18', 'WindowGain18': 'PacketGain18',
			'WindowStage18': 'PacketStage18', 'WindowFailure18': 'PacketFailure18', 'WindowSummary18': 'PacketSummary18', 'WindowPayload18': 'PacketPayload18'}
		for name, text in texts.items():
			for before, after in names.items(): text = text.replace(before, after)
			texts[name] = text
		metadata_name = names[metadata_name]
	elif args.variant == 'fields':
		before = '\tf64 gain;\n\tf64 bias;\n\tint sequence;'
		assert before in texts['leaf']; texts['leaf'] = texts['leaf'].replace(before, '\tint sequence;\n\tf64 bias;\n\tf64 gain;')
	elif args.variant in ['state', 'escape']:
		before = '\ttelemetry18_validate(sequence, count);'
		addition = '\towned WindowAudit18 extra = new WindowAudit18(sequence, 4);\n'
		if args.variant == 'escape': addition += '\towned WindowAudit18 extra_returned = telemetry18_escape(move extra);\n'
		assert before in texts['kernel']; texts['kernel'] = texts['kernel'].replace(before, addition + before)
		before = '\tif (returned.tag() != sequence'
		selected = 'extra_returned' if args.variant == 'escape' else 'extra'
		texts['kernel'] = texts['kernel'].replace(before, '\tif (' + selected + '.tag() != sequence) { return -1.0; }\n' + before)
	elif args.variant == 'helpers':
		before = 'combine(selected_gain(first, true), selected_gain(second, false))'
		assert before in texts['kernel']; texts['kernel'] = texts['kernel'].replace(before, 'telemetry18_gain_pair(first, second)')
		texts['kernel'] += '\nf64 telemetry18_gain_pair(WindowMetadata first, WindowMetadata second) { return ' + before + '; }\n'
	elif args.variant == 'third':
		before = '\tf64 stage_gain = 0.5;'
		addition = '\tif (sequence % 3 == 0) {\n\t\towned WindowThird18 alternate = new WindowThird18(0);\n\t\tif (alternate.choose(sequence % 2) != stage.choose(sequence % 2)) { return -1.0; }\n\t}\n'
		assert before in texts['kernel']; texts['kernel'] = texts['kernel'].replace(before, addition + before)
		texts['kernel'] += '\nclass WindowThird18 : WindowStage18 { int parity; init(int parity) : base(){this.parity=parity;} override int choose(int input){return input+this.parity;} }\n'
	elif args.variant == 'branch':
		before = '\tf64 factor = combine(selected_gain(first, true), selected_gain(second, false));'
		after = '\tf64 factor = 0.0;\n\tif (sequence % 2 == 0) { factor = combine(selected_gain(first, true), selected_gain(second, false)); }\n\telse { factor = combine(second.scale, first.scale); }'
		assert before in texts['kernel']; texts['kernel'] = texts['kernel'].replace(before, after)
	if args.policy == 'contract':
		for before in ['f64 telemetry18_affine(', 'f64<2> telemetry18_affine_pair(']:
			assert before in texts['kernel']; texts['kernel'] = texts['kernel'].replace(before, '[FloatingPoint(contract="on")]\n' + before)
	sources = {}
	for name, text in texts.items():
		path = runtime / ('telemetry-' + name + '.astra'); path.write_text(text); sources[name] = path
	receipt['rendered_inputs'] = {str(path): sha(path) for path in sources.values()}
	def save(): (runtime / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, facts='on'):
		command = list(map(str, command)); started = time.monotonic()
		p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', ASTRA_TEST_OPTIMIZATIONS=facts, ASTRA_EXPLAIN_OPTIMIZATIONS='1'))
		row = dict(command=command, facts=facts, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, seconds=time.monotonic()-started)
		receipt['commands'].append(row); save(); assert p.returncode == 0 and not p.stderr, row
		return p.stdout
	host = build / 'host.o'
	run(['clang', '-std=c11', '-O2', '-g', '-fno-builtin', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', '-pedantic',
		*(['-DTELEMETRY_EXTRA_AUDIT'] if args.variant in ['state', 'escape'] else []),
		*(['-DTELEMETRY_CONTRACT'] if args.policy == 'contract' else []),
		*(['-DTELEMETRY_WORKERS', '-pthread'] if args.profile == 'threaded' else ['-DTELEMETRY_IO', '-pthread'] if args.profile == 'uring' else []),
		'-I', library / 'runtime', '-c', HERE / 'telemetry-host.c', '-o', host])
	links = ['--link-object', host]
	for provider in providers:
		obj = build / (provider.stem + '.o')
		run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
			*(['-isystem', uring_prefix / 'include'] if args.profile == 'uring' else []), '-c', provider, '-o', obj])
		links += ['--link-object', obj]
	if providers: links += ['--link-library', 'pthread']
	if args.profile == 'uring': links += ['--link-object', uring_prefix / 'lib/liburing.a']
	application = [sources[name] for name in roles if name not in ['leaf', 'middle']]
	arguments = [part for path in vapis for part in ['--vapi', path]]
	imports = []
	if args.layout == 'native':
		for name, module, exports in [
			('leaf', 'TelemetryLeaf18', [metadata_name, 'metadata_gain', 'metadata_bias', 'combine']),
			('middle', 'TelemetryMiddle18', ['selected_gain', 'balanced_scalar']),
		]:
			producer = sources[name]
			interface, obj = build / (name + '.asti'), build / (name + '.o')
			selectors = [part for export in exports for part in ['--native-export', module + '.' + export]]
			run([compiler, '-O2', '-c', producer, '--module', module, *selectors, *imports, '--emit-interface', interface, '-o', obj])
			receipt['products'][name] = dict(interface_sha256=sha(interface), object_sha256=sha(obj), producer_input=str(producer), producer_input_sha256=sha(producer))
			producer.unlink()
			imports += ['--import-module', interface]
			save()
		receipt['producer_input_copies_removed'] = True
	else: application = [sources['leaf'], sources['middle'], *application]
	ssa = build / 'telemetry.ssa'; ssa.write_text(run([compiler, '--dump-ssa', *application, *libraries, *imports, *arguments], args.facts))
	receipt['stack_claims'] = [line for line in ssa.read_text().splitlines() if '(stack-object' in line]
	receipt['exact_claims'] = [line for line in ssa.read_text().splitlines() if '(exact-call' in line]
	receipt['shared_claims'] = [line for line in ssa.read_text().splitlines() if '(shared-elision' in line]
	product = build / ('telemetry-O' + args.optimization + '-' + args.facts)
	run([compiler, '-O' + args.optimization, *application, *libraries, *imports, *arguments, *links, '-o', product], args.facts)
	ir = product.with_suffix('.ll'); ir.write_text(run([compiler, '-O' + args.optimization, '--dump-llvm', *application, *libraries, *imports, *arguments], args.facts))
	assembly = product.with_suffix('.asm'); assembly.write_text(run(['objdump', '-dr', product]))
	receipt['products']['application'] = dict(path=str(product), sha256=sha(product), bytes=product.stat().st_size,
		ir_sha256=sha(ir), assembly_sha256=sha(assembly), ssa_sha256=sha(ssa), sections=run(['size', '-A', product]))
	assert sha(compiler) == receipt['compiler']['sha256'] and all(sha(ROOT / name) == digest for name, digest in receipt['inputs'].items())
	receipt['status'] = 'BUILT'; save()
	print(json.dumps(dict(product=str(product), receipt=str(runtime / 'build.json'))))


if __name__ == '__main__': main()
