#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current native documentation acceptance, with independent schema assertions."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


class Links(HTMLParser):
	def __init__(self):
		super().__init__()
		self.ids = []
		self.links = []
		self.scripts = []

	def handle_starttag(self, tag, attributes):
		values = dict(attributes)
		if 'id' in values: self.ids.append(values['id'])
		if tag == 'a': self.links.append(values.get('href', ''))
		if tag in ('script', 'iframe', 'img', 'object'): self.scripts.append(tag)
		assert not any(key.startswith('on') for key,value in attributes)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--toolchain', type=Path, required=True)
	p.add_argument('--build-identity', type=Path, required=True)
	a = p.parse_args()
	sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
	assert a.compiler.is_absolute() and sha(a.compiler) == a.compiler_sha256
	a.runtime.mkdir(parents=True, exist_ok=False)
	commands = []
	env = dict(os.environ, LC_ALL='C', PYTHONDONTWRITEBYTECODE='1')
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == h for path,h in toolchain['tools'].items())
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	def run(label, arguments, expected=0, memory=False):
		argv = [a.compiler, 'doc', *arguments]
		if memory: argv = ['valgrind', '--trace-children=yes', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
		start = time.monotonic()
		timing = a.runtime/(label+'.time')
		r = subprocess.run(['/usr/bin/time', '-v', '-o', timing, '--', *map(str, argv)], capture_output=True, cwd=a.runtime, env=env, timeout=180)
		(a.runtime/(label+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(label+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(label=label, argv=list(map(str, argv)), exit=r.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest(), time_sha256=sha(timing)))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (label, r.returncode, r.stderr.decode(errors='replace'))
		if memory: assert all(marker in r.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		return r
	def source(name, text):
		(a.runtime/name).write_bytes(text.encode() if isinstance(text, str) else text)
		return name
	main = source('main.astra', '''language astra27b;
/// Adds two values. See {@link answer}.
/// @param first The first value.
/// @param last The second value.
/// @return Their sum.
int add(int first, int last) { return first + last; }
/// Produces the answer. UTF-8: café 日本語.
/// <script>alert("unsafe")</script>
/// @return The answer.
int answer() { return add(20, 22); }
''')
	other = source('types.astra', '''language astra27b;
/// An explicitly shared object.
[Shared] class SharedItem {
 private int secret;
 init() { this.secret = 0; }
 /// A public scalar field.
 int value;
}
/// A generic identity.
/// @param value The argument.
/// @return The argument value.
T identity<T>(T value) { return value; }
/// A foreign scalar contract.
/// @param value The C ABI argument.
/// @return The C ABI result.
extern(C) int foreign_value(int value);
class Child { int value; init(int value) { this.value = value; } }
class Holder {
 readonly Child root;
 readonly borrowed Child view;
 init(owned Child incoming) { this.root = move incoming; this.view = this.root; }
}
int inspect(borrowed Child value) { return value.value; }
int consume(owned Child value) { return value.value; }
int observe(weak shared Child value) { return 0; }
''')
	visibility = source('visibility.astra', 'namespace Visibility; internal int hidden() { return 7; }\n')
	run('help', ['--help'])
	run('json-first', ['--format', 'json', '--output', 'first.json', main, other, visibility])
	run('json-shuffled', ['--format', 'json', '--output', 'second.json', visibility, other, main])
	assert (a.runtime/'first.json').read_bytes() == (a.runtime/'second.json').read_bytes()
	doc = json.loads((a.runtime/'first.json').read_text())
	assert doc['format'] == 'astra-api-docs/1' and doc['schema_version'] == 1
	identity = json.loads(a.build_identity.read_text())
	assert identity['fingerprint'] == hashlib.sha256(json.dumps(identity['material'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	assert doc['build'] == dict(kind='source-toolchain-sha256', fingerprint=identity['fingerprint'])
	assert all(row['sha256'] == sha(a.runtime/row['path']) for row in doc['inputs'])
	syms = {row['canonical_name']:row for row in doc['symbols']}
	assert not any(row['canonical_name'].endswith(('hidden', 'secret')) for row in doc['symbols'])
	assert syms['add']['parameters'][0]['name'] == 'first'
	assert syms['add']['type_contract']['arguments'][0]['name'] == 'int'
	assert syms['add']['links'] == [syms['answer']['id']]
	assert syms['foreign_value']['attributes']['foreign_import']
	assert syms['foreign_value']['attributes']['foreign_contract'] == 'checked_C_scalar'
	assert syms['identity']['type_parameters'] == ['T']
	assert syms['identity']['generic_constraints'] == []
	import jsonschema
	jsonschema.Draft202012Validator(json.loads((ROOT/'docs/api/schema.json').read_text())).validate(doc)
	assert syms['SharedItem']['type_contract']['shared']
	assert syms['Holder.root']['type_contract']['ownership'] == 'owned'
	assert syms['Holder.root']['owner'] == syms['Holder']['id']
	assert syms['Holder.view']['type_contract']['ownership'] == 'borrowed_noescape'
	assert syms['inspect']['parameters'][0]['type_contract']['ownership'] == 'borrowed_noescape'
	assert syms['consume']['parameters'][0]['type_contract']['ownership'] == 'owned'
	assert syms['observe']['parameters'][0]['type_contract']['weak']
	assert [row['id'] for row in doc['symbols']] == sorted(row['id'] for row in doc['symbols'])
	assert '/home/' not in (a.runtime/'first.json').read_text()
	run('internal', ['--internal', '--output', 'internal.json', main, other, visibility])
	internal = json.loads((a.runtime/'internal.json').read_text())
	assert any(row['canonical_name'].endswith('hidden') and row['visibility'] == 'internal' for row in internal['symbols'])
	run('html', ['--format', 'html', '--output', 'api.html', main, other, visibility])
	markup = (a.runtime/'api.html').read_text()
	parsed = Links()
	parsed.feed(markup)
	assert not parsed.scripts and len(parsed.ids) == len(set(parsed.ids))
	assert all(link.startswith('#') and link[1:] in parsed.ids for link in parsed.links)
	assert '&lt;script&gt;' in markup and '<script>' not in markup
	run('rebuild', ['--format', 'html', '--output', 'api.html', main, other, visibility])
	assert (a.runtime/'api.html').read_text() == markup
	user_output = a.runtime/'user-output.json'
	user_output.write_bytes(b'USER_OUTPUT\n')
	main_sha = sha(a.runtime/main)
	for label,args in (
		('unknown-option', ['--unknown']),
		('missing-output', [main]),
		('bad-format', ['--format', 'script', '--output', 'never.json', main]),
		('traversal-source', ['--output', 'never.json', '../escape.astra']),
		('absolute-source', ['--output', 'never.json', str(a.runtime/main)]),
		('input-collision', ['--output', main, main]),
		('duplicate-source', ['--output', 'never.json', main, './'+main]),
		('user-output', ['--output', 'user-output.json', main]),
	):
		run(label, args, expected=1)
		assert user_output.read_bytes() == b'USER_OUTPUT\n' and sha(a.runtime/main) == main_sha
		assert not (a.runtime/'never.json').exists()
	(a.runtime/'linked.json').symlink_to(user_output)
	(a.runtime/'linked-parent').symlink_to(a.runtime, target_is_directory=True)
	run('symlink-output', ['--output', 'linked.json', main], expected=1)
	run('symlink-parent', ['--output', 'linked-parent/never.json', main], expected=1)
	assert user_output.read_bytes() == b'USER_OUTPUT\n' and not (a.runtime/'never.json').exists()
	crlf = source('crlf.astra', b'/// UTF-8 caf\xc3\xa9\r\n/// @return Forty-two.\r\nint answer() { return 42; }\r\n')
	run('crlf', ['--output', 'crlf.json', crlf])
	assert json.loads((a.runtime/'crlf.json').read_text())['symbols'][0]['documentation']['markdown'] == 'UTF-8 café\n@return Forty-two.'
	edge_text = '''language astra27b;
// Ordinary trivia.
/* An ordinary block. */
//// An ordinary four-slash comment.
/// A tagged choice.
enum Choice {
 /// The empty case.
 Empty,
 /// Carries a scalar value.
 /// @param value The scalar payload.
 Data(int value)
}
/// A nested API container.
class Container {
 /// A scalar property.
 property int answer { get { return 42; } }
 /// A normal method.
 /// @return Forty-two.
 int read() { return 42; }
}
'''
	edge = source('association.astra', edge_text)
	run('enum-property-association', ['--output', 'association.json', edge])
	edge_rows = {row['canonical_name']:row for row in json.loads((a.runtime/'association.json').read_text())['symbols']}
	assert edge_rows['Choice.Data']['owner'] == edge_rows['Choice']['id']
	assert edge_rows['Choice.Data']['parameters'][0]['type_contract']['name'] == 'int'
	assert edge_rows['Choice.Data']['type_contract'] == {'status':'unproven'}, 'variant declarations have no ordinary checked symbol TypeId; owner and payload contracts remain explicit'
	assert edge_rows['Container.answer']['type_contract']['name'] == 'int'
	assert edge_rows['Container.read']['owner'] == edge_rows['Container']['id']
	for name,comment in [('Choice', '/// A tagged choice.'), ('Choice.Empty', '/// The empty case.'), ('Choice.Data', '/// Carries a scalar value.'), ('Container', '/// A nested API container.'), ('Container.answer', '/// A scalar property.'), ('Container.read', '/// A normal method.')]:
		row = edge_rows[name]
		assert row['documentation']['start'] == edge_text.encode().index(comment.encode())
		assert row['documentation']['markdown'].startswith(comment[4:])
		assert row['source_location']['start'] > row['documentation']['end']
	generic = source('generic-record.astra', 'struct Box<T> { T value; }\nint read_int(Box<int> value) { return value.value; }\nbool read_bool(Box<bool> value) { return value.value; }\nint main() { Box<int> value = { value = 42 }; return read_int(value); }\n')
	run('generic-specializations', ['--output', 'generic-record.json', generic])
	generic_rows = {row['canonical_name']:row for row in json.loads((a.runtime/'generic-record.json').read_text())['symbols']}
	for name,argument in (('read_int', 'int'), ('read_bool', 'bool')):
		contract = generic_rows[name]['parameters'][0]['type_contract']
		assert contract['name'] == 'Box<'+argument+'>' and contract['arguments'][0]['name'] == argument
	privacy = source('privacy.astra', 'int body() { const int implementation_detail = 17; return implementation_detail; }\n')
	for suffix,options in (('public', []), ('internal', ['--internal'])):
		name = 'privacy-'+suffix+'.json'
		run('privacy-'+suffix, [*options, '--output', name, privacy])
		assert not any('implementation_detail' in row['canonical_name'] for row in json.loads((a.runtime/name).read_text())['symbols']), 'function-local constants are not API declarations'
	negative = {
		'eof-stray': ('int main() { return 42; }\n/// No following declaration.\n', b'unattached'),
		'blank': ('/// Wrong association.\n\nint main() { return 42; }', b'unattached'),
		'ordinary-barrier': ('/// Wrong association.\n// barrier\nint main() { return 42; }', b'unattached'),
		'nested-stray': ('int main() {\n/// Wrong association.\nreturn 42;\n}', b'unattached'),
		'missing-result': ('/// Missing result contract.\nint main() { return 42; }', b'@return'),
		'missing-param': ('/// @return Result.\nint once(int value) { return value; }', b'undocumented parameter'),
		'void-result': ('/// @return A forbidden result.\nvoid empty() {}', b'void callable'),
		'duplicate-result': ('/// @return First.\n/// @return Second.\nint main() { return 42; }', b'duplicate @return'),
		'nonthrowing-tag': ('/// @throws Error A nonexistent error channel.\n/// @return Result.\nint main() { return 42; }', b'nonthrowing'),
		'empty-link': ('/// {@link }\n/// @return Result.\nint main() { return 42; }', b'malformed link'),
		'duplicate-param': ('/// @param a first\n/// @param a second\n/// @return result\nint twice(int a) { return a+a; }', b'duplicate @param'),
		'unknown-param': ('/// @param missing text\n/// @return result\nint once(int a) { return a; }', b'@param'),
		'malformed-param': ('/// @parama text\n/// @return result\nint once(int a) { return a; }', b'malformed @param'),
		'malformed-throws': ('/// @throwsError text\n/// @return result\nint once() { return 1; }', b'malformed @throws'),
		'missing-link': ('/// {@link absent}\n/// @return result\nint main() { return 42; }', b'unresolved'),
		'invisible-link': ('namespace Visibility; internal int secret() { return 42; }\n/// {@link Visibility.secret}\n/// @return result\nint main() { return 42; }', b'invisible'),
		'bad-fence': ('/// ```astra name=x mode=run category=freestanding exit=42\n/// int main() { return 42; }\n/// @return result\nint main() { return 42; }', b'fence'),
		'large': ('/// '+('x'*65537)+'\nint main() { return 42; }', b'65536'),
		'nul': (b'/// bad\0comment\nint main() { return 42; }', b'error:'),
		'utf8': (b'/// bad\xffcomment\nint main() { return 42; }', b'error:'),
	}
	for name,(text,diagnostic) in negative.items():
		path = source(name+'.astra', text)
		output = name+'.json'
		(a.runtime/output).write_bytes(b'PRESERVED_SENTINEL\n')
		r = run(name, ['--output', output, path], expected=1)
		assert diagnostic in r.stderr and (a.runtime/output).read_bytes() == b'PRESERVED_SENTINEL\n'
	run('strict-memory', ['--output', 'memory.json', main, other, visibility], memory=True)
	run('negative-memory', ['--output', 'negative-memory.json', 'missing-link.astra'], expected=1, memory=True)
	assert not list(a.runtime.glob('*.o')) and not list(a.runtime.glob('*.ll'))
	assert sha(a.compiler) == a.compiler_sha256
	images = {str(path):sha(path) for path in (a.compiler.with_name(a.compiler.name+'.native'), a.compiler.with_name(a.compiler.name+'.doc')) if path.is_file()}
	result = dict(status='FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS', compiler_sha256=a.compiler_sha256, paired_images=images, build_identity_sha256=sha(a.build_identity), source_sha256=sha(__file__), commands_sha256=sha(a.runtime/'commands.json'), negatives=len(negative), symbols=len(doc['symbols']), scope='Focused current native extraction/render/association/schema/memory; complete normal compiler and example qualification remain separate')
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
