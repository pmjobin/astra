# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Eight useful programs: public optimization, independent outputs and lifetimes."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT / 'examples/language-runtime-3'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'text/scalar-format', 'hosted/text-ops', 'hosted/files', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]
NAMES = ['interface-dispatch', 'polymorphic-diagnostics', 'callable-stream-transform',
	'closure-ledger', 'c-record-bridge', 'c-callback-provider',
	'property-replacement', 'composed-event-report']
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full',
	'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	record = dict(compiler_sha256=sha(compiler), commands=[], applications={}, files=[],
		sources={str(p.relative_to(ROOT)): sha(p) for p in [*APPS.glob('*.astra'),
		*LIBS, HERE/'corpus.py', HERE/'corpus-provider.c', HERE/'corpus-client.c']})
	evidence = out/'results.json'

	def run(argv, code=0, stdout=b'', stderr=b'', memory=False):
		argv = list(map(str, argv)); started = time.monotonic()
		process = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		actual_error = process.stderr
		if memory:
			memory_ok = all(part in actual_error for part in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
			actual_error = re.sub(rb'^==\d+==[^\n]*\n', b'', actual_error, flags=re.M)
		else:
			memory_ok = True
		good = (process.returncode == code and (stdout is None or process.stdout == stdout)
			and (stderr is None or actual_error == stderr) and memory_ok)
		record['commands'].append(dict(argv=argv, exit=process.returncode, expected_exit=code,
			stdout_hex=process.stdout.hex(), stderr_hex=process.stderr.hex(), memory=memory,
			expected_stdout_hex=None if stdout is None else stdout.hex(),
			seconds=time.monotonic()-started, passed=good))
		evidence.write_text(json.dumps(record, indent=2)+'\n')
		assert good, (argv, process.returncode, process.stdout, process.stderr[-5000:])
		return process

	providers = []
	for name in ['args', 'text', 'text-ops', 'files']:
		obj = out/(name+'.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
			ROOT/f'lib/astra/platform/{name}-posix.c', '-o', obj])
	observer = out/'corpus-provider.o'; providers.append(observer)
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'corpus-provider.c', '-o', observer])
	links = [part for path in providers for part in ['--link-object', path]]
	products = {}
	for name in NAMES:
		sources = [APPS/(name+'.astra'), APPS/'support.astra', *LIBS]
		if name == 'c-record-bridge': sources.insert(1, APPS/'record-api.astra')
		if name == 'composed-event-report': sources.insert(1, APPS/'event-entry.astra')
		products[name] = []
		for level in ([0, 1, 2] if name in ['interface-dispatch', 'c-callback-provider'] else [0, 2]):
			binary = out/f'{name}-O{level}'
			run([compiler, f'-O{level}', *sources, *links, '-o', binary])
			needed = run(['readelf', '-d', binary], stdout=None).stdout
			assert not any(name in needed for name in [b'libglib', b'libgobject', b'liburing']), needed
			products[name].append(binary)
		record['applications'][name] = dict(sources=[str(p.relative_to(ROOT)) for p in sources],
			products={str(p): dict(sha256=sha(p), bytes=p.stat().st_size) for p in products[name]}, cases=[])

	def exercise(name, args, stdout=b'', code=0, stderr=b'', file_output=None, memory=True):
		record['applications'][name]['cases'].append(dict(args=list(map(str, args)),
			stdout_hex=stdout.hex(), exit=code))
		for binary in products[name]:
			for under_memory in ([False, True] if memory else [False]):
				run([*(VG if under_memory else []), binary, *args], code, stdout, stderr, under_memory)
				if file_output is not None:
					target, expected = file_output
					actual = Path(target).read_bytes()
					assert actual == expected, (name, actual[:200], expected[:200])
					record['files'].append(dict(app=name, target=str(target), sha256=sha(target), bytes=len(actual)))

	for mode, count in [(0, 0), (0, 7), (1, 11)]:
		total = 7*count+count*(count+1)//2 if mode == 0 else 3*count*(count+1)//2
		exercise('interface-dispatch', [mode, count], f'quote={total}\n'.encode(), memory=count != 0)
	exercise('interface-dispatch', [2, 3], code=64)
	exercise('interface-dispatch', ['bad', 3], code=2)
	for count, message in [(0, 'none'), (3, 'café'), (2, 'input')]:
		expected = ''.join(f'{base+line}:{message}\n' for base in [2, 90] for line in range(1, count+1)).encode()
		exercise('polymorphic-diagnostics', [count, message], expected)
	for index, data in enumerate([b'', bytes(range(256))*5, b'a\0\xffz\n'*19]):
		source = out/f'input-{index}.bin'; source.write_bytes(data)
		record['files'].append(dict(input=str(source), bytes=len(data), sha256=sha(source)))
		shift = [0, 17, 255][index]; target = out/f'transform-{index}.bin'
		transformed = bytes((byte+shift)&255 for byte in data)
		exercise('callable-stream-transform', [source, target, shift], f'sum={sum(transformed)}\n'.encode(),
			file_output=(target, transformed))
		for mode in [0, 1]:
			target = out/f'report-{index}-{mode}.txt'
			metric = sum(byte+5 if mode == 0 else byte*3 for byte in data)
			folded = 4*(metric+mode)+6
			report = f'metric={metric}\nfold={folded}\ncalls=4\n'.encode()
			exercise('composed-event-report', [source, target, mode], file_output=(target, report))
	for name in ['callable-stream-transform', 'composed-event-report']:
		target = out/f'{name}-sentinel'; target.write_bytes(b'preserve\n')
		exercise(name, [out/'missing.bin', target, 0], code=2, file_output=(target, b'preserve\n'))
	for count, mode in [(0, 0), (7, 0), (7, 1), (7, 2)]:
		if mode == 2:
			exercise('closure-ledger', [count, mode], code=2, stderr=b'ledger failure\n')
		else:
			end = min(count, 2) if mode == 1 else count
			exercise('closure-ledger', [count, mode], f'total={3*end*(end+1)//2}\n'.encode())
	for price, count in [(0, 0), (17, 53), (1000, 1000)]:
		exercise('c-record-bridge', [price, count], f'shipment={12345678901+price*count}\n'.encode())
	for seed, count, bias in [(-17, 0, 3), (13, 9, -4), (-1000, 1000, 1000)]:
		total = count*(seed+bias)+count*(count-1)//2
		exercise('c-callback-provider', [seed, count, bias], f'fold={total}\ncalls={count}\n'.encode())
	for first, second, mode in [(7, 42, 0), (7, -1, 0), (7, 42, 1)]:
		success = second >= 0 and mode == 0
		exercise('property-replacement', [first, second, mode],
			f'{"revision" if success else "retained"}={second if success else first}\n'.encode(),
			code=0 if success else 2)

		# Public object route has a separately compiled C consumer, with both toolchains.
	record['object_clients'] = {}
	for cc in ['gcc', 'clang']:
		for level in [0, 2]:
			obj = out/f'api-{cc}-O{level}.o'
			run([compiler, f'-O{level}', '-c', APPS/'record-api.astra', '-o', obj])
			binary = out/f'client-{cc}-O{level}'
			run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', HERE/'corpus-client.c', obj, observer, '-o', binary])
			record['object_clients'][f'{cc}-O{level}'] = {
				str(path): dict(sha256=sha(path), bytes=path.stat().st_size) for path in [obj, binary]}
			for price, count in [(17, 53), (0, 0), (1000, 1000)]:
				run([binary, price, count], stdout=f'shipment={12345678901+price*count}\n'.encode())
	record['summary'] = dict(applications=len(NAMES), commands=len(record['commands']),
		memory_runs=sum(x['memory'] for x in record['commands']),
		exact_file_comparisons=sum('target' in item for item in record['files']))
	evidence.write_text(json.dumps(record, indent=2)+'\n')
	print(json.dumps(record['summary']))


if __name__ == '__main__': main(*sys.argv[1:])
