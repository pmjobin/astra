# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owner-slot refusals, approved nested positive and labeled fatal preconditions."""
from pathlib import Path
import hashlib
import json
import os
import resource
import re
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PREFIX = (HERE / 'smoke.astra').read_text().split('int main() {')[0]
SETUP = 'var bag=new Items();if(!bag.reserve(2)){return 81;}var entry=new Item(10);'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, expected=0, diagnostic=None, save=None, memory=False):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected
		if memory:
			valid &= not p.stdout and all(s in p.stderr for s in ['ERROR SUMMARY: 0 errors', 'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		elif diagnostic:
			valid &= diagnostic in p.stderr and not p.stdout and 'internal error' not in p.stderr.lower()
		else:
			valid &= not p.stderr
		if save is not None:
			save.write_text(p.stdout)
		rows.append(dict(command=command, expected=expected, actual=p.returncode, stdout=p.stdout, stderr=p.stderr, memory=memory, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]

	cases = []
	def case(name, body, diagnostic, phase='semantics', extra='', prefix=PREFIX):
		cases.append((name, prefix + extra + 'int main(){' + body + 'return 0;}\n', diagnostic, phase))
	case('duplicate-input', SETUP + 'bag.entries.append(move entry);bag.entries.append(move entry);', 'moved', 'cfg')
	case('use-after-append', SETUP + 'bag.entries.append(move entry);return entry.value;', 'moved', 'cfg')
	case('release-after-append', SETUP + 'bag.entries.append(move entry);release entry;', 'moved', 'cfg')
	case('borrowed-input', 'var bag=new Items();', 'owned', extra='void illegal(Items bag,Item entry){bag.entries.append(move entry);}')
	case('input-copy', SETUP + 'bag.entries.append(entry);', 'append(move exact_heap_owner)')
	case('wrong-class', 'var bag=new Items();var value=new Other();bag.entries.append(move value);', 'exact heap ClassType', extra='class Other{init(){}}')
	case('lexical-input', 'var bag=new Items();owned Item value=Item.init(10);bag.entries.append(move value);', 'heap ClassType')
	case('lexical-wrapper', 'var bag=new Items();owned Item value=Item.init(10);bag.append(move value);', 'incompatible heap and lexical')
	case('store-parameter', '', 'admitted only as owned native Class fields', extra='void illegal(Item[slots] entries){}')
	case('store-result', '', 'admitted only as owned native Class fields', extra='Item[slots] illegal(){return null;}')
	case('descriptor-copy', 'var bag=new Items();var copied=bag.entries;', 'descriptor is field-only')
	case('element-alias', SETUP + 'bag.append(move entry);Item alias=bag.entries[0];', 'direct exact-Class borrowed inspection')
	case('descriptor-replacement', 'var bag=new Items();bag.entries=new Item[slots];', 'one exact empty initialization')
	case('underinitialized-store', '', 'not definitely initialized', prefix=PREFIX.replace('this.entries = new Item[slots];', ''))
	case('twice-initialized', '', 'one exact empty initialization', prefix=PREFIX.replace('this.entries = new Item[slots];', 'this.entries = new Item[slots];this.entries = new Item[slots];'))
	case('nonclass-element', '', 'invalid array extent', prefix=PREFIX.replace('Item[slots]', 'int[slots]'))
	case('unowned-store', '', 'owned native Class field', prefix=PREFIX.replace('owned Item[slots] entries;', 'Item[slots] entries;'))
	case('two-stores', '', 'not definitely initialized', prefix=PREFIX.replace('owned Item[slots] entries;', 'owned Item[slots] entries;owned Item[slots] other;'))
	case('nested-store', SETUP + 'bag.append(move entry);var nested=new Nested();if(!nested.entries.reserve(1)){return 82;}nested.entries.append(move bag);if(len(nested.entries)!=1||!check_nested(nested.entries[0])){return 83;}', '', phase='positive', extra='class Nested{owned Items[slots] entries;init(){this.entries=new Items[slots];}}bool check_nested(Items bag){return bag.count()==1&&bag.check(0,10);}')
	case('polymorphic-element', '', 'nonpolymorphic', extra='class Child:Item{init():base(1){}}')
	case('bad-index-type', 'var bag=new Items();inspect(bag.entries[true],10);', 'index requires int/i32')
	case('bad-capacity-type', 'var bag=new Items();if(bag.entries.reserve(true)){return 81;}', 'reserve requires int/i32')
	case('loan-release', '', 'owned', extra='void illegal(Item entry){release entry;}')
	case('loan-move', '', 'owned', extra='void take(owned Item entry){}void illegal(Item entry){take(move entry);}')
	case('loan-return-owner', '', 'owned', extra='owned Item illegal(Item entry){return move entry;}')
	case('loan-container-alias', SETUP + 'bag.append(move entry);use(bag.entries[0],bag);', 'overlaps', extra='void use(Item entry,Items bag){}')
	case('loan-reserve', SETUP + 'bag.append(move entry);use(bag.entries[0],bag.entries.reserve(3));', 'overlaps', extra='void use(Item entry,bool reserved){}')
	case('loan-later-mutator', SETUP + 'bag.append(move entry);use(bag.entries[0],change(bag));', 'overlaps', extra='void use(Item entry,int changed){}int change(Items bag){if(bag.reserve(3)){return 1;}return 0;}')
	case('index-invalidates-container', SETUP + 'bag.append(move entry);inspect(bag.entries[invalidate(move bag)],10);', 'overlaps', extra='class Kept{owned Items child;init(owned Items child){this.child=move child;}}int invalidate(owned Items bag){var kept=new Kept(move bag);return 0;}')
	case('loan-ancestor-alias', '', 'overlaps', extra='class Parent{owned Items bag;init(owned Items bag){this.bag=move bag;}}void use(Item entry,Parent parent){}void illegal(Items bag,Parent parent){use(bag.entries[0],parent);}')
	case('loan-source-text-extent', 'var message=new Label("x");var bag=new Labels();{var view=message.text;bag.entries.append(move message);}', 'stored text loan', prefix='class Label{readonly string snapshot;init(string text){this.snapshot=text;}property string text{get{return this.snapshot;}}}class Labels{owned Label[slots] entries;init(){this.entries=new Label[slots];}}')

	stages = ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	for name, text, diagnostic, phase in cases:
		source = out / (name + '.astra'); source.write_text(text)
		if phase == 'positive':
			for stage in stages:
				run([compiler, '--dump-' + stage, source], save=out / (name + '.' + stage))
			for level in ['O0', 'O1', 'O2']:
				binary = out / (name + '-' + level)
				run([compiler, '-' + level, source, '-o', binary])
				run([binary]); assert not rows[-1]['stdout']
				run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], memory=True)
			continue
		first = stages.index(phase)
		for n, stage in enumerate(stages):
			run([compiler, '--dump-' + stage, source], expected=1 if n >= first else 0, diagnostic=diagnostic if n >= first else None, save=None if n >= first else out / (name + '.' + stage))
		binary = out / (name + '-invalid')
		run([compiler, source, '-o', binary], expected=1, diagnostic=diagnostic)
		assert not binary.exists()

	fatal_cases = {
		'empty-index': 'var bag=new Items();if(bag.check(0,10)){return 81;}',
		'negative-index': SETUP + 'bag.append(move entry);if(bag.check(-1,10)){return 81;}',
		'index-at-length': SETUP + 'bag.append(move entry);if(bag.check(1,10)){return 81;}',
		'full-append': SETUP + 'bag.append(move entry);var other=new Item(20);bag.append(move other);var third=new Item(30);bag.append(move third);',
		'zero-capacity-append': 'var bag=new Items();var entry=new Item(10);bag.append(move entry);',
		'null-heap-result': 'var bag=new Items();if(!bag.reserve(2)){return 81;}var entry=maybe(false);bag.append(move entry);',
	}
	for name, body in fatal_cases.items():
		source = out / (name + '.astra')
		extra = 'owned Item maybe(bool present){if(present){var entry=new Item(10);return move entry;}return null;}' if name == 'null-heap-result' else ''
		source.write_text(PREFIX + extra + 'int main(){' + body + 'return 0;}\n')
		native, ir, optimized, obj, o2 = [out / (name + suffix) for suffix in ['', '.ll', '-O2.ll', '-O2.o', '-O2']]
		run([compiler, source, '-o', native])
		# No hosted arguments: recover the actual main ordinal from its SSA dump.
		ssa = subprocess.check_output([compiler, '--dump-ssa', source], cwd=ROOT, text=True)
		ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		text = subprocess.check_output([compiler, '--dump-llvm', source], cwd=ROOT, text=True)
		ir.write_text(text + '\ndefine i32 @main(){\n %r=call fastcc i32 @astra.fn.' + ordinal + '()\n ret i32 %r\n}\n')
		run(['opt', '-passes=verify', '-disable-output', ir])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, '-o', o2])
		for executable in [native, o2]:
			run([executable], expected=-signal.SIGILL)
			assert not rows[-1]['stdout']
	identity = dict(output=str(out), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
		commands=len(rows), source_refusals=sum(c[3] != 'positive' for c in cases), positive_cases=sum(c[3] == 'positive' for c in cases),
		memory_runs=sum(r['memory'] for r in rows), fatal_cases=len(fatal_cases), all_passed=all(r['passed'] for r in rows),
		sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), HERE / 'smoke.astra']})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(json.dumps(identity, indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
