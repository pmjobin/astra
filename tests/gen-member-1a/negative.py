# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check genuine refusals and approved historical positives with actual ownership."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BAG = ROOT / 'lib/astra/collections/bag.astra'
PREFIX = '''class Item{int value;init(int value){this.value=value;}}
class Other{init(){}}
bool read(Item item,int value){return item.value==value;}
bool inspect(Bag<Item> bag,int index,int value){return read(bag.entries[index],value);}
'''
SETUP = 'var bag=new Bag<Item>();if(!bag.reserve(2)){return 81;}var item=new Item(1);'
POPULATED = SETUP + 'bag.append(move item);'
STAGES = ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	cases = []
	def case(name, body='', diagnostic='', phase='semantics', extra='', template=None, vapi=False):
		cases.append((name, PREFIX + extra + 'int main(){' + body + 'return 0;}\n', diagnostic, phase, template, vapi))
	case('wrong-element', SETUP + 'var other=new Other();bag.append(move other);', 'exact')
	case('wrong-bag', 'var bag=new Bag<Item>();take(bag);', 'type', extra='void take(Bag<Other> bag){}')
	case('wrong-inspect', SETUP + 'bag.append(move item);wrong(bag.entries[0]);', 'exact-Class borrowed inspection', extra='void wrong(Other item){}')
	case('value-argument', 'var bag=new Bag<int>();', 'concrete nongeneric native Class')
	case('struct-argument', 'var bag=new Bag<Value>();', 'concrete nongeneric native Class', extra='struct Value{int x;}')
	case('resource-argument', 'var bag=new Bag<R>();', 'concrete nongeneric native Class', vapi=True)
	case('polymorphic-argument', 'var bag=new Bag<Item>();', 'nonpolymorphic', extra='class Child:Item{init():base(1){}}')
	case('virtual-argument', 'var bag=new Bag<Virtual>();', 'nonpolymorphic', extra='class Virtual{init(){}virtual int tag(){return 1;}}')
	case('nested-argument', 'var bag=new Bag<Bag<Item>>();', 'concrete nongeneric native Class')
	case('nested-child-slots', 'var store=new Store();if(!store.entries.reserve(1)){return 81;}var item=new Item(1);store.entries.append(move item);var parent=new Parent(move store);var bag=new Bag<Parent>();if(!bag.reserve(1)){return 82;}bag.append(move parent);if(bag.count()!=1||!inspect_parent(bag.entries[0])){return 83;}', phase='positive', extra='class Store{owned Item[slots] entries;init(){this.entries=new Item[slots];}}class Parent{owned Store child;init(owned Store child){this.child=move child;}}bool inspect_parent(Parent parent){return len(parent.child.entries)==1&&read(parent.child.entries[0],1);}')
	case('generic-bag-child', POPULATED + 'var parent=new Parent(move bag);if(parent.child.count()!=1||!inspect(parent.child,0,1)){return 82;}', phase='positive', extra='class Parent{owned Bag<Item> child;init(owned Bag<Item> child){this.child=move child;}}')
	case('open-argument', diagnostic='ExactHeapClass requires a concrete nongeneric native Class argument', extra='void f<T>(owned T value) where T:Ownable{var bag=new Bag<T>();}')
	case('lexical-element', 'var bag=new Bag<Item>();owned Item item=Item.init(1);bag.append(move item);', 'incompatible heap and lexical')
	case('lexical-bag', 'owned Bag<Item> bag=Bag<Item>.init();', phase='positive')
	case('caller-backed-element', 'var bag=new Bag<Item>();var item=make();bag.append(move item);', 'incompatible', extra='owned Item make(){owned Item item=Item.init(1);return move item;}')
	case('borrowed-element', diagnostic='owned', extra='void bad(Bag<Item> bag,Item item){bag.append(move item);}')
	case('copy-element', SETUP + 'bag.append(item);', 'move')
	case('duplicate-move', SETUP + 'bag.append(move item);bag.append(move item);', 'moved', 'cfg')
	case('conditional-move', SETUP + 'var send=true;if(send){bag.append(move item);}bag.append(move item);', 'moved', 'cfg')
	case('use-after-move', SETUP + 'bag.append(move item);return item.value;', 'moved', 'cfg')
	case('double-destroy', 'var bag=new Bag<Item>();release bag;release bag;', 'released', 'cfg')
	case('moved-bag-use', 'var bag=new Bag<Item>();owned Bag<Item> moved=move bag;return bag.count();', 'moved', 'cfg')
	case('borrow-escape', SETUP + 'bag.append(move item);Item escaped=bag.entries[0];', 'direct exact-Class borrowed inspection')
	case('borrow-return', diagnostic='direct exact-Class borrowed inspection', extra='owned Item bad(Bag<Item> bag){var escaped=bag.entries[0];return move escaped;}')
	case('borrow-reserve', SETUP + 'bag.append(move item);use(bag.entries[0],bag.reserve(3));', 'overlaps', extra='void use(Item item,bool changed){}')
	case('borrow-later-append', SETUP + 'bag.append(move item);var next=new Item(2);use(bag.entries[0],change(bag,move next));', 'overlaps', extra='void use(Item item,int changed){}int change(Bag<Item> bag,owned Item value){bag.append(move value);return 0;}')
	case('borrow-container-alias', SETUP + 'bag.append(move item);use(bag.entries[0],bag);', 'overlaps', extra='void use(Item item,Bag<Item> alias){}')
	case('descriptor-copy', 'var bag=new Bag<Item>();var copied=bag.entries;', 'descriptor is field-only')
	case('descriptor-replace', 'var bag=new Bag<Item>();bag.entries=new Item[slots];', 'one exact empty initialization')
	case('index-type', 'var bag=new Bag<Item>();read(bag.entries[true],1);', 'index requires int/i32')
	case('capacity-type', 'var bag=new Bag<Item>();if(bag.reserve(true)){return 81;}', 'type')
	case('owned-bag-helper', POPULATED + 'if(bag.count()!=1||!inspect(bag,0,1)){return 82;}take(move bag);', phase='positive', extra='void take(owned Bag<Item> bag){}')
	case('bag-result', 'var bag=make();if(!bag.reserve(1)){return 81;}var item=new Item(1);bag.append(move item);if(bag.count()!=1||!inspect(bag,0,1)){return 82;}', phase='positive', extra='owned Bag<Item> make(){var bag=new Bag<Item>();return move bag;}')
	case('generic-free-function', 'var bag=new Bag<Item>();loan<Bag<Item>>(bag);', phase='positive', extra='void loan<T>(borrowed T item) where T:Ownable{}')
	case('generic-helper-formal', POPULATED + 'if(bad<int>(bag,42)!=1||bad<bool>(bag,true)!=1||!inspect(bag,0,1)){return 82;}', phase='positive', extra='int bad<T>(Bag<Item> bag,T value){return bag.count();}')
	case('pointer-result-helper', POPULATED + 'if(bad(bag)!=null||!inspect(bag,0,1)){return 82;}', phase='positive', extra='void* bad(Bag<Item> bag){return null;}')
	text = BAG.read_text()
	case('wrong-definition', 'var bag=new Bag<Item>();take(bag);', 'type', extra=text.replace('class Bag<T>', 'class Crate<T>')+'void take(Crate<Item> bag){}')
	for name, replacement, diagnostic in [
		('underinitialized', '', 'not definitely initialized'), ('duplicate-init', 'this.entries = new T[slots]; this.entries = new T[slots];', 'one exact empty initialization')]:
		case(name, diagnostic=diagnostic, template=text.replace('this.entries = new T[slots];', replacement))
	for name, replacement, diagnostic in [
		('unqualified-field', 'T entries;', 'unqualified object-reference fields'), ('unowned-field', 'T[slots] entries;', 'owned native Class field'),
		('second-field', 'owned T[slots] entries; int extra;', 'not definitely initialized')]:
		case(name, diagnostic=diagnostic, template=text.replace('owned T[slots] entries;', replacement))
	case('unsupported-member-body', POPULATED + 'if(bag.count()!=0||!inspect(bag,0,1)){return 82;}', phase='positive', template=text.replace('return len(this.entries);', 'return 0;'))
	case('async-member', diagnostic='async methods', phase='syntax', template=text.replace('bool reserve(', 'async bool reserve('))
	case('throwing-member', diagnostic="unknown type 'RuntimeError'", template=text.replace('bool reserve(int requested)', 'bool reserve(int requested) throws RuntimeError'))
	case('property', SETUP + 'if(bag.count!=0){return 82;}bag.append(move item);if(bag.count!=1||!inspect(bag,0,1)){return 83;}', phase='positive', template=text.replace('int count() { return len(this.entries); }', 'property int count { get { return len(this.entries); } }'))
	case('generic-method', POPULATED + 'if(bag.count<int>()!=1||bag.count<bool>()!=1||!inspect(bag,0,1)){return 82;}', phase='positive', template=text.replace('int count()', 'int count<U>()'))
	case('inheritance', diagnostic='nonpolymorphic', template=text.replace('ExactHeapClass {', 'ExactHeapClass : Item {'))
	case('deinit', POPULATED + 'if(bag.count()!=1||!inspect(bag,0,1)){return 82;}', phase='positive', template=text.replace('\n}', '\n\tdeinit() {}\n}'))
	case('bad-constraint', POPULATED + 'if(bag.count()!=1||!inspect(bag,0,1)){return 82;}', phase='positive', template=text.replace('ExactHeapClass', 'Ownable'))
	rows = []
	compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
	def positive(command, name, stage, memory=False, dump=False):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == 0 and (dump or not p.stdout)
		if memory:
			valid &= all(s in p.stderr for s in ['ERROR SUMMARY: 0 errors', 'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
		else:
			valid &= not p.stderr
		rows.append(dict(name=name, stage=stage, command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, memory=memory, passed=bool(valid)))
		(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
	for name, source, diagnostic, phase, template, vapi in cases:
		path = out / (name + '.astra'); path.write_text(source)
		bag = BAG
		if template is not None:
			bag = out / (name + '-bag.astra'); bag.write_text(template)
		inputs = [path, bag]
		if phase == 'positive':
			for stage in STAGES:
				positive([compiler, '--dump-' + stage, *inputs], name, stage, dump=True)
			for level in ['O0', 'O1', 'O2']:
				binary = out / (name + '-' + level)
				positive([compiler, '-' + level, *inputs, '-o', binary], name, level + '-compile')
				positive([binary], name, level + '-execute')
				positive(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], name, level + '-memory', memory=True)
			continue
		binary = out / (name + '-invalid')
		for stage in [*STAGES, 'native']:
			rejects = stage == 'native' or STAGES.index(stage) >= STAGES.index(phase)
			command = list(map(str, [compiler, *([] if stage == 'native' else ['--dump-' + stage]), *inputs, *(['--vapi', ROOT / 'tests/gen-borrow-1/resources.vapi'] if vapi and stage != 'syntax' else []), *(['-o', binary] if stage == 'native' else [])]))
			p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
			message = p.stderr.partition(': error: ')[2]
			valid = p.returncode == (1 if rejects else 0) and (not p.stdout and diagnostic in message and 'internal error' not in p.stderr.lower() if rejects else not p.stderr) and not binary.exists()
			rows.append(dict(name=name, stage=stage, command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=bool(valid)))
			(out / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
			assert valid, rows[-1]
	assert hashlib.sha256(compiler.read_bytes()).hexdigest() == compiler_hash
	identity = dict(output=str(out), cases=len(cases), commands=len(rows), all_passed=all(r['passed'] for r in rows),
		compiler_sha256=compiler_hash, positive_cases=sum(c[3] == 'positive' for c in cases),
		source_refusals=sum(c[3] != 'positive' for c in cases), memory_runs=sum(r.get('memory', False) for r in rows),
		sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), BAG]})
	(out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	(output / 'current.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(json.dumps(identity, indent=2))


if __name__ == '__main__':
	main(*sys.argv[1:])
