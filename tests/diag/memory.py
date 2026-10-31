# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal/fatal compiler and provider memory measurements."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from qualify import HERE, LIB, ROOT, STAGES, COMMANDS, sha, write_json


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
from output_paths import current_output

def qualify(build, baseline, out, qualification=None):
	build = build.resolve(); baseline = baseline.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	qualification = (qualification or build / 'diag-1').resolve()
	jobs = []
	for stage in ['semantic', 'pipeline', 'llvm']:
		jobs.append(dict(name='stage-' + stage, argv=[build / ('tests/diag/astra-diag-' + stage), '--tap'], status=0))
	for stage in STAGES:
		jobs.append(dict(name='compiler-' + stage, argv=[build / 'astrac', '--dump-' + stage, ROOT / 'examples/diagnostics/main.astra', LIB / 'base/diagnostics.astra'], status=0))
	for name, source in [('parse-failure', 'void f([CallerArgumentExpression(1)] string x){}'), ('semantic-failure', 'void f([CallerFilePath] int x){}'), ('failed-call', 'void f(bool x,[CallerLineNumber] int n){} void g(){f(1);}')]:
		path = out / (name + '.astra'); path.write_text(source); jobs.append(dict(name=name, argv=[build / 'astrac', '--check', path], status=1))
	growth = out / 'capture-growth.astra'; growth.write_text('void sample(int value,[CallerArgumentExpression("value")] string expression){} int main(){' + ''.join('sample(%d /* distinct capture %d */);' % (i, i) for i in range(6000)) + 'return 0;}')
	jobs.append(dict(name='capture-pool-growth', argv=[build / 'astrac', '--dump-llvm', growth], status=0))
	control = out / 'ordinary-name-control.astra'; control.write_text('int f(){' + ''.join('int C%d=0;' % i for i in range(5001)) + 'return 0;}')
	# Exact bytes of the inherited ARGS-1 control, independently reproducible.
	assert sha(control.read_bytes()) == '926d5a295e7a62db4fc11c96a59d71437e5cc96026ee092d31dca696a2965927'
	for name, compiler in [('baseline', baseline / 'astrac'), ('candidate', build / 'astrac')]:
		jobs.append(dict(name=name + '-name-control', argv=[compiler, '--dump-semantics', control], status=99, inherited=True))
	runtime = current_output(qualification / 'runtime')
	for host in ['gcc', 'clang']:
		for vector in [2, 3]:
			jobs.append(dict(name='renderer-' + host + '-' + str(vector), argv=[runtime / ('rendering/render-' + host)], status=0, input=runtime / f'rendering/vector-{vector:03}.bin'))
		for mode in ['O0', 'O2', 'fma', 'preserved']:
			jobs.append(dict(name='library-' + mode + '-' + host, argv=[runtime / f'effects/eager-true-{mode}-{host}'], status=0))
			jobs.append(dict(name='ownership-' + mode + '-' + host, argv=[runtime / f'ownership/ownership-{mode}-{host}', 'ok'], status=0))
			jobs.append(dict(name='ownership-output-' + mode + '-' + host, argv=[runtime / f'ownership-output/ownership-output-{mode}-{host}', 'ok'], status=0))
		jobs.append(dict(name='fatal-ownership-' + host, argv=[runtime / f'ownership/ownership-O0-{host}', 'fatal é %s%n'], fatal=True))
		jobs.append(dict(name='fatal-ownership-output-' + host, argv=[runtime / f'ownership-output/ownership-output-O0-{host}', 'fatal é %s%n'], fatal=True))
		jobs.append(dict(name='fatal-trap-' + host, argv=[current_output(qualification / 'qualification') / f'failures/trap-O0-{host}'], fatal=True))
	installation = current_output(qualification / 'installation'); result = json.loads((installation / 'results.json').read_text()); client = Path(result['cwd']); installed = Path(result['compiler'])
	jobs.append(dict(name='installed-consumer', argv=[client / 'consumer-0', 'ok'], status=0))
	jobs.append(dict(name='installed-compiler', argv=[installed, '--dump-llvm', 'client.astra', 'wrapper.astra', 'helper.astra', 'library.astra'], cwd=client, status=0))
	jobs.append(dict(name='compiler-full-link', argv=[build / 'astrac', ROOT / 'examples/diagnostics/main.astra', LIB / 'base/diagnostics.astra', '--link-object', build / 'lib/astra/args-posix.o', '--link-object', build / 'lib/astra/diagnostics-hosted.o', '-o', out / 'linked-example'], status=0))
	def measure(job):
		name = job['name']; log = out / (name + '.log')
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file=' + str(log), *map(str, job['argv'])]
		p = subprocess.run(command, input=job['input'].read_bytes() if 'input' in job else None, capture_output=True, timeout=600, cwd=job.get('cwd', ROOT), env=dict(os.environ, CCACHE_DISABLE='1', DIAG_OUTPUT=str(out / 'semantic-output')))
		(out / (name + '.stdout')).write_bytes(p.stdout); (out / (name + '.stderr')).write_bytes(p.stderr)
		text = log.read_text()
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, category='inherited-glib' if job.get('inherited') else 'fatal' if job.get('fatal') else 'normal', status=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), allocations=number(r'total heap usage: ([\d,]+) allocs'), command=command, log_sha256=sha(log.read_bytes()))
		write_json(out / (name + '.json'), row)
		assert 'ERROR SUMMARY:' in text and row['suppressed'] == 0, row
		if job.get('inherited'):
			assert p.returncode == 99 and row['errors'] == 2 and row['definite'] == 49152 and row['indirect'] == row['possible'] == 0, row
			assert '16,384 bytes in 1 blocks are definitely lost' in text and '32,768 bytes in 1 blocks are definitely lost' in text and 'g_quark_from_string' in text, name
		elif job.get('fatal'):
			assert p.returncode < 0 and row['errors'] == 0, row
		else:
			assert p.returncode == job['status'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
		return row
	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write_json(out / 'results.json', rows)
	print('DIAG-1 unsuppressed memory qualification PASS:', len(rows), 'records')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('baseline', type=Path); parser.add_argument('output', type=Path); parser.add_argument('--qualification-root', type=Path); args = parser.parse_args()
	qualify(args.build, args.baseline, fresh_output(args.output), args.qualification_root)
