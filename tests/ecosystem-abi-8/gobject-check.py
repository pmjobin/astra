# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real optional GObject ABI, public Astra ownership, and independent C guards."""
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
	out = Path(tempfile.mkdtemp(prefix='gobject-', dir=output))
	rows = []
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows)

	def run(command, expected=0, contains=(), stdout=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings'))
		text = (p.stdout + p.stderr).decode(errors='replace')
		valid = p.returncode == expected and all(s in text for s in contains) and (stdout is None or p.stdout == stdout)
		rows.append(dict(command=command, expected_exit=expected, exit=p.returncode,
			stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	flags = shlex.split(run(['pkg-config', '--cflags', '--libs', 'gobject-2.0']).decode())
	run(['pkg-config', '--modversion', 'gobject-2.0'])
	sources = [LIB/'gobject.c', HERE/'counter.c']
	objects = []
	for source in sources:
		product = out/(source.stem+'.o')
		run(['/usr/bin/cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), *flags, '-c', source, '-o', product])
		objects.append(product)
	control = out/'control'
	run(['/usr/bin/cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), HERE/'gobject-control.c', *objects, *flags, '-o', control])
	run([control], stdout=b'GObject identity/transfer/property/weak/capacity guards PASS\n')
	link = [item for path in objects for item in ('--link-object', str(path))] + ['--link-library', 'gobject-2.0', '--link-library', 'glib-2.0']
	for level in (0, 1, 2):
		product = out/f'probe-O{level}'
		run([compiler, f'-O{level}', '--vapi', HERE/'counter.vapi', HERE/'gobject-probe.astra', *link, '-o', product])
		run([product], stdout=b'')
		run(['readelf', '-d', product], contains=('libgobject-2.0', 'libglib-2.0'))
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', product],
			contains=('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes', 'ERROR SUMMARY: 0 errors'))
	run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', control],
		contains=('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes', 'ERROR SUMMARY: 0 errors'))
	for sanitizer in ('address', 'undefined'):
		probe = out/'sanitizer-probe.c'
		probe.write_text('int main(void) { return 0; }\n')
		selected = None
		for cc in ('/usr/bin/cc', '/usr/bin/clang'):
			command = [cc, f'-fsanitize={sanitizer}', str(probe), '-o', str(out/'sanitizer-probe')]
			p = subprocess.run(command, capture_output=True, text=True, timeout=60)
			receipt.setdefault('sanitizer_probes', []).append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr))
			if p.returncode == 0:
				run([out/'sanitizer-probe'])
				selected = cc
				break
		if selected is None:
			receipt.setdefault('unavailable_sanitizers', []).append(sanitizer)
			continue
		product = out/f'control-{sanitizer}'
		run([selected, '-std=c11', '-g', '-O1', f'-fsanitize={sanitizer}', '-fno-sanitize-recover=all', '-fno-omit-frame-pointer',
			'-I'+str(LIB), HERE/'gobject-control.c', *sources, *flags, '-o', product])
		run([product], stdout=b'GObject identity/transfer/property/weak/capacity guards PASS\n')

	negative = {
		'native-class-confusion': 'class Local{init(){}deinit(){}} int main(){var x=new Local();return counter_get(x);}',
		'wrong-handle': 'int main(){owned Counter x=counter_new(1);return foreign_text_length(x);}',
		'double-move': 'void take(owned Counter x){} int main(){owned Counter x=counter_new(1);take(move x);take(move x);return 0;}',
		'borrow-escape': 'owned Counter bad(borrowed Counter x){return move x;} int main(){return 0;}',
		'raw-owner': 'int main(){owned Counter x=null;return 0;}',
	}
	for name, text in negative.items():
		source = out/(name+'.astra')
		source.write_text(text+'\n')
		run([compiler, '--check', '--vapi', HERE/'counter.vapi', source], expected=1, contains=('error:',))
	receipt['sources'] = {str(p.relative_to(ROOT)): sha(p) for p in [*sources, LIB/'gobject.h', HERE/'counter.h', HERE/'counter.vapi', HERE/'gobject-probe.astra', HERE/'gobject-control.c']}
	receipt['products'] = {p.name: sha(p) for p in [*objects, control, *out.glob('probe-*')]}
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: GObject native O0/O1/O2, C guards, Valgrind; unavailable sanitizers {receipt.get("unavailable_sanitizers", [])}; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
