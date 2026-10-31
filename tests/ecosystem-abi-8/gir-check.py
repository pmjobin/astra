# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Strict installed+fixture GIR import, independent ABI checks, reject/restore."""
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
IMPORTER = ROOT/'tools/gir/import.py'
INSTALLED = Path('/usr/share/gir-1.0/GObject-2.0.gir')


def main(compiler_path, output_path, declaration_mode='legacy'):
	assert declaration_mode in ('legacy', 'policy-attributes')
	policy_attributes = declaration_mode == 'policy-attributes'
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='gir-', dir=output))
	rows = []
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), declaration_mode=declaration_mode, checks=rows)

	def run(command, expected=0, contains=(), stdout=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30 if command[0] == 'llvm-dwarfdump' else 180,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings', DEBUGINFOD_URLS=''))
		text = (p.stdout+p.stderr).decode(errors='replace')
		valid = p.returncode == expected and all(s in text for s in contains) and (stdout is None or p.stdout == stdout)
		rows.append(dict(command=command, expected_exit=expected, exit=p.returncode,
			stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	def importer(fixture=HERE/'AstraFixture-1.0.gir', reverse=False):
		inputs = [INSTALLED, fixture]
		if reverse: inputs.reverse()
		return [sys.executable, IMPORTER, '--profile', HERE/'gir-profile.json', *(['--policy-attributes'] if policy_attributes else []), *[part for path in inputs for part in ('--gir', path)]]

	first, second = out/'first', out/'second'
	run([*importer(), '--output', first])
	run([*importer(reverse=True), '--output', second])
	products = ('bindings.vapi', 'bindings.astra', 'bindings.c', 'contract.json') + (('bindings.h',) if policy_attributes else ())
	for name in products:
		assert (first/name).read_bytes() == (second/name).read_bytes(), name
	run([*importer(), '--verify', first])
	flags = shlex.split(run(['pkg-config', '--cflags', 'gobject-2.0']).decode())
	run(['pkg-config', '--libs', 'gobject-2.0'])
	sources = [LIB/'gobject.c', LIB/'retained.c', LIB/'gobject-signals.c', HERE/'counter.c']
	objects = []
	for source in sources:
		product = out/(source.stem+'.o')
		run(['/usr/bin/clang', '-std=c11', '-g', '-gdwarf-4', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), '-I'+str(HERE), *flags, '-c', source, '-o', product])
		objects.append(product)

	def c_binding(directory, expected=0, contains=()):
		product = directory/'bindings.o'
		run(['/usr/bin/clang', '-std=c11', '-g', '-gdwarf-4', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(LIB), '-I'+str(HERE), '-I'+str(first), *flags, '-c', directory/'bindings.c', '-o', product], expected, contains)
		return product

	bindings = c_binding(first)
	# Exact package release must match the actual compile headers and runtime.
	version = json.loads((first/'contract.json').read_text())['packages']['gobject-2.0']
	micro = int(version.split('.')[2])
	header_mismatch = out/'header-version'; header_mismatch.mkdir()
	header_text = (first/'bindings.c').read_text().replace(f'GLIB_MICRO_VERSION == {micro}', f'GLIB_MICRO_VERSION == {micro+1}', 1)
	assert header_text != (first/'bindings.c').read_text()
	(header_mismatch/'bindings.c').write_text(header_text)
	c_binding(header_mismatch, expected=1, contains=('GIR selected header version',))
	runtime_mismatch = out/'runtime-version'; runtime_mismatch.mkdir()
	runtime_text = (first/'bindings.c').read_text().replace(f'glib_micro_version != {micro}', f'glib_micro_version != {micro+1}', 1)
	assert runtime_text != (first/'bindings.c').read_text()
	(runtime_mismatch/'bindings.c').write_text(runtime_text)
	version_bindings = c_binding(runtime_mismatch)
	version_admission = out/'version-admission.astra'
	version_admission.write_text('int main() { if (gir_contract_valid() == 0) { return 0; } return 1; }\n')
	version_link = [item for path in [*objects, version_bindings] for item in ('--link-object', path)] + ['--link-library', 'gobject-2.0', '--link-library', 'glib-2.0']
	run([compiler, '--vapi', first/'bindings.vapi', first/'bindings.astra', version_admission, *version_link, '-o', out/'version-admission'])
	run([out/'version-admission'], stdout=b'')
	link = [item for path in [*objects, bindings] for item in ('--link-object', path)] + ['--link-library', 'gobject-2.0', '--link-library', 'glib-2.0']
	for level in (0, 1, 2):
		product = out/f'client-O{level}'
		run([compiler, '-g', f'-O{level}', '--vapi', first/'bindings.vapi', first/'bindings.astra', HERE/'gir-probe.astra', *link, '-o', product])
		run([product], stdout=b'')
		run(['llvm-dwarfdump', '--verify', product], contains=('No errors.',))
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', product],
			contains=('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes', 'ERROR SUMMARY: 0 errors'))
	run(['llvm-dwarfdump', '--debug-info', out/'client-O0'], contains=('bindings.astra', 'gir-probe.astra', 'GObjectObject_unref'))
	run(['nm', '-u', bindings], contains=('g_object_ref', 'ast_counter_read', 'ast_counter_new'))
	fixture = (HERE/'AstraFixture-1.0.gir').read_text()
	mutations = {
		'malformed': fixture[:-20],
		'version': fixture.replace('name="AstraFixture" version="1.0"', 'name="AstraFixture" version="9.0"'),
		'wrong-transfer': fixture.replace('transfer-ownership="full" nullable="1"', 'transfer-ownership="none" nullable="1"', 1),
		'missing-transfer': fixture.replace('transfer-ownership="full" ', '', 1),
		'wrong-ctype': fixture.replace('c:type="AstCounter*"', 'c:type="void*"', 1),
		'wrong-parent': fixture.replace('parent="GObject.Object"', 'parent="GObject.InitiallyUnowned"'),
		'unknown-annotation': fixture.replace('<constructor name="new"', '<constructor mystery="1" name="new"', 1),
		'varargs': fixture.replace('<type name="gint" c:type="gint"/>', '<varargs/>', 1),
		'union': fixture.replace('name="gint" c:type="gint"', 'name="UnsupportedUnion" c:type="union Unsupported*"', 1),
		'callback': fixture.replace('<type name="gint" c:type="gint"/>', '<callback name="unsupported"/>', 1),
		'foreign-bool': fixture.replace('name="gint" c:type="gint"', 'name="gboolean" c:type="gboolean"', 1),
		'nullable-conflict': fixture.replace('nullable="1"', 'nullable="1" allow-none="0"', 1),
		'duplicate-symbol': fixture.replace('c:identifier="ast_counter_write"', 'c:identifier="ast_counter_read"'),
		'property-transfer': fixture.replace('writable="1" transfer-ownership="none"', 'writable="1" transfer-ownership="full"', 1),
		'entity': fixture.replace('<repository', '<!DOCTYPE repository [<!ENTITY x SYSTEM "file:///nonexistent">]><repository', 1),
	}
	for name, text in mutations.items():
		path = out/(name+'.gir'); path.write_text(text)
		run([*importer(path), '--output', out/(name+'-output')], expected=1, contains=(str(path)+':', 'error:'))

	for name in products:
		path = first/name
		original = path.read_bytes(); path.write_bytes(original+b'corrupted\n')
		run([*importer(), '--verify', first], expected=1, contains=('drift',))
		path.write_bytes(original)
		run([*importer(), '--verify', first])

	wrong_symbol = out/'wrong-symbol.gir'
	wrong_symbol.write_text(fixture.replace('c:identifier="ast_counter_read"', 'c:identifier="counter_new"'))
	wrong = out/'wrong-symbol-output'
	run([*importer(wrong_symbol), '--output', wrong])
	c_binding(wrong, expected=1, contains=('GIR function ABI',))

	wrong_property = out/'wrong-property.gir'
	wrong_property.write_text(fixture.replace('<property name="value" readable="1" writable="1" transfer-ownership="none"><type name="gint"/>', '<property name="value" readable="1" writable="1" transfer-ownership="none"><type name="utf8"/>'))
	wrong = out/'wrong-property-output'
	run([*importer(wrong_property), '--output', wrong])
	wrong_bindings = c_binding(wrong)
	admission = out/'admission.astra'
	admission.write_text('int main() { if (gir_contract_valid() == 0) { return 0; } return 1; }\n')
	wrong_link = [item for path in [*objects, wrong_bindings] for item in ('--link-object', path)] + ['--link-library', 'gobject-2.0', '--link-library', 'glib-2.0']
	run([compiler, '--vapi', wrong/'bindings.vapi', wrong/'bindings.astra', admission, *wrong_link, '-o', out/'admission'])
	run([out/'admission'], stdout=b'')

	changed = out/'changed-identity.gir'; changed.write_text(fixture+'\n<!-- distinct input identity -->\n')
	changed_dir = out/'changed-identity'
	run([*importer(changed), '--output', changed_dir])
	run([compiler, '--vapi', changed_dir/'bindings.vapi', changed_dir/'bindings.astra', HERE/'gir-probe.astra', *link, '-o', out/'stale-object'], expected=1, contains=('undefined reference',))
	run([*importer(), '--verify', first])
	run([out/'client-O2'], stdout=b'')
	receipt['sources'] = {str(p): sha(p) for p in [IMPORTER, INSTALLED, HERE/'AstraFixture-1.0.gir', HERE/'gir-profile.json', HERE/'gir-probe.astra', *sources]}
	receipt['products'] = {str(p.relative_to(out)): sha(p) for p in [*objects, bindings, *first.glob('bindings.*'), first/'contract.json', *out.glob('client-*')]}
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: deterministic typed GIR, real Astra O0/O1/O2, strict ABI/reflection and rejection/restoration; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
