# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact instances and complete executable bodies under a recorded identity map."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = [ROOT / 'lib/astra/base/slices.astra', ROOT / 'lib/astra/base/buffers.astra']
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
HELPERS = 'owned T[] relay<T>(owned T[] values){return move values;}owned T[] make<T>(int count){return new T[count];}void replace<T>(owned T[] values){values=clone_array(values);}'

def run(compiler, stage, path):
	result = subprocess.run([compiler, '--dump-' + stage, *LIBRARIES, path.name], cwd=path.parent, capture_output=True, text=True)
	(path.parent / (path.stem + '.' + stage)).write_text(result.stdout)
	(path.parent / (path.stem + '.' + stage + '.stderr')).write_text(result.stderr)
	assert result.returncode == 0 and not result.stderr, (path, stage, result)
	return result.stdout

def source(explicit):
	def args(value):
		return '<' + value + '>' if explicit else ''
	return 'struct S{int x;f64 y;}struct Box<T>{T value;}' + HELPERS + f'''
owned T[] outer<T>(owned T[] values,T seed){{owned T[] copy=clone_array{args('T')}(values);fill{args('T')}(copy,seed);return relay{args('T')}(move copy);}}
void root(S seed,Box<S> box){{var a=filled_array{args('S')}(2,seed);var b=outer{args('S')}(move a,seed);b=clone_array{args('S')}(b);replace{args('S')}(move b);var c=filled_array{args('Box<S>')}(3,box);var d=relay{args('Box<S>')}(move c);var integers=make<int>(1);var aliases=relay{args('i32')}(move integers);}}
'''

def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	canonical = {}
	rows = []
	for mode in ['explicit', 'inferred']:
		folder = out / mode
		folder.mkdir()
		path = folder / 'input.astra'
		path.write_text(source(mode == 'explicit'))
		for stage in STAGES:
			dump = run(compiler, stage, path)
			if mode == 'explicit':
				canonical[stage] = dump
			else:
				assert dump == canonical[stage], stage
			rows.append(dict(mode=mode, stage=stage, sha256=hashlib.sha256(dump.encode()).hexdigest()))
	parts = ['struct S{int x;f64 y;}', HELPERS]
	pairs = []
	for label, element in [('numeric', 'int'), ('record', 'S')]:
		parts.append(f'''void {label}_fill({element}[] values,{element} value){{var index=0;while(index<len(values)){{values[index]=value;index=index+1;}}}}
owned {element}[] {label}_clone({element}[] source){{owned {element}[] result=new {element}[len(source)];var index=0;while(index<len(source)){{result[index]=source[index];index=index+1;}}return move result;}}
owned {element}[] {label}_filled(int count,{element} value){{owned {element}[] result=new {element}[count];{label}_fill(result,value);return move result;}}
owned {element}[] {label}_relay(owned {element}[] values){{return move values;}}
owned {element}[] {label}_make(int count){{return new {element}[count];}}
void {label}_replace(owned {element}[] values){{values={label}_clone(values);}}
void {label}_root({element} value,int count){{var a=filled_array(count,value);var b=clone_array(a);a=relay(move a);var c=make<{element}>(count);replace(move c);}}
''')
		for suffix, origin in [('fill', 'fill'), ('clone', 'clone_array'), ('filled', 'filled_array'), ('relay', 'relay'), ('make', 'make'), ('replace', 'replace')]:
			pairs.append((label + '_' + suffix, origin, element))
	path = out / 'controls.astra'
	path.write_text('\n'.join(parts))
	ssa = run(compiler, 'ssa', path)
	llvm = run(compiler, 'llvm', path)
	inventory = run(compiler, 'instances', path)
	functions = {name: (ordinal, body) for ordinal, name, body in re.findall(r'\t\(function #(\d+) "([^"]+)"([^\n]*\n[\s\S]*?\n\t\))', ssa)}
	llvm_functions = {ordinal: body for ordinal, body in re.findall(r'define internal fastcc [^\n]* @astra.fn.(\d+)([\s\S]*?\n})', llvm)}
	mapping = []
	for ordinary, origin, element in pairs:
		line = next(line for line in inventory.splitlines() if '(generic-instance #' in line and f'"{origin}") (type-arguments {element})' in line)
		name = 'astra.gen.' + re.search(r'\(origin #(\d+)', line)[1] + '.' + re.search(r'\(generic-instance #(\d+)', line)[1]
		mapping.append(dict(ordinary=ordinary, specialized=name, ordinary_ordinal=functions[ordinary][0], specialized_ordinal=functions[name][0], element=element))
	for row in mapping:
		left, right = functions[row['ordinary']][1], functions[row['specialized']][1]
		left_llvm, right_llvm = llvm_functions[row['ordinary_ordinal']], llvm_functions[row['specialized_ordinal']]
		for identity in mapping:
			right = right.replace(f"#{identity['specialized_ordinal']} \"{identity['specialized']}\"", f"#{identity['ordinary_ordinal']} \"{identity['ordinary']}\"")
			right_llvm = re.sub(r'@astra\.fn\.' + identity['specialized_ordinal'] + r'(?=\()', '@astra.fn.' + identity['ordinary_ordinal'], right_llvm)
		assert left == right, (row, 'SSA', left, right)
		assert left_llvm == right_llvm, (row, 'LLVM', left_llvm, right_llvm)
	(out / 'results.json').write_text(json.dumps(dict(stages=rows, mapping=mapping, rule='Only exact function identities and their call references are mapped; complete raw stages, nominal identities, guards, groups, instructions and payloads are retained.'), indent='\t') + '\n')
	print('16 explicit/inferred stages; 12 independently written monomorphic SSA and LLVM bodies')

if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
