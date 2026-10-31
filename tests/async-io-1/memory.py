# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate compiler, real C instrumentation, and unsupported-tool evidence."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]

def main():
	build, prefix, output = [Path(value).resolve() for value in sys.argv[1:4]]
	output.mkdir(parents=True, exist_ok=True)
	receipt = output / 'receipts.json'
	if receipt.exists():
		history = output / 'history'
		history.mkdir(exist_ok=True)
		(history / (hashlib.sha256(receipt.read_bytes()).hexdigest() + '.json')).write_bytes(receipt.read_bytes())
	records = []
	inputs = [build / 'astrac', build / 'tests/async-io-1/astra-linux-async-frames', build / 'tests/async-io-1/astra-linux-async-runtime', prefix / 'lib/liburing.a', SOURCE / 'lib/runtime/async/virtual.c', SOURCE / 'lib/runtime/async/linux.c', Path(__file__).resolve()]
	identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
	def save():
		receipt.write_text(json.dumps({'inputs': identities, 'records': records, 'limits': 'ASan/UBSan instrument C core/provider/observers; generated LLVM and private helper are not compiler-sanitized. Valgrind syscall unavailability is explicitly separate. No kernel-internal instrumentation.'}, separators=(',', ':')) + '\n')
	def run(name, command, expected=0, unavailable=False):
		command = list(map(str, command))
		result = subprocess.run(command, capture_output=True, timeout=180)
		row = {'name': name, 'command': command, 'expected': expected, 'exit': result.returncode, 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'status': 'PASS' if result.returncode == expected else 'FAIL'}
		if command[0] == 'valgrind':
			def count(pattern):
				match = re.search(pattern, result.stderr)
				return int(match[1].replace(b',', b'')) if match else None
			row['memory'] = {name: count(pattern) for name, pattern in [('errors', rb'ERROR SUMMARY: ([0-9,]+) errors'), ('live_bytes', rb'in use at exit: ([0-9,]+) bytes'), ('definitely_lost', rb'definitely lost: ([0-9,]+) bytes'), ('indirectly_lost', rb'indirectly lost: ([0-9,]+) bytes'), ('possibly_lost', rb'possibly lost: ([0-9,]+) bytes'), ('reachable', rb'still reachable: ([0-9,]+) bytes'), ('suppressed_errors', rb'\(suppressed: ([0-9,]+) from')]}
			row['default_suppressions'] = False
			row['summary'] = result.stderr.decode(errors='replace')[-2200:]
			if row['memory']['errors'] != 0 or row['memory']['suppressed_errors'] != 0 or any(row['memory'][key] not in (0, None) for key in ('definitely_lost', 'indirectly_lost', 'possibly_lost')):
				row['status'] = 'FAIL'
			if unavailable and (b'unhandled syscall' in result.stderr or b'unimplemented' in result.stderr or b'not supported' in result.stderr):
				row['status'] = 'UNAVAILABLE'
				row['diagnostic'] = result.stderr.decode(errors='replace')[-7000:]
		if len(result.stdout) < 3000:
			row['observations'] = result.stdout.decode(errors='replace')
		records.append(row)
		save()
		print(name, row['status'], flush=True)
		assert row['status'] in ('PASS', 'UNAVAILABLE'), (command, result.returncode, result.stdout[-1000:], result.stderr[-5000:])
		return result.stdout
	support = [SOURCE / 'lib/astra/base/errors.astra', SOURCE / 'lib/astra/async/linux.astra']
	app = [SOURCE / 'tests/async-io-1/application' / n for n in ('types.astra', 'produce.astra', 'controller.astra', 'main.astra')]
	if shutil.which('valgrind'):
		options = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible']
		control = output / 'synchronous.astra'
		control.write_text('int main(){return 42;}\n')
		run('compiler-synchronous-infrastructure', [*options, build / 'astrac', '--check', control])
		run('compiler-Linux-source', [*options, build / 'astrac', '--check', *support, *app])
		run('retained-source-native-LLVM-artifacts', [*options, build / 'tests/async-io-1/astra-linux-async-frames', '--tap'])
		run('Valgrind-real-provider', [*options, build / 'tests/async-io-1/astra-linux-async-runtime'], unavailable=True)
	else:
		records.append({'name': 'Valgrind', 'status': 'UNAVAILABLE', 'diagnostic': 'Tool absent'})
	common = ['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I' + str(prefix / 'include'), '-I' + str(SOURCE / 'lib/runtime/async')]
	program = output / 'sanitized'
	run('sanitized-native-build', [*common, SOURCE / 'tests/async-io-1/runtime-tests.c', SOURCE / 'lib/runtime/async/virtual.c', SOURCE / 'lib/runtime/async/linux.c', prefix / 'lib/liburing.a', '-o', program])
	run('ASan-UBSan-real-expiry-cancel-pressure', [program])
	core, provider, observer = [output / n for n in ('core.o', 'linux.o', 'observer.o')]
	for name, source, obj, flags in [('core', SOURCE / 'lib/runtime/async/virtual.c', core, []), ('provider', SOURCE / 'lib/runtime/async/linux.c', provider, []), ('observer', SOURCE / 'tests/async-io-1/observer.c', observer, ['-DASTRA_LINUX_PLAIN_OBSERVER'])]:
		run('sanitized-' + name, [*common, *flags, '-c', source, '-o', obj])
	llvm, obj = output / 'program.ll', output / 'program.o'
	llvm.write_bytes(run('verified-generated-LLVM', [build / 'astrac', '--dump-llvm', *support, *app]))
	run('verified-LLVM-object', ['llc', '-filetype=obj', llvm, '-o', obj])
	if shutil.which('valgrind'):
		native_objects = []
		for name, source, flags in [('core', SOURCE / 'lib/runtime/async/virtual.c', []), ('provider', SOURCE / 'lib/runtime/async/linux.c', []), ('observer', SOURCE / 'tests/async-io-1/observer.c', ['-DASTRA_LINUX_PLAIN_OBSERVER'])]:
			native = output / ('native-' + name + '.o')
			run('Valgrind-native-' + name, ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I' + str(prefix / 'include'), '-I' + str(SOURCE / 'lib/runtime/async'), *flags, '-c', source, '-o', native])
			native_objects.append(native)
		native_program = output / 'native-program'
		run('Valgrind-generated-link', ['cc', obj, *native_objects, SOURCE / 'tests/async-io-1/entry.c', prefix / 'lib/liburing.a', '-o', native_program])
		run('Valgrind-real-generated-program', [*options, native_program], 42, unavailable=True)
	run('sanitized-generated-link', [*common, obj, core, provider, observer, SOURCE / 'tests/async-io-1/entry.c', prefix / 'lib/liburing.a', '-o', program])
	run('ASan-UBSan-real-generated-program-boundary', [program], 42)
	save()
	return 0

if __name__ == '__main__':
	sys.exit(main())
