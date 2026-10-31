#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""APP-CAD-2 matched P/I measurements under one frozen compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import shlex
import time

HERE = Path(__file__).resolve().parent
SOURCES = ['src/numeric.astra', 'src/algorithm.astra', 'src/main.astra', 'src/entry.astra']
TIMER = '''#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static struct timespec start;
void cad_time_begin(void) { if (clock_gettime(CLOCK_MONOTONIC, &start)) { _Exit(98); } }
void cad_time_end(void) {
	struct timespec end;
	if (clock_gettime(CLOCK_MONOTONIC, &end)) { _Exit(98); }
	const char* name = getenv("CAD_TIME_OUTPUT");
	if (!name) { _Exit(98); }
	FILE* stream = fopen(name, "w");
	if (!stream) { _Exit(98); }
	int64_t elapsed = (int64_t)(end.tv_sec - start.tv_sec) * 1000000000 + end.tv_nsec - start.tv_nsec;
	if (fprintf(stream, "%lld\\n", (long long)elapsed) < 0 || fclose(stream)) { _Exit(98); }
}
'''


def execute(command, cwd, output, label, env):
	start = time.perf_counter_ns()
	p = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, env=env)
	elapsed = time.perf_counter_ns() - start
	(output / (label + '.stdout')).write_bytes(p.stdout)
	(output / (label + '.stderr')).write_bytes(p.stderr)
	row = {'label': label, 'argv': list(map(str, command)), 'cwd': str(cwd), 'status': p.returncode, 'elapsed_ns': elapsed, 'load_before_or_after': list(os.getloadavg())}
	with (output / 'commands.jsonl').open('a') as stream:
		stream.write(json.dumps(row) + '\n')
	if p.returncode:
		raise RuntimeError(f'{label} failed; inspect {output}')
	return row


def measure(args):
	out = args.output.resolve()
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(out / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
	plan = json.loads((HERE / 'idiomatic/timing-plan.json').read_text())
	(out / 'plan.json').write_text(json.dumps(dict(plan, scope='Current P/I; correctness must be complete before sampling.'), indent='\t') + '\n')
	routes = {'P': (args.compiler.resolve(), args.p_source.resolve(), args.p_build.resolve()), 'I': (args.compiler.resolve(), args.i_source.resolve(), args.i_build.resolve())}
	(out / 'timer.c').write_text(TIMER)
	execute(['/usr/bin/gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', out / 'timer.c', '-o', out / 'timer.o'], out, out, 'timer-build', env)
	commands = {}
	for route, (compiler, source, build) in routes.items():
		algorithm = (source / 'src/algorithm.astra').read_text()
		start = '\tinitialize(&c);' if route == 'P' else '\towned Context c = Context.init(wi, hi, wo, ho);'
		for old, new in [(start, '\tcad_time_begin();\n' + start), ('\tint result = cad_finish(', '\tcad_time_end();\n\tint result = cad_finish(')]:
			assert algorithm.count(old) == 1
			algorithm = algorithm.replace(old, new)
		(out / (route + '-timed-algorithm.astra')).write_text('extern(C) void cad_time_begin();\nextern(C) void cad_time_end();\n' + algorithm)
		files = [source / name for name in SOURCES]
		instrumented = [out / (route + '-timed-algorithm.astra') if path.name == 'algorithm.astra' else path for path in files]
		links = ['--link-object', build / 'libcad-io.so']
		links += ['--link-object', args.args_provider.resolve()]
		commands[route] = [compiler, *files, *links, '-o']
		execute([compiler, *instrumented, *links, '--link-object', out / 'timer.o', '-o', out / (route + '-timed')], source, out, route + '-timed-build', env)
	if args.prepare_only:
		return
	samples = []
	for repetition, order in enumerate(plan['balanced_orders']):
		for route in order:
			compiler, source, build = routes[route]
			label = f'{repetition}-{route}'
			row = execute([*commands[route], out / (label + '-compiled')], source, out, label + '-compile-link', env)
			assert hashlib.sha256((out / (label + '-compiled')).read_bytes()).digest() == hashlib.sha256((build / 'astra-cad').read_bytes()).digest()
			samples.append(dict(row, route=route, phase='Astra-compile-link', repetition=repetition))
			for name in ['adapter.c', 'arguments.c']:
				entries = json.loads((build / 'compile_commands.json').read_text())
				entry = next(item for item in entries if Path(item['file']).name == name and 'libcad-io.so.p/' in item['output'])
				command = entry.get('arguments') or shlex.split(entry['command'])
				target = out / (label + '-' + name + '.o')
				command[command.index('-o') + 1] = str(target)
				for option, value in [('-MF', str(target) + '.d'), ('-MQ', str(target))]:
					if option in command:
						command[command.index(option) + 1] = value
				row = execute(command, Path(entry['directory']), out, label + '-' + name, env)
				assert hashlib.sha256(target.read_bytes()).digest() == hashlib.sha256((build / entry['output']).read_bytes()).digest()
				samples.append(dict(row, route=route, phase='C-compile-' + name, repetition=repetition))
			for case in plan['cases']:
				name = case['name']
				input_path = args.synthetic_inputs.resolve() / (name + '-input.png')
				case_args = [input_path, out / (label + '-' + name + '.png'), *map(str, case['output']), *case.get('options', [])]
				selected_env = dict(env, LD_LIBRARY_PATH=str(build), CAD_TIME_OUTPUT=str(out / (label + '-' + name + '.ns')))
				plain = execute([build / 'astra-cad', *case_args], source, out, label + '-' + name + '-plain', selected_env)
				sha = hashlib.sha256(Path(case_args[1]).read_bytes()).hexdigest()
				timed = execute([out / (route + '-timed'), *case_args], source, out, label + '-' + name + '-timed', selected_env)
				assert sha == hashlib.sha256(Path(case_args[1]).read_bytes()).hexdigest()
				for suffix in ['stdout', 'stderr']:
					assert (out / (plain['label'] + '.' + suffix)).read_bytes() == (out / (timed['label'] + '.' + suffix)).read_bytes()
				samples.append(dict(plain, route=route, phase='CLI', case=name, repetition=repetition, output_sha256=sha))
				samples.append(dict(timed, elapsed_ns=int(Path(selected_env['CAD_TIME_OUTPUT']).read_text()), route=route, phase='numerical-with-two-clock-hooks', case=name, repetition=repetition, output_sha256=sha))
			(out / 'samples.json').write_text(json.dumps(samples, indent='\t') + '\n')
	groups = {}
	for row in samples:
		key = '/'.join([row['route'], row['phase'], row.get('case', '')])
		groups.setdefault(key, []).append(row['elapsed_ns'])
	summary = {}
	for key, values in groups.items():
		q1, _, q3 = statistics.quantiles(values, n=4, method='inclusive')
		summary[key] = {'count': len(values), 'median_ns': statistics.median(values), 'min_ns': min(values), 'max_ns': max(values), 'iqr_ns': q3 - q1}
	(out / 'summary.json').write_text(json.dumps(summary, indent='\t') + '\n')
	print(json.dumps(summary, indent='\t'))


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'p-source', 'i-source', 'p-build', 'i-build', 'args-provider', 'synthetic-inputs', 'output']:
		parser.add_argument('--' + name, type=Path, required=True)
	parser.add_argument('--prepare-only', action='store_true', help='compile the separate clock-observed programs without collecting comparative samples')
	measure(parser.parse_args())
