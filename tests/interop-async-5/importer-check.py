#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A40: actual io_uring payload, retained checked events, UTF8/Bag report."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / 'examples/interop-async-5/event-diagnostic-importer.astra'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'base/errors', 'async/linux', 'async/payload', 'text/scalar-format',
	'hosted/text-ops', 'text/utf8-byte-builder', 'text/utf8-message',
	'collections/bag', 'hosted/files', 'hosted/text']]
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full',
	'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']
CASES = {
	'empty': (b'', b'rows=0 rejected=0\n', []),
	'unicode': ('3|café\n-2|warning\n'.encode(), 'rows=2 rejected=0\ncode=3 message=café\ncode=-2 message=warning\n'.encode(), ['event=43:1', 'event=43:2']),
	'retry': (b'1|first\nbad\nx|nope\n2|next\n', b'rows=2 rejected=2\ncode=1 message=first\ncode=2 message=next\n', ['event=43:1', 'event=44:0', 'record requires code|message', 'event=44:0', 'invalid signed decimal', 'event=43:2']),
}

def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main(compiler, output, prefix=None):
	compiler = Path(compiler).resolve(); out = Path(output).resolve()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	prefix = Path(prefix or os.environ.get('ASTRA_LIBURING_PREFIX', Path.home() / '.local/opt/liburing-2.15')).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	receipt = dict(application='A40', source=str(SOURCE.relative_to(ROOT)), source_sha256=sha(SOURCE), compiler_sha256=sha(compiler), records=[], products={}, inputs={}, source_hashes={})
	def save():
		(out / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(name, argv, code=0, stdout=None, stderr=b'', memory=False):
		argv = list(map(str, argv)); start = time.monotonic()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		good = result.returncode == code and (stdout is None or result.stdout == stdout)
		if memory:
			good &= all(x in result.stderr for x in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
			if stderr: good &= stderr in result.stderr
		else:
			good &= result.stderr == stderr
		receipt['records'].append(dict(name=name, argv=argv, exit=result.returncode, expected_exit=code, stdout_hex=result.stdout.hex(), stderr_hex=result.stderr.hex(), passed=bool(good), memory=memory, seconds=time.monotonic()-start))
		save(); assert good, receipt['records'][-1]
		return result
	archive = prefix / 'lib/liburing.a'
	if not (prefix / 'include/liburing.h').is_file() or not archive.is_file():
		receipt['status'] = 'ENVIRONMENT_BLOCKED'; receipt['reason'] = 'existing matching liburing prefix missing'; save()
		print('ENVIRONMENT_BLOCKED A40: matching liburing prefix missing'); return 77
	receipt['liburing'] = {'archive': str(archive), 'sha256': sha(archive), 'header_sha256': sha(prefix / 'include/liburing.h')}
	common = ['-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-I' + str(prefix / 'include'), '-I' + str(ROOT / 'lib/runtime/async')]
	run('real-provider-probe-build', ['gcc', *common, HERE / 'provider-probe.c', archive, '-o', out / 'provider-probe'])
	probe = subprocess.run([str(out / 'provider-probe')], capture_output=True, timeout=15)
	receipt['provider_probe'] = dict(exit=probe.returncode, stdout=probe.stdout.decode(errors='replace'), stderr=probe.stderr.decode(errors='replace'))
	if probe.returncode == 77:
		receipt['status'] = 'ENVIRONMENT_BLOCKED'; save(); print('ENVIRONMENT_BLOCKED A40: real provider probe denied'); return 77
	assert probe.returncode == 0 and json.loads(probe.stdout)['status'] == 'AVAILABLE'
	support = []
	for name, path, defines in [
		('linux', ROOT / 'lib/runtime/async/linux.c', ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL']),
		('virtual', ROOT / 'lib/runtime/async/virtual.c', []),
		('payload-observer', HERE / 'payload-observer.c', []),
		('retained-observer', HERE / 'retained-observer.c', []),
		*[(n, ROOT / ('lib/astra/platform/' + n + '.c'), []) for n in ['args-posix', 'text-posix', 'text-ops-posix', 'files-posix']],
	]:
		obj = out / (name + '.o'); run(name + '-build', ['gcc', *common, *defines, '-c', path, '-o', obj]); support.append(obj)
	compilers = ['gcc', 'clang-22' if shutil.which('clang-22') else 'clang']
	assert all(shutil.which(cc) for cc in compilers) and shutil.which('valgrind')
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		result = run('A40-' + stage, [compiler, '--dump-' + stage, SOURCE, *LIBS, '--vapi', ROOT / 'lib/bindings/async/payload.vapi'])
		(out / ('A40-' + stage + '.txt')).write_bytes(result.stdout)
	def check_output(result, data, events, rows, error=False):
		lines = result.stdout.decode().splitlines()
		observed = [line for line in lines if line.startswith('observed target=')]
		receipts = [line for line in lines if line.startswith('payload-receipt ')]
		assert len(receipts) == 1
		counters = re.fullmatch(r'payload-receipt submitted=(\d+) closed=(\d+) scans=0 bytes=0 checksum=0', receipts[0])
		assert counters and int(counters[2]) == 2 and len(observed) == int(counters[1])
		results = []; identities = set()
		for line in observed:
			found = re.fullmatch(r'observed target=(\d+) result=(-?\d+) cancel=(\d+) result=(-?\d+) cancel_seen=0', line)
			assert found and int(found[1]) != 0 and int(found[3]) == int(found[1]) + 1
			assert int(found[1]) not in identities; identities.add(int(found[1])); results.append(int(found[2]))
		assert sum(results) == 2 * len(data) and results.count(0) == 1 and all(n >= 0 for n in results)
		actual_events = [line for line in lines if not line.startswith(('observed target=', 'payload-receipt '))]
		expected = ['event=41:1', f'event=42:{len(data)}', *events]
		if error:
			expected += ['event=47:1', 'event=48:1', 'event=49:0']
		else:
			expected += ['event=45:1', 'event=46:1', 'event=47:1', 'event=48:1', f'event=49:{rows}', 'event=50:1']
		assert actual_events == expected, (actual_events, expected)
	for cc in compilers:
		provider = out / (cc + '-retained.o')
		run(cc + '-retained-provider-build', [cc, *common, '-c', ROOT / 'lib/runtime/interop/retained.c', '-o', provider])
		links = [part for obj in [provider, *support, archive] for part in ['--link-object', obj]]
		for level in [0, 1, 2]:
			binary = out / f'A40-{cc}-O{level}'
			run(binary.name + '-public-build', [compiler, f'-O{level}', SOURCE, *LIBS, '--vapi', ROOT / 'lib/bindings/async/payload.vapi', *links, '-o', binary], stdout=b'')
			receipt['products'][str(binary)] = dict(sha256=sha(binary), bytes=binary.stat().st_size)
			for name, (data, expected, events) in CASES.items():
				source = out / (name + '.input'); source.write_bytes(data)
				spool = out / (binary.name + '-' + name + '.spool'); report = out / (binary.name + '-' + name + '.report')
				result = run(binary.name + '-' + name + '-real', [binary, source, spool, report])
				assert spool.read_bytes() == data and report.read_bytes() == expected
				check_output(result, data, events, 0 if name == 'empty' else 2)
				receipt['inputs'][name] = dict(input_sha256=sha(source), spool_sha256=sha(spool), report_sha256=sha(report), expected_report_hex=expected.hex())
				if level in [0, 2]:
					result = run(binary.name + '-' + name + '-memory', [*VG, binary, source, spool, report], memory=True)
					check_output(result, data, events, 0 if name == 'empty' else 2)
			invalid = out / 'invalid.input'; invalid.write_bytes(b'\xff\n')
			spool = out / (binary.name + '-invalid.spool'); report = out / (binary.name + '-invalid.report')
			result = run(binary.name + '-invalid-UTF8-real', [binary, invalid, spool, report], code=3, stderr=b'invalid UTF-8\n')
			assert spool.read_bytes() == invalid.read_bytes() and not report.exists()
			check_output(result, invalid.read_bytes(), [], 0, error=True)
			if level in [0, 2]:
				result = run(binary.name + '-invalid-UTF8-memory', [*VG, binary, invalid, spool, report], code=3, stderr=b'invalid UTF-8\n', memory=True)
				check_output(result, invalid.read_bytes(), [], 0, error=True)
	for path in [SOURCE, *LIBS, HERE / 'importer-check.py', ROOT / 'lib/runtime/interop/retained.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/bindings/async/payload.vapi']:
		receipt['source_hashes'][str(path.relative_to(ROOT))] = sha(path)
	receipt['status'] = 'PASS'; save()
	print(f'PASS A40 importer: {len(receipt["records"])} commands; actual payload CQEs, owned UTF8/Bag report, retained checked retry, GCC/Clang and unsuppressed Valgrind')
	return 0

if __name__ == '__main__':
	sys.exit(main(*sys.argv[1:]))
