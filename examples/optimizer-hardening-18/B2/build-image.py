#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build B2 image topology through explicit public/native/runtime routes."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from freeze import check as freeze_check

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'library-root', 'build', 'runtime']: parser.add_argument('--' + name, type=Path, required=True)
	parser.add_argument('--profile', choices=['sequential', 'threaded', 'uring'], default='sequential')
	parser.add_argument('--optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--producer-optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--facts', choices=['off', 'on'], required=True)
	parser.add_argument('--linkage', choices=['local', 'native'], default='native')
	parser.add_argument('--variant', choices=['base', 'renamed', 'fields', 'helpers'], default='base')
	parser.add_argument('--uring-prefix', type=Path)
	parser.add_argument('--freeze', type=Path)
	args = parser.parse_args(); compiler, library = args.compiler.resolve(strict=True), args.library_root.resolve(strict=True)
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='image-B2-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='image-B2-', dir=args.runtime.resolve()))
	def frozen(): return freeze_check(args.freeze, ROOT) if args.freeze else None
	receipt = dict(status='BUILDING_NOT_QUALIFIED', compiler=dict(path=str(compiler), sha256=sha(compiler)),
		profile=args.profile, optimization=args.optimization, producer_optimization=args.producer_optimization, producer_facts='on',
		facts=args.facts, linkage=args.linkage, variant=args.variant, commands=[], inputs={}, products={}, freeze_before=frozen())
	path = runtime / 'build.json'
	def save(): path.write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, facts=None, output=None):
		command = list(map(str, command)); start = time.monotonic()
		q = subprocess.run(command, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1',
			ASTRA_TEST_OPTIMIZATIONS=facts or args.facts, ASTRA_EXPLAIN_OPTIMIZATIONS='1'), capture_output=True, text=True, timeout=90)
		if output is not None: output.write_text(q.stdout)
		receipt['commands'].append(dict(command=command, facts=facts or args.facts, exit=q.returncode, seconds=time.monotonic() - start,
			stdout=q.stdout if output is None else dict(path=str(output), sha256=sha(output)), stderr=q.stderr)); save()
		assert q.returncode == 0 and not q.stderr, receipt['commands'][-1]
		return q.stdout
	try:
		consumer = [HERE / ('image-' + name + '.astra') for name in ['host', 'common', 'color', 'rows', 'components', 'jobs']]
		consumer += [library / 'base/errors.astra', library / 'collections/map.astra', library / 'collections/vector.astra']
		vapis = [library / 'memory/contexts.vapi']
		providers = [HERE / 'image-host.c', library / 'runtime/context-17.c', library / 'platform/args-posix.c']
		flags = ['-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-I', library / 'runtime']
		links = []
		if args.profile == 'sequential': consumer += [HERE / 'image-sequential.astra']
		elif args.profile == 'threaded':
			consumer += [HERE / 'image-threaded.astra', library / 'async/threaded.astra']
			providers += [library / 'async/threaded.c', library / 'runtime/monitors-13.c']
		else:
			assert args.uring_prefix; prefix = args.uring_prefix.resolve(strict=True)
			consumer += [HERE / 'image-io-cpu.astra', HERE / 'image-io.astra', library / 'async/payload.astra']
			vapis += [library / 'async/composition.vapi', library / 'async/payload.vapi']
			providers += [library / 'async/composed.c', library / 'async/linux.c', library / 'runtime/monitors-13.c']
			flags += ['-DIMAGE2_IO', '-isystem', prefix / 'include']; links += [prefix / 'lib/liburing.a']
		leaf, middle = HERE / 'image-leaf.astra', HERE / 'image-middle.astra'
		inputs = [Path(__file__), HERE / 'freeze.py', leaf, middle, *consumer, *vapis, *providers, *links]
		receipt['inputs'] = {str(p): sha(p) for p in inputs}
		sources = build / 'sources'; sources.mkdir()
		texts = {p.name: p.read_text() for p in [leaf, middle, *consumer] if p.parent == HERE}
		if args.variant == 'renamed':
			for name, code in texts.items():
				for before, after in [('ImageSpan18', 'RasterSpan18'), ('ImageRules18', 'RasterRules18'), ('RowSpan18', 'RowDomain18'),
					('ImageAuditOwner18', 'RowHistory18'), ('ImageComponentOwner18', 'ClusterOwner18'), ('ImageColorOwner18', 'ColorPacket18')]: code = code.replace(before, after)
				texts[name] = code
		elif args.variant == 'fields':
			before = '\tint first;\n\tint last;\n\tint row;\n\tint kind;'; assert before in texts[leaf.name]
			texts[leaf.name] = texts[leaf.name].replace(before, '\tint kind;\n\tint last;\n\tint first;\n\tint row;')
		elif args.variant == 'helpers':
			for name in ['first', 'second']:
				before = 'x >= span_edge(' + name + ', false) && x < span_edge(' + name + ', true)'
				assert before in texts['image-rows.astra']; texts['image-rows.astra'] = texts['image-rows.astra'].replace(before, 'image2_contains(' + name + ', x)')
			texts['image-rows.astra'] += '\nbool image2_contains(RowSpan18 span, int x) { return x >= span_edge(span, false) && x < span_edge(span, true); }\n'
		for name, code in texts.items(): (sources / name).write_text(code)
		receipt['rendered_inputs'] = {str(sources / name): sha(sources / name) for name in texts}
		consumer = [sources / p.name if p.parent == HERE else p for p in consumer]
		leaf, middle = sources / leaf.name, sources / middle.name
		leaf_module, middle_module = ('RasterSpan18', 'RasterRules18') if args.variant == 'renamed' else ('ImageSpan18', 'ImageRules18')
		class_name = 'RowDomain18' if args.variant == 'renamed' else 'RowSpan18'
		imports, objects = [], []
		if args.linkage == 'native':
			producer = build / 'producer'; producer.mkdir(); sdk = build / 'sdk'; sdk.mkdir()
			for source in [leaf, middle, sources / 'image-host.astra']: shutil.copyfile(source, producer / source.name)
			run([compiler, '-O' + args.producer_optimization, '-c', '--module', leaf_module,
				*[arg for name in [class_name, 'span_start'] for arg in ['--native-export', leaf_module + '.' + name]],
				'--emit-interface', sdk / 'leaf.asti', producer / leaf.name, producer / 'image-host.astra', '-o', sdk / 'leaf.o'], facts='on')
			run([compiler, '-O' + args.producer_optimization, '-c', '--module', middle_module,
				*[arg for name in ['span_edge', 'blend'] for arg in ['--native-export', middle_module + '.' + name]],
				'--import-module', sdk / 'leaf.asti', '--emit-interface', sdk / 'middle.asti', producer / middle.name, '-o', sdk / 'middle.o'], facts='on')
			for source in producer.iterdir(): source.unlink()
			leaf.unlink(); middle.unlink(); receipt['producer_inputs_removed'] = True
			imports = ['--import-module', sdk / 'middle.asti']; objects = [sdk / 'leaf.o', sdk / 'middle.o']
		else: consumer += [leaf, middle]
		common = [compiler, '-O' + args.optimization, *consumer, *[arg for p in vapis for arg in ['--vapi', p]], *imports]
		ssa = build / 'image.ssa'; run([common[0], *common[2:], '--dump-ssa'], output=ssa)
		receipt['claims'] = {name: [line for line in ssa.read_text().splitlines() if marker in line]
			for name, marker in [('storage', '(stack-object'), ('shared', '(shared-elision'), ('dispatch', '(exact-call')]}
		ir = build / 'image.ll'; run([*common, '--dump-llvm'], output=ir)
		obj, product = build / 'image.o', build / 'image'
		command = [*common, '--entry-object', '-o', obj]; receipt['consumer_command'] = list(map(str, command))
		trace = runtime / 'consumer-opens.log'; run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command])
		if args.linkage == 'native':
			opened = trace.read_text()
			assert str(HERE / 'image-leaf.astra') not in opened and str(HERE / 'image-middle.astra') not in opened and str(producer) not in opened
		wrappers = ['-Wl,--wrap=' + name for name in ['calloc', 'malloc', 'realloc']]
		link = ['cc', *flags, obj, *objects, *providers, *links, *wrappers, '-o', product]
		receipt['link_command'] = list(map(str, link)); run(link)
		assembly = build / 'image.asm'; run(['objdump', '-dr', product], output=assembly); receipt['sections'] = run(['size', '-A', product])
		artifacts = [ssa, ir, obj, product, trace, assembly, *objects]
		if args.linkage == 'native': artifacts += [sdk / 'leaf.asti', sdk / 'middle.asti']
		receipt['products'] = {str(p): dict(sha256=sha(p), bytes=p.stat().st_size) for p in artifacts}; receipt['product'] = str(product)
		assert sha(compiler) == receipt['compiler']['sha256'] and all(sha(p) == h for p, h in receipt['inputs'].items())
		receipt['status'] = 'BUILT_NOT_QUALIFIED'
	finally:
		receipt['freeze_after'] = frozen(); save()
	print(path); print(product)


if __name__ == '__main__': main()
