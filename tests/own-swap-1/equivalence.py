# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact generic keys and complete concrete/specialized operation correspondence."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
HELPERS = 'owned T[] turn<T>(owned T[] a,owned T[] b){swap(a,b);return move a;}owned T[] outer<T>(owned T[] a,owned T[] b){return turn(move a,move b);}'


def dump(compiler, path, stage):
	result = subprocess.run([compiler, '--dump-' + stage, path.name], cwd=path.parent, capture_output=True)
	(path.parent / (path.stem + '.' + stage)).write_bytes(result.stdout)
	(path.parent / (path.stem + '.' + stage + '.stderr')).write_bytes(result.stderr)
	assert result.returncode == 0 and not result.stderr, (path, stage, result.stderr.decode())
	return result.stdout.decode()


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	canonical, records = {}, []
	for explicit in [True, False]:
		folder = out / ('explicit' if explicit else 'inferred'); folder.mkdir()
		path = folder / 'input.astra'
		parts = ['struct S{int n;f64 x;}struct Box<T>{T item;}', HELPERS]
		for i, element in enumerate(['int', 'S', 'Box<S>']):
			parts.append(f'void root{i}(){{var a=new {element}[2];var b=new {element}[3];var c=outer' + (f'<{element}>' if explicit else '') + '(move a,move b);}')
		parts.append('void alias(){var a=new int[0];var b=new int[0];var c=turn' + ('<i32>' if explicit else '') + '(move a,move b);}')
		path.write_text('\n'.join(parts) + '\n')
		for stage in STAGES:
			text = dump(compiler, path, stage)
			if explicit:
				canonical[stage] = text
			else:
				assert text == canonical[stage], stage
			records.append(dict(mode=folder.name, stage=stage, sha256=hashlib.sha256(text.encode()).hexdigest()))
	path = out / 'controls.astra'
	parts = ['struct S{int n;f64 x;}', HELPERS]
	for label, element in [('numeric', 'int'), ('record', 'S')]:
		parts.append(f'owned {element}[] {label}(owned {element}[] a,owned {element}[] b){{swap(a,b);return move a;}}void root_{label}(){{var a=new {element}[2];var b=new {element}[3];var c=turn(move a,move b);}}')
	path.write_text('\n'.join(parts) + '\n')
	ssa, ir, inventory = [dump(compiler, path, stage) for stage in ['ssa', 'llvm', 'instances']]
	functions = {name: (ordinal, body) for ordinal, name, body in re.findall(r'\t\(function #(\d+) "([^"]+)"([^\n]*\n[\s\S]*?\n\t\))', ssa)}
	llvm = {ordinal: body for ordinal, body in re.findall(r'define internal fastcc [^\n]* @astra.fn.(\d+)([\s\S]*?\n})', ir)}
	mapping = []
	for label, element in [('numeric', 'int'), ('record', 'S')]:
		line = next(line for line in inventory.splitlines() if '(generic-instance #' in line and f'"turn") (type-arguments {element})' in line)
		name = 'astra.gen.' + re.search(r'\(origin #(\d+)', line)[1] + '.' + re.search(r'\(generic-instance #(\d+)', line)[1]
		assert functions[label][1] == functions[name][1]
		assert llvm[functions[label][0]] == llvm[functions[name][0]]
		mapping.append(dict(concrete=label, concrete_ordinal=functions[label][0], specialized=name, specialized_ordinal=functions[name][0], element=element))
	(out / 'results.json').write_text(json.dumps(dict(stages=records, mapping=mapping, rule='Complete function bodies match after selecting the explicitly recorded corresponding function identities. No instruction, nominal type, count, cleanup or guard is normalized.'), indent='\t') + '\n')
	print('16 exact explicit/inferred stages; two concrete/generic complete SSA and LLVM body pairs')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
