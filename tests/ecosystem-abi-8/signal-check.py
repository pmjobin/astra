# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real GSignal dispatch into Astra closures with foreign quiescence evidence."""
from pathlib import Path
import hashlib
import json
import os
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIB = ROOT/'lib/runtime/interop'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='signal-', dir=output))
	rows = []
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows)

	def run(command, expected=0, contains=(), stdout=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings'))
		text = (p.stdout+p.stderr).decode(errors='replace')
		valid = p.returncode == expected and all(s in text for s in contains) and (stdout is None or p.stdout == stdout)
		rows.append(dict(command=command, expected_exit=expected, exit=p.returncode,
			stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	flags = shlex.split(run(['pkg-config', '--cflags', '--libs', 'gobject-2.0']).decode())
	sources = [LIB/'gobject.c', LIB/'retained.c', LIB/'gobject-signals.c', HERE/'counter.c', HERE/'signal-observer.c']
	objects = []
	for source in sources:
		product = out/(source.stem+'.o')
		run(['/usr/bin/cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), *flags, '-c', source, '-o', product])
		objects.append(product)
	control = out/'control'
	run(['/usr/bin/cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), HERE/'signal-control.c', *objects, *flags, '-o', control])
	control_output = b'GObject signal reentry/disconnect/quiescence/source-order guards PASS\n'
	run([control], stdout=control_output)
	valgrind = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']
	memory_ok = ('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes', 'ERROR SUMMARY: 0 errors')
	run([*valgrind, control], stdout=control_output, contains=memory_ok)
	link = [item for path in objects for item in ('--link-object', str(path))] + ['--link-library', 'gobject-2.0', '--link-library', 'glib-2.0']
	inputs = [(HERE/'signal-probe.astra', [], b'1:0\n2:7\n3:-2\n2:9\n9:2\n'),
		(HERE/'signal-weak-checked.astra', [ROOT/'lib/astra/base/errors.astra'], b'5:-1\n6:40\n7:4\n8:0\n6:100\n')]
	for source, extra, expected in inputs:
		for level in (0, 1, 2):
			product = out/f'{source.stem}-O{level}'
			run([compiler, f'-O{level}', '--vapi', HERE/'counter.vapi', '--vapi', HERE/'signals.vapi', source, *extra, *link, '-o', product])
			run([product], stdout=expected)
			run([*valgrind, product], stdout=expected, contains=memory_ok)
	for sanitizer in ('address', 'undefined'):
		product = out/f'control-{sanitizer}'
		run(['/usr/bin/clang', '-std=c11', '-g', '-O1', f'-fsanitize={sanitizer}', '-fno-sanitize-recover=all', '-fno-omit-frame-pointer',
			'-I'+str(LIB), HERE/'signal-control.c', *sources, *flags, '-o', product])
		run([product], stdout=control_output)
	negative = {
		'wrong-payload': 'class E{init(){}deinit(){}} f64 code(borrowed E e,f64 v){return v;} int main(){var e=new E();var f=closure_bind(move e,code);return retained_register(f,0);}',
		'moved-callback': 'class E{init(){}deinit(){}} int code(borrowed E e,int v){return v;} int main(){var e=new E();var f=closure_bind(move e,code);release f;return retained_dispatch(f,1);}',
		'borrowed-source-owner': 'owned SignalSource escape(borrowed SignalSource source){return move source;} int main(){return 0;}',
	}
	for name, text in negative.items():
		source = out/(name+'.astra'); source.write_text(text+'\n')
		run([compiler, '--check', '--vapi', HERE/'counter.vapi', '--vapi', HERE/'signals.vapi', source], expected=1, contains=('error:',))
	receipt['sources'] = {str(p.relative_to(ROOT)): sha(p) for p in [*sources, HERE/'signal-control.c', HERE/'signals.vapi', *(p[0] for p in inputs)]}
	receipt['products'] = {p.name: sha(p) for p in [*objects, control, *out.glob('*-O?')]}
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: real GObject signals, native closures/weak/errors O0/O1/O2, C controls and memory; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
