#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep C0 semantic negatives distinct from C0-admitted native deferrals."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from corpus import CASES as POSITIVES, ITEM, RECORD

ROOT = Path(__file__).resolve().parents[2]
CASES = {
	'scalar-slots': (False, 'int main() { var v = new Vector<int>(1); return 0; }'),
	'copy-container-owner': (False, ITEM+'int main() { var a = new Vector<Item>(1); owned Vector<Item> b = a; return b.count(); }'),
	'container-use-after-move': (False, ITEM+'int main() { var a = new Vector<Item>(1); owned Vector<Item> b = move a; return a.count(); }'),
	'copy-element-owner': (False, ITEM+'int main() { var v = new Vector<Item>(1); var a = new Item(3); bool ok = v.append(a); return 0; }'),
	'element-use-after-transfer': (False, ITEM+'int main() { var v = new Vector<Item>(1); var a = new Item(3); bool ok = v.append(move a); return a.get(); }'),
	'duplicate-replacement-transfer': (False, ITEM+'int main() { var v = new Vector<Item>(2); var a = new Item(3); bool ok = v.append(move a); v.replace(0, move a); return 0; }'),
	'wrong-nominal-vector': (False, RECORD+'struct Other { bool flag; f64 weight; int value; } int inspect(Vector<Item> value) { return value.count(); } int main() { var v = new Vector<Other>(1); return inspect(v); }'),
	'wrong-nominal-element': (False, RECORD+'struct Other { bool flag; f64 weight; int value; } int main() { var v = new Vector<Item>(1); Other value = {flag = false, weight = 0.0, value = 3}; bool ok = v.append(value); return 0; }'),
	'lost-constructor-argument': (False, ITEM+'int main() { var v = new Vector<Item>(); return v.count(); }'),
	'wrong-constructor-argument': (False, ITEM+'int main() { var v = new Vector<Item>(true); return v.count(); }'),
	'borrow-then-consume-container': (False, ITEM+'int inspect(Vector<Item> view, owned Vector<Item> owner) { return view.count(); } int main() { var v = new Vector<Item>(1); return inspect(v, move v); }'),
	'consume-receiver-during-method': (False, ITEM+'int consume(owned Vector<Item> owner) { return 2; } int main() { var v = new Vector<Item>(1); bool ok = v.reserve(consume(move v)); return 0; }'),
	'nested-generic-owner-policy': (True, ITEM+'int main() { var v = new Vector<Vector<Item>>(1); return v.count(); }'),
	'constructor-preinitialization-owner-staging': (True, POSITIVES[8][1]+POSITIVES[8][2]),
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	identity = json.loads(a.component.with_suffix('.identity.json').read_text()); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	vector = ROOT/'lib/astra/collections/vector.astra'; commands, rows = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, timeout=120)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, (admitted, text) in CASES.items():
		source = a.runtime/(name+'.astra'); source.write_text(text+'\n'); sources = [vector, source]
		parsed = run([a.compiler, '--parse', *sources], name+'-parse'); assert parsed.returncode == 0, name
		oracle = run([a.compiler, '--check', *sources], name+'-C0'); assert (oracle.returncode == 0) == admitted, (name, oracle.stderr)
		output = a.build/(name+'.o'); output.write_bytes(b'preserved-genclass-refusal-destination\n'); original = sha(output)
		candidate = run([a.component, '--classstorage-admit', a.mode, output, *sources], name+'-candidate')
		writer = run([a.component, '--classstorage-emit-obj', a.mode, output, *sources], name+'-writer')
		assert candidate.returncode != 0 and writer.returncode != 0 and sha(output) == original, name
		assert any(tag in candidate.stdout for tag in (b'CHECKED_ERROR ', b'DEFER ', b'ERROR ')), name
		rows.append(dict(name=name, source_sha256=sha(source), classification='C0_ADMITTED_NATIVE_DEFERRED' if admitted else 'C0_SEMANTIC_NEGATIVE', candidate_exit=candidate.returncode, writer_exit=writer.returncode, destination_preserved=original))
		(a.runtime/'observations.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, rows[-1]['classification'], flush=True)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), cases=rows), indent=2)+'\n')


if __name__ == '__main__':
	main()
