#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real kernel, public-driver, ownership, byte parity and memory receipts."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full',
	'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checksum(data):
	value = 0
	for byte in data:
		value = (value * 31 + byte) % 1000003
	return value


def main():
	compiler, output = [Path(p).resolve() for p in sys.argv[1:3]]
	prefix = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else Path(os.environ.get(
		'ASTRA_LIBURING_PREFIX', str(Path.home()/'.local/opt/liburing-2.15')))
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	if not (prefix/'include/liburing.h').is_file() or not (prefix/'lib/liburing.a').is_file():
		print('ENVIRONMENT_BLOCKED: provide an existing matching liburing >=2.15 prefix with ASTRA_LIBURING_PREFIX')
		return 77
	records, products = [], {}
	receipt = {'status': 'RUNNING', 'compiler_sha256': sha(compiler), 'liburing_archive_sha256': sha(prefix/'lib/liburing.a'),
		'sources': {str(p.relative_to(ROOT)): sha(p) for p in [
		HERE/'payload-check.py', HERE/'payload-runtime.c', HERE/'payload-observer.c',
		ROOT/'lib/runtime/async/linux.c', ROOT/'lib/runtime/async/virtual.c',
		ROOT/'lib/bindings/async/payload.vapi', ROOT/'lib/astra/async/payload.astra']},
		'records': records, 'products': products, 'applications': {}}

	def save():
		(output/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')

	def run(name, command, expected=0):
		command = list(map(str, command))
		started = time.monotonic()
		result = subprocess.run(command, cwd=output, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		row = {'name': name, 'command': command, 'exit': result.returncode, 'expected': expected,
			'seconds': round(time.monotonic() - started, 6),
			'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
			'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(),
			'stdout': result.stdout.decode(errors='replace')[-6000:],
			'stderr': result.stderr.decode(errors='replace')[-6000:]}
		records.append(row); save()
		print(name, 'PASS' if result.returncode == expected else 'FAIL', flush=True)
		assert result.returncode == expected, row
		return result

	cc = ['gcc', '-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror',
		'-I'+str(prefix/'include'), '-I'+str(ROOT/'lib/runtime/async')]
	archive = prefix/'lib/liburing.a'
	run('provider-probe-build', [*cc, HERE/'provider-probe.c', archive, '-o', output/'provider-probe'])
	probe = run('provider-probe-real', [output/'provider-probe'])
	assert json.loads(probe.stdout)['status'] == 'AVAILABLE'
	for name in ('virtual', 'linux'):
		run(name+'-real-provider-build', [*cc, *(['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL'] if name == 'linux' else []), '-c', ROOT/f'lib/astra/async/{name}.c', '-o', output/f'{name}.o'])
	run('observer-build', [*cc, '-c', HERE/'payload-observer.c', '-o', output/'observer.o'])
	runtime = [HERE/'payload-runtime.c', ROOT/'lib/runtime/async/linux.c', ROOT/'lib/runtime/async/virtual.c', archive]
	run('runtime-build', [*cc, '-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', *runtime, '-o', output/'runtime'])
	run('runtime-real-and-guard-mutations', [output/'runtime'])
	memory = run('runtime-unsuppressed-valgrind', [*VG, output/'runtime', '--memory'])
	assert 'in use at exit: 0 bytes in 0 blocks' in memory.stderr.decode() and 'suppressed: 0 from 0' in memory.stderr.decode()
	run('runtime-sanitized-build', ['clang-22', *cc[1:], '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', *runtime, '-o', output/'runtime-sanitized'])
	run('runtime-ASan-UBSan', [output/'runtime-sanitized', '--memory'])

	libs = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/async/linux.astra',
		ROOT/'lib/astra/async/payload.astra',
		ROOT/'lib/astra/hosted/text.astra', ROOT/'lib/astra/text/utf8-message.astra',
		ROOT/'lib/astra/hosted/text-ops.astra', ROOT/'lib/astra/text/scalar-format.astra',
		ROOT/'lib/astra/text/utf8-byte-builder.astra', ROOT/'lib/astra/collections/bag.astra']
	# Explicit support objects; default nonusers do not acquire liburing.
	links = [output/'virtual.o', output/'linux.o', output/'observer.o', archive]
	for name in ('args-posix', 'text-posix', 'text-ops-posix'):
		run(name+'-build', [*cc, '-c', ROOT/f'lib/astra/platform/{name}.c', '-o', output/f'{name}.o'])
		links.append(output/f'{name}.o')
	link_args = [arg for obj in links for arg in ('--link-object', obj)]
	link_args += ['--vapi', ROOT/'lib/bindings/async/payload.vapi']
	for opt in ('O0', 'O1', 'O2'):
		for app, label in [('binary-ingest', 'A37'), ('segmented-copy', 'A38'), ('cancellable-scan', 'A39')]:
			source = ROOT/f'examples/interop-async-5/{app}.astra'
			binary = output/f'{app}-{opt}'
			run(f'{label}-{opt}-public-build', [compiler, '-'+opt, *libs, source, *link_args, '-o', binary])
			products[binary.name] = {'sha256': sha(binary), 'bytes': binary.stat().st_size, 'source_sha256': sha(source)}
			receipt['applications'][label] = str(source.relative_to(ROOT))
			for size in (0, 1, 8193):
				data = bytes((i*37) & 255 for i in range(size))
				input_file = output/f'{label}-input.bin'; input_file.write_bytes(data)
				destination = output/f'{label}-output.bin'
				if app == 'binary-ingest':
					result = run(f'{label}-{opt}-{size}-real', [binary, input_file, destination])
					assert destination.read_bytes() == f'{size}:{checksum(data)}\n'.encode()
					assert b'submitted=3 closed=2' in result.stdout
				elif app == 'segmented-copy':
					result = run(f'{label}-{opt}-{size}-real', [binary, input_file, destination, '257'])
					assert destination.read_bytes() == data and b'closed=2' in result.stdout
				else:
					for when in (0, 1, 2):
						result = run(f'{label}-{opt}-{size}-cancel-{when}', [binary, input_file, str(when)])
						assert b'closed=1' in result.stdout
						expected = f'scans=1 bytes={size} checksum={checksum(data)}' if when == 2 else 'scans=0 bytes=0 checksum=0'
						assert expected.encode() in result.stdout
				if app != 'cancellable-scan':
					records[-1]['file_sha256'] = sha(destination)
			missing = [binary, output/'missing-input', '0'] if app == 'cancellable-scan' else [binary, output/'missing-input', destination] + (['257'] if app == 'segmented-copy' else [])
			run(f'{label}-{opt}-missing-input', missing, 2)
			if app == 'segmented-copy':
				run(f'{label}-{opt}-invalid-segment', [binary, input_file, destination, '0'], 64)
			if app == 'binary-ingest':
				too_large = output/'over-capacity.bin'; too_large.write_bytes(b'\xff'*65537)
				run(f'{label}-{opt}-over-capacity', [binary, too_large, destination], 2)
			args = [binary, input_file, destination] + (['257'] if app == 'segmented-copy' else [])
			if app == 'cancellable-scan': args = [binary, input_file, '2']
			memory = run(f'{label}-{opt}-unsuppressed-valgrind', [*VG, *args])
			assert 'in use at exit: 0 bytes in 0 blocks' in memory.stderr.decode() and 'suppressed: 0 from 0' in memory.stderr.decode()
			if app == 'cancellable-scan':
				for when in (0, 1):
					memory = run(f'{label}-{opt}-cancel-{when}-unsuppressed-valgrind', [*VG, binary, input_file, str(when)])
					assert 'in use at exit: 0 bytes in 0 blocks' in memory.stderr.decode() and 'suppressed: 0 from 0' in memory.stderr.decode()
			save()
			# Every public stage must expose the provider action; the native sidecar
			# additionally records exact stable pointer/owner hold authority.
	sample = ROOT/'examples/interop-async-5/binary-ingest.astra'
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm'):
		result = run('payload-stage-'+stage, [compiler, '--dump-'+stage, '--vapi', ROOT/'lib/bindings/async/payload.vapi', *libs, sample])
		expected = b'linux-payload-hold' if stage == 'nabi' else b'astra_async_linux_payload' if stage == 'llvm' else b'linux-payload-suspend'
		assert expected in result.stdout
		(output/f'payload-{stage}.txt').write_bytes(result.stdout)
	negatives = {
		'borrowed-payload': 'async void bad(borrowed LinuxPayload p)throws Error{await payload_io(p);}',
		'wrong-resource': 'async void bad(int p)throws Error{await payload_io(p);}',
		'moved-payload': 'async void bad(owned LinuxPayload p)throws Error{var moved=move p;await payload_io(p);}',
		'released-payload': 'async void bad(owned LinuxPayload p)throws Error{release p;await payload_io(p);}',
		'wrong-provider': 'async void bad(owned LinuxPayload p)throws Error{await payload_io(p);}',
	}
	for name, body in negatives.items():
		source = output/f'negative-{name}.astra'; source.write_text(body+'int main(){return 0;}')
		selected = libs if name != 'wrong-provider' else [p for p in libs if p.name != 'linux.astra'] + [ROOT/'lib/astra/async/virtual.astra']
		rejected = run('negative-'+name, [compiler, '--check', '--vapi', ROOT/'lib/bindings/async/payload.vapi', *selected, source], 1)
		assert b'payload' in rejected.stderr.lower() or b'owns' in rejected.stderr.lower() or b'moved' in rejected.stderr.lower() or b'released' in rejected.stderr.lower()
	print(f'payload qualification PASS: {len(records)} commands, {len(products)} public products', flush=True)
	receipt['status'] = 'PASS'
	save()
	return 0


if __name__ == '__main__':
	sys.exit(main())
