# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
	probe, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
	source = Path(__file__).resolve().parents[2]
	assert output.parent.exists()
	output.mkdir(exist_ok=True)
	obj, native = output / 'source-frames.o', output / 'source-frames'
	receipts = []
	prior = output / 'receipts.json'
	if prior.exists():
		history = output / 'receipt-history'
		history.mkdir(exist_ok=True)
		retained = history / (sha(prior) + '.json')
		if not retained.exists():
			retained.write_bytes(prior.read_bytes())
	def run(name, command):
		result = subprocess.run(command, capture_output=True, text=True)
		record = {'name': name, 'command': [str(x) for x in command], 'expected_exit': 0, 'actual_exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr, 'status': 'PASS' if result.returncode == 0 else 'FAIL'}
		if command[0] == 'valgrind':
			errors = re.search(r'ERROR SUMMARY: ([0-9,]+) errors', result.stderr)
			live = re.search(r'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', result.stderr)
			suppressed = re.search(r'\(suppressed: ([0-9,]+) from ([0-9,]+)\)', result.stderr)
			if errors is None or live is None or suppressed is None:
				record['status'] = 'FAIL'
			else:
				record['memory'] = {'errors': int(errors[1].replace(',', '')), 'live_bytes': int(live[1].replace(',', '')), 'live_blocks': int(live[2].replace(',', '')), 'suppressed_errors': int(suppressed[1].replace(',', '')), 'default_suppressions': False}
				if any(record['memory'][key] != 0 for key in ('errors', 'live_bytes', 'live_blocks', 'suppressed_errors')):
					record['status'] = 'FAIL'
		receipts.append(record)
		(output / 'receipts.json').write_text(json.dumps({'probe_sha256': sha(probe), 'source_sha256': {str(p.relative_to(source)): sha(p) for p in (source / 'tests/async-1').iterdir() if p.is_file()}, 'receipts': receipts}, indent='\t') + '\n')
		print(name, record['status'], flush=True)
		if record['status'] != 'PASS':
			print(result.stdout, result.stderr, flush=True)
			return False
		return True
	if not run('compiled-frame-object', [str(probe), '--emit-fixture', str(obj)]):
		return 1
	if not run('strict-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/native-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(obj), '-o', str(native)]):
		return 1
	for value in ('7', '13', '0'):
		if not run('runtime-values-' + value, [str(native), value]):
			return 1
	if not run('unsuppressed-native-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(native), '7']):
		return 1
	await_obj, await_native = output / 'source-await.o', output / 'source-await'
	if not run('compiled-await-object', [str(probe), '--emit-await-fixture', str(await_obj)]):
		return 1
	if not run('strict-await-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/await-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(await_obj), '-o', str(await_native)]):
		return 1
	if not run('source-await-native', [str(await_native)]):
		return 1
	if not run('unsuppressed-await-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(await_native)]):
		return 1
	origin_native = output / 'source-exception-origin'
	if not run('strict-exception-origin-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/exception-origin-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(await_obj), '-Wl,--wrap=calloc,--wrap=free,--wrap=astra_async_complete', '-o', str(origin_native)]):
		return 1
	if not run('source-exception-original-allocation', [str(origin_native)]):
		return 1
	if not run('unsuppressed-exception-origin-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(origin_native)]):
		return 1
	buffer_obj, buffer_native = output / 'source-buffer.o', output / 'source-buffer'
	if not run('compiled-buffer-object', [str(probe), '--emit-buffer-fixture', str(buffer_obj)]):
		return 1
	if not run('strict-buffer-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/buffer-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(buffer_obj), '-o', str(buffer_native)]):
		return 1
	if not run('source-buffer-native', [str(buffer_native)]):
		return 1
	if not run('unsuppressed-buffer-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(buffer_native)]):
		return 1
	resource_obj, resource_native = output / 'source-resource.o', output / 'source-resource'
	if not run('compiled-resource-object', [str(probe), '--emit-resource-fixture', str(resource_obj)]):
		return 1
	if not run('strict-resource-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/resource-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(resource_obj), '-o', str(resource_native)]):
		return 1
	if not run('source-resource-native', [str(resource_native)]):
		return 1
	if not run('unsuppressed-resource-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(resource_native)]):
		return 1
	storage_obj, storage_native = output / 'source-storage.o', output / 'source-storage'
	if not run('compiled-storage-object', [str(probe), '--emit-storage-fixture', str(storage_obj)]):
		return 1
	if not run('strict-storage-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/storage-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(storage_obj), '-o', str(storage_native)]):
		return 1
	if not run('source-storage-native', [str(storage_native)]):
		return 1
	if not run('unsuppressed-storage-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(storage_native)]):
		return 1
	result_obj, result_native = output / 'source-result.o', output / 'source-result'
	if not run('compiled-result-object', [str(probe), '--emit-result-fixture', str(result_obj)]):
		return 1
	if not run('strict-result-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/result-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(result_obj), '-Wl,--wrap=astra_async_new,--wrap=astra_async_delay,--wrap=free', '-o', str(result_native)]):
		return 1
	if not run('source-result-native', [str(result_native)]):
		return 1
	if not run('unsuppressed-result-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(result_native)]):
		return 1
	loan_obj, loan_native = output / 'source-loan.o', output / 'source-loan'
	if not run('compiled-loan-object', [str(probe), '--emit-loan-fixture', str(loan_obj)]):
		return 1
	if not run('strict-loan-native-link', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-I', str(source / 'lib/runtime/async'), str(source / 'tests/async-1/loan-observer.c'), str(source / 'lib/runtime/async/virtual.c'), str(loan_obj), '-Wl,--wrap=astra_async_new,--wrap=astra_async_delay,--wrap=free', '-o', str(loan_native)]):
		return 1
	if not run('source-loan-native', [str(loan_native)]):
		return 1
	if not run('unsuppressed-loan-memory', ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(loan_native)]):
		return 1
	return 0

if __name__ == '__main__':
	sys.exit(main())
