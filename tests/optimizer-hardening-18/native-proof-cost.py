#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unknown-summary acceptance, actual preflight counts and raw compilation costs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('build', type=Path)
	parser.add_argument('runtime', type=Path)
	parser.add_argument('--baseline', type=Path)
	args = parser.parse_args()
	for path in [args.build, args.runtime]:
		assert not path.resolve().is_relative_to(ROOT)
		path.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='empty-proof-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='empty-proof-', dir=args.runtime.resolve()))
	compilers = {'current': args.compiler.resolve(strict=True)}
	if args.baseline: compilers['baseline'] = args.baseline.resolve(strict=True)
	receipt = dict(compilers={name: dict(path=str(path), sha256=sha(path)) for name, path in compilers.items()},
		checks=[], samples=[], products={}, schedule='serial counts 32/128/512; 3 rounds; alternating compiler order')
	production = sorted({p for prefix in ['bootstrap', 'lib', 'tools'] for p in (ROOT / prefix).rglob('*') if p.is_file() and p.suffix in ('.vala', '.vapi', '.c', '.h', '.py', '.astra')})
	production += [ROOT / 'meson.build', ROOT / 'meson.options']
	receipt['production_snapshot'] = {str(p.relative_to(ROOT)): sha(p) for p in production}
	codec = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	receipt['inputs'] = {str(p.relative_to(ROOT)): sha(p) for p in [Path(__file__).resolve(), HERE / 'native-observer.c', ROOT / 'tests/structural-generics-15/units.py']}
	def save(): (runtime / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, expected_stdout=None):
		command = [str(part) for part in command]
		started = time.monotonic()
		process = subprocess.run(command, cwd=build, text=True, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS='', LC_ALL='C'))
		row = dict(command=command, exit=process.returncode, stdout=process.stdout, stderr=process.stderr,
			seconds=time.monotonic()-started)
		receipt['checks'].append(row); save()
		assert process.returncode == 0 and (expected_stdout is None or process.stdout == expected_stdout), row
		return process
	def metadata(interface):
		data = codec['metadata'](interface.read_text())
		assert data['abi']['schema'].endswith('runtime-units/6')
		functions = [fields for group, fields in data.items() if group.startswith('function ')]
		assert functions and all(fields['optimizer'] == r'astra-optimizer-summary/1\nmemory|unknown' for fields in functions)
		return data
	def command(compiler, source, count, prefix):
		selectors = [part for index in range(count) for part in ['--native-export', 'UnknownProof18.step' + str(index)]]
		return [compiler, '-O2', '-c', source, '--module', 'UnknownProof18', *selectors,
			'--emit-interface', prefix.with_suffix('.asti'), '-o', prefix.with_suffix('.o')]
	for count in [32, 128, 512]:
		source = build / ('unknown-' + str(count) + '.astra')
		source.write_text('namespace UnknownProof18; extern(C) void native18_event();\n' + ''.join(
			'f64 step' + str(index) + '(f64 value){native18_event();return value;}\n' for index in range(count)))
		for iteration in range(3):
			order = list(compilers) if iteration % 2 == 0 else list(reversed(compilers))
			for name in order:
				prefix = build / f'{name}-{count}-{iteration}'
				stats = runtime / (prefix.name + '.time')
				run(['/usr/bin/time', '-f', '%U %S %e %M', '-o', stats,
					*command(compilers[name], source, count, prefix)], '')
				user, system, elapsed, rss = stats.read_text().split()
				metadata(prefix.with_suffix('.asti'))
				receipt['samples'].append(dict(compiler=name, count=count, iteration=iteration,
					user_seconds=float(user), system_seconds=float(system), elapsed_seconds=float(elapsed), peak_rss_kib=int(rss)))
				receipt['products'][prefix.name] = {ext: sha(prefix.with_suffix(ext)) for ext in ['.asti', '.o']}; save()
				# Keep input identities, then remove each implementation before consuming
				# the last interface/object pair from each compiler's actual invocation.
		receipt['inputs'][str(source)] = sha(source); source.unlink()
	observer = build / 'observer.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'native-observer.c', '-o', observer], '')
	client = build / 'client.astra'
	client.write_text('using UnknownProof18; int main(){if(step0(7.0)!=7.0){return 1;}return 0;}\n')
	for name, compiler in compilers.items():
		for count in [32, 128, 512]:
			prefix = build / f'{name}-{count}-2'
			executable = build / (prefix.name + '-client')
			run([compiler, '-O2', client, '--import-module', prefix.with_suffix('.asti'), '--link-object', observer, '-o', executable], '')
			run([executable], 'opaque\n')
			# Count the actual LLVM object-buffer emission API, rather than inferring
			# that an empty summary bypassed expensive work from exit status alone.
		source = build / ('trace-' + name + '.astra')
		source.write_text('namespace UnknownProof18; extern(C) void native18_event();\nf64 step0(f64 value){native18_event();return value;}\n')
		gdb = build / ('count-' + name + '.gdb')
		gdb.write_text('set pagination off\nset disable-randomization off\nset breakpoint pending on\nset $proof_emits = 0\n'
			'break LLVMTargetMachineEmitToMemoryBuffer\ncommands 1\nsilent\nset $proof_emits = $proof_emits + 1\ncontinue\nend\n'
			'run\nprintf "PROOF_EMITS=%d\\n", $proof_emits\n')
		prefix = build / ('traced-' + name)
		result = run(['gdb', '--nx', '--batch', '-x', gdb, '--args', *command(compiler, source, 1, prefix)])
		match = re.search(r'PROOF_EMITS=(\d+)', result.stdout)
		assert match and int(match[1]) == (1 if name == 'baseline' else 0), result
		metadata(prefix.with_suffix('.asti'))
		receipt.setdefault('actual_preflight_emissions', {})[name] = int(match[1]); save()
	for name, compiler in compilers.items(): assert sha(compiler) == receipt['compilers'][name]['sha256']
	assert all(sha(ROOT / name) == digest for name, digest in receipt['production_snapshot'].items())
	receipt['production_unchanged_during_measurement'] = True
	receipt['medians'] = {name: {str(count): statistics.median(
		row['elapsed_seconds'] for row in receipt['samples'] if row['compiler'] == name and row['count'] == count)
		for count in [32, 128, 512]} for name in compilers}
	receipt['status'] = 'PASS'; save()
	print(runtime / 'checks.json')


if __name__ == '__main__': main()
