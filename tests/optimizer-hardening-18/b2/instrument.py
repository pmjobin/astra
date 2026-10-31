#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay relocated B2 consumers and instrument all emitted LLVM/C providers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from reference import reconcile, SEED
from qualify import observations, ROOT, APP, sample_input as generate
sys.path.insert(0, str(APP))
from freeze import check as freeze_check


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['qualification', 'build', 'runtime']: parser.add_argument(name, type=Path)
	parser.add_argument('--freeze', type=Path)
	args = parser.parse_args(); qualified = json.loads(args.qualification.read_text())
	assert qualified['status'] == 'PASS' and qualified['source_unchanged']
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT); path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='B2-instrument-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='B2-instrument-', dir=args.runtime.resolve()))
	receipt = dict(status='RUNNING', qualification_sha256=sha(args.qualification), source_snapshot=qualified['source_snapshot'],
		inputs={str(Path(__file__)): sha(Path(__file__))}, commands=[], products={}, traces={},
		coverage='Every emitted consumer/library LLVM function and linked C provider is instrumented. Opaque native leaf/middle objects and static liburing remain exact and outside compiler instrumentation; complete native products separately run unsuppressed Memcheck.')
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def frozen(): return freeze_check(args.freeze, ROOT) if args.freeze else None
	def run(command, env=None, cwd=runtime):
		command = list(map(str, command)); start = time.monotonic()
		q = subprocess.run(command, cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1', DEBUGINFOD_URLS='', LC_ALL='C', **(env or {})),
			capture_output=True, text=True, timeout=90)
		row = dict(command=command, cwd=str(cwd), environment=env or {}, exit=q.returncode, stdout=q.stdout, stderr=q.stderr, seconds=time.monotonic() - start)
		receipt['commands'].append(row); save(); assert q.returncode == 0 and not q.stderr, row
		return q.stdout
	def execute(product, name, profile, count):
		data = generate(count, SEED + 31); expected, reference = reconcile(data)
		source, target = runtime / (name + '.input'), runtime / (name + '.output'); source.write_bytes(data)
		stdout = run([product, source, target], dict(ASTRA_IMAGE_WORKERS='4', ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',
			UBSAN_OPTIONS='halt_on_error=1', TSAN_OPTIONS='halt_on_error=1'))
		assert target.read_bytes() == expected
		return dict(records=count, output_sha256=sha(target), **observations(stdout, data, reference, profile, 1 if profile == 'sequential' else 4))
	try:
		receipt['freeze_before'] = frozen()
		for profile in qualified['profiles']:
			for facts in ['off', 'on']:
				name = profile + '-' + facts; case = build / name; case.mkdir()
				product = qualified['products'][profile + '-base-O2-native-P2-' + facts]
				path = Path(product['receipt']); assert sha(path) == product['receipt_sha256']; complete = json.loads(path.read_text())
				compiler = Path(complete['compiler']['path']); assert sha(compiler) == qualified['compiler']['sha256']
				sdk = case / 'sdk'; sdk.mkdir(); copied = {}
				command = complete['consumer_command']
				for argument in command[1:]:
					original = Path(argument)
					if not original.is_file() or original.suffix not in ['.astra', '.vapi', '.asti']: continue
					destination = sdk / (original.relative_to(ROOT) if original.is_relative_to(ROOT) else Path(original.name))
					destination.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(original, destination); copied[argument] = str(destination)
					if original.suffix == '.asti':
						for unit in ['leaf', 'middle']:
							for suffix in ['.asti', '.o']: shutil.copyfile(original.parent / (unit + suffix), destination.parent / (unit + suffix))
						assert not (original.parent.parent / 'sources/image-leaf.astra').exists()
						assert not (original.parent.parent / 'sources/image-middle.astra').exists()
				obj = case / 'relocated.o'; relocated = [copied.get(a, a) for a in command]; relocated[-1] = str(obj)
				trace = runtime / (name + '-consumer-opens.log')
				run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *relocated],
					dict(ASTRA_TEST_OPTIMIZATIONS=facts, ASTRA_EXPLAIN_OPTIMIZATIONS='1'), sdk)
				opened = trace.read_text(); assert str(ROOT) not in opened
				assert '/producer/' not in opened and 'image-leaf.astra' not in opened and 'image-middle.astra' not in opened
				receipt['traces'][name] = dict(path=str(trace), sha256=sha(trace), bytes=trace.stat().st_size, checkout_or_producer_reads=False)
				link = complete['link_command']
				library = Path(link[link.index('-I') + 1]).parent
				def destination_for(original):
					if original.is_relative_to(ROOT): return sdk / original.relative_to(ROOT)
					if original.is_relative_to(library): return sdk / 'library' / original.relative_to(library)
					return sdk / original.name
					# C platform edges and their headers are copied into the SDK too.
					# Context providers also include headers from sibling async/runtime
					# directories, even in the sequential application profile.
				for dependency in library.rglob('*'):
					if dependency.suffix not in ['.h', '.c'] or not dependency.is_file(): continue
					destination = destination_for(dependency); destination.parent.mkdir(parents=True, exist_ok=True)
					shutil.copyfile(dependency, destination)
				for argument in link:
					original = Path(argument)
					if original.is_file() and original.suffix == '.c':
						destination = destination_for(original)
						destination.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(original, destination); copied[argument] = str(destination)
						for header in original.parent.glob('*.h'): shutil.copyfile(header, destination.parent / header.name)
					elif original.is_dir() and (original.is_relative_to(ROOT) or original.is_relative_to(library)):
						destination = destination_for(original); destination.mkdir(parents=True, exist_ok=True)
						for header in original.glob('*.h'): shutil.copyfile(header, destination / header.name)
						copied[argument] = str(destination)
				for unit in ['leaf', 'middle']:
					original = Path(product['product']).parent / 'sdk' / (unit + '.o')
					copied[str(original)] = str(sdk / (unit + '.o'))
				base_link = [copied.get(a, a) for a in link]
				base_link[base_link.index(str(Path(product['product']).with_suffix('.o')))] = str(obj)
				relocated_product = case / 'relocated'; base_link[-1] = str(relocated_product)
				run(base_link, cwd=sdk); execute(relocated_product, name + '-relocated', profile, 527)
				target = dict(line.split('=', 1) for line in run([compiler, '--target-info']).splitlines() if '=' in line)
				raw = Path(product['product']).with_suffix('.ll'); assert sha(raw) == complete['products'][str(raw)]['sha256']
				for sanitizer in ['address', 'thread']:
					stem = case / sanitizer; attribute = 'sanitize_thread' if sanitizer == 'thread' else 'sanitize_address'
					code = re.sub(r'^target (?:datalayout|triple) = .*\n', '', raw.read_text(), flags=re.M)
					code = re.sub(r'^(define .*?)\s*\{\s*$', rf'\1 {attribute} {{', code, flags=re.M)
					code = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + code
					ir, modified, instrumented_obj = stem.with_suffix('.ll'), stem.with_suffix('.instrumented.ll'), stem.with_suffix('.o'); ir.write_text(code)
					passes = 'default<O1>,tsan-module,function(tsan)' if sanitizer == 'thread' else 'default<O1>,asan'
					run(['opt', '-passes=' + passes, '-S', ir, '-o', modified])
					instrumented = modified.read_text()
					assert ('__tsan_read' in instrumented and '__tsan_write' in instrumented) if sanitizer == 'thread' else '__asan_report' in instrumented
					run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', modified, '-o', instrumented_obj])
					instrumented_link = ['clang', '-fsanitize=' + ('thread' if sanitizer == 'thread' else 'address,undefined'), '-fno-omit-frame-pointer',
						*['-O1' if a == '-O2' else str(instrumented_obj) if a == str(obj) else a for a in base_link[1:]]]
					instrumented_link[-1] = str(stem); run(instrumented_link, cwd=sdk)
					results = [execute(stem, name + '-' + sanitizer + '-' + str(count), profile, count) for count in [527, 33153]]
					receipt['products'][name + '-' + sanitizer] = dict(path=str(stem), sha256=sha(stem),
						raw_ir_sha256=sha(raw), instrumented_ir_sha256=sha(modified), executions=results); save()
				receipt['freeze_after_profile'] = frozen(); save()
		assert all(sha(path) == digest for path, digest in receipt['source_snapshot'].items())
		assert all(sha(path) == digest for path, digest in receipt['inputs'].items())
		receipt.update(status='PASS', source_unchanged=True, freeze_after=frozen())
	finally:
		if receipt['status'] != 'PASS': receipt['status'] = 'FAIL'
		save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
