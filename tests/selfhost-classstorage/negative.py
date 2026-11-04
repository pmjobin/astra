#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain real C0 semantic refusals and require pre-emission candidate refusal."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from corpus import C0_REFUSED, PLAIN

ROOT = Path(__file__).resolve().parents[2]
CASES = dict(C0_REFUSED)
CASES.update({
	'Class-use-after-move': PLAIN+'owned Item relay(owned Item value) { return move value; } int main() { var a = new Item(17); var b = relay(move a); return a.value; }',
	'duplicate-Class-owner': PLAIN+'int main() { var a = new Item(17); owned Item b = a; return b.value; }',
	'receiver-consumed-during-call': 'class Item { int value; init(int value) { this.value = value; } int read(int unused) { return this.value; } } int consume(owned Item item) { return 0; } int main() { var a = new Item(17); return a.read(consume(move a)); }',
	'mixed-null-heap-result-origins': PLAIN+'owned Item none() { return null; } owned Item relay(owned Item value) { return move value; } int main() { owned Item empty = none(); var a = relay(move empty); if (a != null) return 1; var b = new Item(17); var c = relay(move b); if (c == null || c.value != 17) return 1; return 0; }',
	'wrong-same-shape-Class-nominal': PLAIN+'class Other { int value; init(int value) { this.value = value; } } int inspect(Item value) { return value.value; } int main() { var other = new Other(17); return inspect(other); }',
	'literal-null-owned-child': PLAIN+'class Parent { owned Item child; init() { this.child = null; } } int main() { var p = new Parent(); return 0; }',
	'borrow-Class-then-consume': PLAIN+'int inspect(Item borrowed_value, owned Item owner) { return borrowed_value.value; } int main() { var a = new Item(17); return inspect(a, move a); }',
})


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('component', 'compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == a.compiler_sha256
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, text in CASES.items():
		source = a.runtime/(name+'.astra'); source.write_text(text+'\n')
		parsed = run([a.compiler, '--parse', source], name+'-parse'); assert parsed.returncode == 0, (name, parsed.stderr)
		oracle = run([a.compiler, '--check', source], name+'-C0'); assert oracle.returncode == 1 and b'error:' in oracle.stderr, (name, oracle.stderr)
		admit = run([a.component, '--classstorage-admit', a.mode, a.build/'unused', source], name+'-admit')
		assert admit.returncode in (1, 3), (name, admit.returncode, admit.stdout[:150], admit.stderr)
		assert any(tag in admit.stdout for tag in (b'CHECKED_ERROR', b'ERROR ', b'DEFER ')), name
		output = a.build/(name+'.o'); output.write_bytes(b'preserved-negative-destination\n'); before = sha(output)
		emit = run([a.component, '--classstorage-emit-obj', a.mode, output, source], name+'-refuse-emission')
		assert emit.returncode == 2 and sha(output) == before, (name, emit.returncode, emit.stderr)
		rows.append(dict(name=name, source=dict(path=str(source), sha256=sha(source)), C0_diagnostic=oracle.stderr.decode(), candidate_exit=admit.returncode, admission_stdout_sha256=hashlib.sha256(admit.stdout).hexdigest(), preserved_destination_sha256=before, result='PASS'))
		(a.runtime/'results.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, a.mode, 'refused; destination preserved', flush=True)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), compiler_sha256=sha(a.compiler), recipe_sha256=sha(__file__), cases=rows), indent=2)+'\n')


if __name__ == '__main__':
	main()
