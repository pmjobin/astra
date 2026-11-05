#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure private payload layouts from C0 syntax with an independent C++ ABI.

This generates only layout probes. It never emits Astra application bodies or
reads the candidate planner, emitter, LLVM type spelling, or its cached offsets.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def syntax(text):
	tokens = re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text)
	stack, result = [], None
	for token in tokens:
		if token == '(':
			row = []
			if stack: stack[-1].append(row)
			else:
				assert result is None
				result = row
			stack.append(row)
		elif token == ')':
			assert stack
			stack.pop()
		else:
			assert stack
			stack[-1].append(json.loads(token) if token.startswith('"') else token)
	assert not stack and isinstance(result, list)
	return result


def declarations(tree):
	result = {}
	def visit(node):
		if not isinstance(node, list) or not node: return
		if node[0] in ('class', 'struct'):
			name = node[1]
			assert re.fullmatch(r'[A-Za-z_]\w*', name) and name not in result
			fields = []
			for child in node[2:]:
				if isinstance(child, list) and child and child[0] in ('field', 'owned-field', 'readonly-field'):
					parts = {row[0]: row[1] for row in child[1:] if isinstance(row, list) and len(row) == 2}
					assert set(parts) == {'name', 'type'}, parts
					fields.append(dict(name=parts['name'], type=parts['type'], owned=child[0] == 'owned-field'))
			result[name] = dict(kind=node[0], fields=fields)
			return
		if node[0] in ('program', 'source', 'unit'):
			for child in node[1:]: visit(child)
	visit(tree)
	assert result
	return result


def cpp_probe(decls):
	names = {name: 'Payload'+str(i) for i, name in enumerate(decls)}
	primitives = {'int': 'std::int32_t', 'i8': 'std::int8_t', 'u8': 'std::uint8_t', 'i16': 'std::int16_t', 'u16': 'std::uint16_t', 'i32': 'std::int32_t', 'u32': 'std::uint32_t', 'i64': 'std::int64_t', 'u64': 'std::uint64_t', 'f32': 'float', 'f64': 'double', 'bool': 'bool', 'string': 'CountedText'}
	def field_type(field):
		value = field['type'].removeprefix('nonnull ')
		if value.endswith('[slots]'): return 'OwnerSlots'
		if value.endswith('[]'): return 'Buffer'
		if value in primitives: return primitives[value]
		assert value in decls, ('unqualified probe type', value)
		return 'void*' if decls[value]['kind'] == 'class' else names[value]
	lines = ['#include <cstdint>', '#include <cstddef>', '#include <cstdio>', '#include <type_traits>', 'struct Buffer { void* base; std::int32_t length; };', 'struct CountedText { const void* bytes; std::int32_t count; };', 'struct OwnerSlots { void* base; std::int32_t length; std::int32_t capacity; };']
	pending, completed = list(decls), set()
	while pending:
		progress = False
		for name in pending[:]:
			fields = decls[name]['fields']; types = [field_type(field) for field in fields]
			if any(value.startswith('Payload') and value not in completed for value in types): continue
			lines.append('struct '+names[name]+' { '+''.join(value+' f'+str(i)+'; ' for i, value in enumerate(types))+'};')
			completed.add(names[name]); pending.remove(name); progress = True
		assert progress, 'recursive by-value probe input'
	lines += ['int main() {', 'std::printf("TARGET %zu %zu %zu %zu %zu %zu %zu\\n", sizeof(void*), alignof(void*), sizeof(Buffer), alignof(Buffer), sizeof(OwnerSlots), alignof(OwnerSlots), offsetof(OwnerSlots, capacity));']
	for name, row in decls.items():
		payload = names[name]
		lines.append('static_assert(std::is_standard_layout_v<'+payload+'>);')
		lines.append('std::printf('+json.dumps('LAYOUT '+name+' %zu %zu %d\n')+', sizeof('+payload+'), alignof('+payload+'), '+str(len(row['fields']))+');')
		for i, field in enumerate(row['fields']):
			assert re.fullmatch(r'[A-Za-z_]\w*', field['name'])
			lines.append('std::printf('+json.dumps('FIELD '+name+' '+field['name']+' %zu %zu %zu\n')+', offsetof('+payload+', f'+str(i)+'), sizeof((('+payload+'*)nullptr)->f'+str(i)+'), alignof(decltype('+payload+'::f'+str(i)+')));')
	lines += ['return 0;', '}']
	return '\n'.join(lines)+'\n'


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('sources', type=Path, nargs='+')
	a = p.parse_args()
	assert sha(a.compiler) == a.compiler_sha256
	recipe_sha = sha(__file__)
	root = Path(__file__).resolve().parents[2]
	assert all(not path.resolve().is_relative_to(root) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	inputs = {str(path.resolve()): sha(path) for path in a.sources}
	commands = []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, r.stderr.decode(errors='replace')[-2000:]
		return r.stdout
	decls = declarations(syntax(run([a.compiler, '--dump-syntax', *a.sources], 'c0-syntax').decode()))
	cpp = a.build/'layout.cpp'; cpp.write_text(cpp_probe(decls)); binary = a.build/'layout-probe'
	compiler = Path(shutil.which('g++')).resolve()
	actual = compiler
	if compiler.name == 'ccache':
		actual = next((Path(entry)/'g++').resolve() for entry in os.get_exec_path() if (Path(entry)/'g++').is_file() and (Path(entry)/'g++').resolve().name != 'ccache')
	frontend = Path(subprocess.check_output(['g++', '-print-prog-name=cc1plus'], text=True).strip()).resolve(strict=True)
	dependencies = subprocess.check_output(['g++', '-std=c++20', '-M', cpp], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
	tool_inputs = {str(path): sha(path) for path in (compiler, actual, frontend)}
	headers = {path: sha(path) for path in dependencies}
	run(['g++', '-std=c++20', '-O2', '-Wall', '-Wextra', '-Werror', cpp, '-o', binary], 'compile')
	observed = run([binary], 'execute').decode().splitlines()
	assert inputs == {name: sha(name) for name in inputs}
	assert recipe_sha == sha(__file__) and headers == {path: sha(path) for path in headers}
	result = dict(format='astra-classstorage-independent-layout/1', sources=inputs, c0_sha256=sha(a.compiler), c0_syntax_sha256=sha(a.runtime/'c0-syntax.stdout'), cpp_sha256=sha(cpp), executable_sha256=sha(binary), recipe_sha256=recipe_sha, tools=tool_inputs, dependencies=headers, declarations=decls, observations=observed, limitation='Physical layout only; no application, ownership, calling-channel or native emitter PASS follows from this probe.')
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print('\n'.join(observed))


if __name__ == '__main__':
	main()
