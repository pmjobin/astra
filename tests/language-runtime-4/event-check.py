# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A31: native typed transforms behind a synchronous C event provider."""
from pathlib import Path
import hashlib
import json
import os
import resource
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT / 'examples/language-runtime-4'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'text/scalar-format', 'hosted/text-ops', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	sources = [APPS/'sync-event-bridge.astra', APPS/'event-bridge-api.astra',
		HERE/'event-provider.c', HERE/'event-client.c', Path(__file__).resolve(), *LIBS,
		*[ROOT/f'lib/astra/platform/{name}-posix.c' for name in ['args', 'text', 'text-ops']]]
	receipt = dict(compiler_sha256=sha(compiler), sources={str(p.relative_to(ROOT)): sha(p) for p in sources}, commands=[], products={}, valgrind=0)

	def run(argv, code=0, stdout=b'', memory=False):
		argv = list(map(str, argv))
		started = time.monotonic()
		result = subprocess.run(argv, capture_output=True, cwd=ROOT, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		good = result.returncode == code and (stdout is None or result.stdout == stdout)
		if memory:
			good &= all(part in result.stderr for part in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			good &= not result.stderr
		receipt['commands'].append(dict(argv=argv, exit=result.returncode,
			expected_exit=code, expected_stdout_hex=None if stdout is None else stdout.hex(),
			stdout_hex=result.stdout.hex(), stderr_hex=result.stderr.hex(),
			seconds=time.monotonic()-started, memory=memory, passed=bool(good)))
		(out/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert good, (argv, result.returncode, result.stdout, result.stderr)
		if memory:
			receipt['valgrind'] += 1
		return result.stdout

	vg = ['valgrind', '--default-suppressions=no', '--leak-check=full',
		'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=97']
	c_compilers = ['gcc', 'clang-22' if shutil.which('clang-22') else 'clang']
	receipt['c_compilers'] = {cc: dict(path=shutil.which(cc),
		version=run([cc, '--version'], stdout=None).decode().splitlines()[0]) for cc in c_compilers}
	receipt['compiler_version'] = run([compiler, '--version'], stdout=None).decode().strip()
	platform = []
	for name in ['args', 'text', 'text-ops']:
		obj = out/(name+'-posix.o')
		run([c_compilers[0], '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
			ROOT/f'lib/astra/platform/{name}-posix.c', '-o', obj])
		platform.append(obj)
	links = [part for path in platform for part in ['--link-object', path]]
	for cc in c_compilers:
		provider = out/(cc+'-provider.o')
		run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'event-provider.c', '-o', provider])
		for level in [0, 1, 2]:
			native = out/f'{cc}-O{level}'
			run([compiler, f'-O{level}', *LIBS, APPS/'event-bridge-api.astra', APPS/'sync-event-bridge.astra', *links, '--link-object', provider, '-o', native])
			receipt['products'][native.name] = sha(native)
			for first, count, mode in [(7, 5, 0), (-11, 23, 1), (0, 0, 0)]:
				expected = sum((first+i+3 if mode else 2*(first+i)) for i in range(count))
				data = f'events={count} checksum={expected}\n'.encode()
				run([native, first, count, mode], stdout=data)
				run([*vg, native, first, count, mode], stdout=data, memory=True)
			run([native, 'bad', 1, 0], code=2)
			run([native, 0, -1, 0], code=64)
			run([native, 0, 1, 2], code=64)
			run([native], code=64)
			obj, client = out/f'{cc}-O{level}.o', out/f'{cc}-client-O{level}'
			run([compiler, f'-O{level}', '-c', APPS/'event-bridge-api.astra', '-o', obj])
			run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', HERE/'event-client.c', provider, obj, '-o', client])
			receipt['products'][obj.name], receipt['products'][client.name] = sha(obj), sha(client)
			run([client], stdout=b'event-client: 1400 callback sequences verified\n')
			run([*vg, client], stdout=b'event-client: 1400 callback sequences verified\n', memory=True)
	receipt['status'] = 'PASS'
	(out/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print('A31 synchronous event bridge: PASS')


if __name__ == '__main__':
	main(*sys.argv[1:])
