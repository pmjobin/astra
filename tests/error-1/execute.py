# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native exception carriers, cleanup, exact observer identity, and unsuppressed memory."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / 'fixtures'


def qualify(compiler, output):
	compiler = Path(compiler).resolve(); output = Path(output).resolve(); output.mkdir(parents=True, exist_ok=True)
	rows = []
	def run(command, expected=0, stdout=None):
		command = list(map(str, command)); started = datetime.datetime.now(datetime.timezone.utc).isoformat()
		p = subprocess.run(command, capture_output=True, timeout=90)
		row = dict(command=command, started_utc=started, expected=expected, observed=p.returncode, stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), stderr_sha256=hashlib.sha256(p.stderr).hexdigest())
		if p.stdout.startswith((b'native-observer ', b'runtime-observer ', b'memory-control ', b'runtime-memory ')): row['observer'] = p.stdout.decode('utf-8').strip(); print(row['observer'])
		if command[0] == 'valgrind':
			errors = re.search(rb'ERROR SUMMARY: ([0-9,]+) errors', p.stderr)
			live = re.search(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', p.stderr)
			suppressed = re.search(rb'\(suppressed: ([0-9,]+) from ([0-9,]+)\)', p.stderr)
			assert errors is not None and live is not None and suppressed is not None, p.stderr[-4000:]
			row['memory'] = dict(errors=int(errors[1].replace(b',', b'')), live_bytes=int(live[1].replace(b',', b'')), live_blocks=int(live[2].replace(b',', b'')), suppressed_errors=int(suppressed[1].replace(b',', b'')), default_suppressions=False, all_leak_kinds=True)
			assert row['memory']['errors'] == 0 and row['memory']['live_bytes'] == 0 and row['memory']['live_blocks'] == 0 and row['memory']['suppressed_errors'] == 0, row
		rows.append(row); (output / 'checks.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), fixtures={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in FIXTURES.iterdir() if p.is_file()}, checks=rows), indent='\t')+'\n')
		assert p.returncode == expected and (stdout is None or p.stdout == stdout), (row, p.stdout[-2000:], p.stderr[-4000:])
		return p.stdout
	def memory(executable):
		result = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', executable], 42)
		return result
	provider = output / 'args-posix.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'lib/runtime/platform/args-posix.c', '-o', provider])
	for stage in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		assert run([compiler, '--dump-'+stage, FIXTURES/'base-catch.astra']), stage
	for name in ['heap', 'snapshot', 'hierarchy', 'base-catch', 'success-groups', 'virtual-throws', 'argument-abort', 'control-flow', 'inspection', 'c-export', 'message-loans', 'fresh-staging', 'heap-factories', 'checked-owners']:
		path = FIXTURES / (name+'.astra'); extra = []
		if name in ('snapshot', 'control-flow'): extra += ['--link-object', provider]
		if name == 'c-export':
			foreign = output / 'c-export.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', FIXTURES/'c-export.c', '-o', foreign]); extra += ['--link-object', foreign]
		executable = output / name; run([compiler, path, *extra, '-o', executable]); run([executable], 42); memory(executable)
		if name in ('success-groups', 'virtual-throws', 'argument-abort', 'inspection', 'message-loans', 'fresh-staging', 'heap-factories', 'checked-owners'):
			ir = run([compiler, '--dump-llvm', path]); ssa = run([compiler, '--dump-ssa', path]); ordinal = re.search(rb'\(function #(\d+) "main" -> int', ssa)[1].decode()
			ir += ('\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n').encode()
			llvm = output / (name+'.ll'); llvm.write_bytes(ir); run(['opt', '-passes=verify', '-disable-output', llvm])
			optimized = output / (name+'-O2'); run(['clang', '-O2', llvm, '-o', optimized]); run([optimized], 42); memory(optimized)
	for mode in ('native', 'memory'):
		observer = output / ('observer-'+mode+'.o'); extra = ['-DERROR_MEMORY_ONLY'] if mode == 'memory' else []
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', *extra, '-c', FIXTURES/'observer.c', '-o', observer])
		executable = output / ('rethrow-'+mode); run([compiler, FIXTURES/'rethrow.astra', '--vapi', FIXTURES/'observer.vapi', '--link-object', observer, '-o', executable])
		if mode == 'native': run([executable], 42)
		else: memory(executable)
	for mode in ('native', 'memory'):
		observer = output / ('runtime-observer-'+mode+'.o'); extra = ['-DERROR_MEMORY_ONLY'] if mode == 'memory' else []
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', *extra, '-c', FIXTURES/'runtime-observer.c', '-o', observer])
		executable = output / ('runtime-'+mode); run([compiler, FIXTURES/'runtime-observer.astra', '--link-object', provider, '--link-object', observer, '-o', executable])
		arguments = [executable, 'external é']
		if mode == 'native': run(arguments, 42)
		else: run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *arguments], 42)
	failure = output / 'failure-trap.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'lib/runtime/platform/failure-trap.c', '-o', failure])
	boundaries = output / 'fatal-boundaries'; run([compiler, FIXTURES/'fatal-boundaries.astra', ROOT/'lib/astra/base/contracts.astra', '--link-object', provider, '--link-object', failure, '-o', boundaries])
	for mode in ('assert', 'bounds', 'arith', 'null'): run([boundaries, mode], -signal.SIGILL, b'')
	fatal = output / 'fatal.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', FIXTURES/'fatal.c', '-o', fatal]); executable = output / 'fatal'; run([compiler, FIXTURES/'fatal.astra', '--link-object', fatal, '-o', executable]); run([executable], -signal.SIGILL, b'OOM\n')
	print(json.dumps(dict(native_fixtures=14, optimized_fixtures=8, runtime_observer=True, rethrow_identity=True, unsuppressed_memory=True, fatal_categories=['assertion', 'bounds', 'arithmetic', 'allocation', 'null-owner-transfer'])))


if __name__ == '__main__':
	qualify(sys.argv[1], sys.argv[2])
