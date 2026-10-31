# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh refusal controls and separately labeled unresolved S1/S2 prototypes."""
from pathlib import Path
import hashlib
import json
import resource
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BAG = ROOT/'lib/astra/collections/bag.astra'
ARENA = ROOT/'lib/astra/memory/byte-arena.astra'
ERROR = ROOT/'lib/astra/base/errors.astra'
TYPES = 'class Item {int tag;init(int tag){this.tag=tag;}} class Other {init(){}}\n'
SETUP = 'var bag=new Bag<Item>();bag.reserve(2);var first=new Item(1);bag.append(move first);'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output)); rows = []
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	def refuse(name, body, extra='', includes=None, fragment=None, phase='semantics'):
		source = out/(name+'.astra')
		source.write_text(TYPES+extra+'\nint main(){'+body+'return 0;}\n')
		for stage in (['--dump-semantics', '--check'] if phase == 'semantics' else ['--dump-cfg', '--check']):
			command = [compiler, stage, source, *(includes or [BAG])]
			p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=40)
			valid = p.returncode == 1 and not p.stdout and b'internal' not in p.stderr.lower() and b'error:' in p.stderr and (fragment is None or fragment.encode() in p.stderr)
			rows.append(dict(name=name, command=list(map(str, command)), actual=p.returncode,
				stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), expected_exit=1, passed=valid))
			(out/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
			assert valid, rows[-1]
	refuse('take-discard', SETUP+'bag.entries.take(0);')
	refuse('take-inline', SETUP+'consume(bag.entries.take(0));', 'void consume(owned Item value){}')
	refuse('take-index-bool', SETUP+'var value=bag.entries.take(true);')
	refuse('take-type-arguments', SETUP+'var value=bag.entries.take<int>(0);')
	refuse('take-wrong-destination', SETUP+'owned Other value=bag.entries.take(0);')
	refuse('take-after-release', SETUP+'var value=bag.take(0);release value;inspect(value);', 'int inspect(Item value){return value.tag;}', phase='cfg')
	refuse('take-double-move', SETUP+'var value=bag.take(0);bag.append(move value);bag.append(move value);', phase='cfg')
	refuse('replace-wrong-type', SETUP+'var value=new Other();bag.replace(0,move value);')
	refuse('replace-borrowed', '', 'void invalid(Bag<Item> bag,Item value){bag.replace(0,move value);}')
	refuse('replace-used-owner', SETUP+'var value=new Item(2);bag.replace(0,move value);bag.append(move value);', phase='cfg')
	refuse('take-crosses-loan', SETUP+'use(bag.entries[0],mutate(bag));',
		'int mutate(Bag<Item> bag){var value=bag.take(0);return value.tag;}void use(Item item,int tag){}')
	refuse('replace-crosses-loan', SETUP+'use(bag.entries[0],mutate(bag));',
		'int mutate(Bag<Item> bag){var value=new Item(2);bag.replace(0,move value);return 0;}void use(Item item,int tag){}')
	refuse('slot-loan-escape', '', 'Item invalid(Bag<Item> bag){return bag.entries[0];}')
	for name, body, extra in [
		('arena-private-storage', '', 'u8[] invalid(ByteArena arena){return arena.bytes;}'),
		('arena-borrowed-owner-escape', '', 'owned ByteArena invalid(ByteArena arena){return move arena;}'),
		('arena-used-after-move', 'var arena=byte_arena(8,2);var next=move arena;arena.allocate(1,1);', ''),
		('arena-storage-alias', 'var arena=byte_arena(8,2);var alias=arena;', '')]:
		# Enclose factory/allocate effects to ensure the ownership refusal is the reason.
		refuse(name, 'try{'+body+'}catch(Error error){}', extra, [ARENA, ERROR], phase='cfg' if name == 'arena-used-after-move' else 'semantics')
		# Surge 10 implements this formerly deferred owning-record composition.
	source = HERE/'prototypes/two-owner.astra'
	p = subprocess.run([str(compiler), '--check', str(source)], cwd=ROOT, capture_output=True, timeout=40)
	assert p.returncode == 0 and not p.stdout and not p.stderr
	rows.append(dict(name='two-class-owners', status='ACCEPTED_SURGE10_OWNING_RECORD_FIELDS', source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), actual=p.returncode, stderr=p.stderr.decode()))
	for optimization in ['-O0', '-O1', '-O2']:
		exe = out/('two-class-owners'+optimization)
		command = [str(compiler), optimization, str(source), '-o', str(exe)]
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=40)
		assert p.returncode == 0 and not p.stdout and not p.stderr, p.stderr
		p = subprocess.run([str(exe)], capture_output=True, timeout=10)
		assert p.returncode == 42 and not p.stdout and not p.stderr
		memory_command = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', str(exe)]
		p = subprocess.run(memory_command, capture_output=True, timeout=40)
		assert p.returncode == 42 and not p.stdout and all(marker in p.stderr for marker in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		rows.append(dict(name='two-class-owners'+optimization, status='PASS_NATIVE_AND_VALGRIND', command=command, memory_command=memory_command, actual=p.returncode, expected_exit=42, executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), stderr=p.stderr.decode()))
	lazy = 'class Lazy{init(){}lazy property owned Item content{get{var value=new Item(7);return move value;}}}'
	lazy_setup = 'var holder=new Lazy();'
	refuse('lazy-view-storage', lazy_setup+'var alias=holder.content;', lazy)
	refuse('lazy-owner-alias', lazy_setup+'owned Item alias=holder.content;', lazy)
	refuse('lazy-return-escape', '', lazy+'owned Item escape(Lazy holder){return holder.content;}')
	refuse('lazy-transfer-during-loan', lazy_setup+'use(holder.content,move holder);', lazy+'void use(Item value,owned Lazy holder){}')
	refuse('lazy-borrow-after-move', lazy_setup+'var moved=move holder;inspect(holder.content);', lazy+'int inspect(Item item){return item.tag;}', phase='cfg')
	refuse('lazy-owner-reset', lazy_setup+'var item=new Item(2);holder.content=move item;', lazy)
	refuse('lazy-direct-factory', lazy_setup+'var alias=holder.__astra_lazy_factory_content();', lazy)
	refuse('lazy-copied-owned-result', '', 'class Invalid{lazy property owned int value{get{return 1;}}}')
	refuse('lazy-polymorphic-result', '', 'class Parent{init(){}virtual int tag(){return 1;}}class Child:Parent{init():base(){}}class Holder{lazy property owned Parent content{get{var value=new Parent();return move value;}}}')
	refuse('lazy-cycle', '', 'class Cycle{init(){}lazy property owned Cycle content{get{var value=new Cycle();return move value;}}}')
	record = 'struct Pair{owned R first;int tag;owned Other second;} '
	pair = 'Pair value={first=make(1),tag=7,second=make_other(2)};'
	imports = ['--vapi', ROOT/'tests/own-field/fixtures/resources.vapi']
	refuse('record-copy', pair+'var copy=value;', record, imports)
	refuse('record-double-move', pair+'var moved=move value;var twice=move value;', record, imports, phase='cfg')
	refuse('record-use-after-move', pair+'var moved=move value;return value.tag;', record, imports, phase='cfg')
	refuse('record-extraction-copy', pair+'owned R first=value.first;', record, imports)
	refuse('record-alias', 'owned R item=make(1);Pair value={first=move item,tag=0,second=make_other(2)};owned R again=move item;', record, imports, phase='cfg')
	refuse('record-wrong-resource', 'Pair value={first=make(1),tag=0,second=make(2)};', record, imports)
	for name, prefix, operation in [
		('empty-take', '', 'var taken=bag.take(0);'),
		('negative-take', 'var value=new Item(1);bag.append(move value);', 'var taken=bag.take(-1);'),
		('past-last-take', 'var value=new Item(1);bag.append(move value);', 'var taken=bag.take(1);'),
		('empty-replace', '', 'var value=new Item(1);bag.replace(0,move value);')]:
		source = out/(name+'.astra'); source.write_text(TYPES+'int main(){var bag=new Bag<Item>();bag.reserve(1);'+prefix+operation+'return 0;}')
		exe = out/name
		p = subprocess.run([str(compiler), '-O2', str(source), str(BAG), '-o', str(exe)], cwd=ROOT, capture_output=True, timeout=40)
		assert p.returncode == 0 and not p.stderr, p.stderr
		p = subprocess.run([str(exe)], cwd=out, capture_output=True, timeout=10)
		assert p.returncode == -signal.SIGILL, (name, p.returncode)
		rows.append(dict(name=name, status='EXPECTED_FATAL_PRECONDITION', actual=p.returncode, expected_exit=-signal.SIGILL, command=[str(exe)], executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
	recursive = out/'recursive-owned-field.astra'
	recursive.write_text('class Seed{init(){}}owned Seed vacant(bool make){if(make){var seed=new Seed();return move seed;}return null;}class Recursive{owned Seed cache;init(){this.cache=vacant(false);}lazy property bool ready{get{if(this.ready){return true;}return false;}}}int main(){var value=new Recursive();if(value.ready){return 81;}return 82;}')
	exe = out/'recursive-owned-field'
	p = subprocess.run([str(compiler), '-O2', str(recursive), '-o', str(exe)], cwd=ROOT, capture_output=True, timeout=40)
	assert p.returncode == 0 and not p.stderr, p.stderr
	p = subprocess.run([str(exe)], cwd=out, capture_output=True, timeout=10)
	assert p.returncode == -signal.SIGILL
	rows.append(dict(name='recursive-owned-field', status='EXPECTED_FATAL_REENTRANCY', actual=p.returncode, expected_exit=-signal.SIGILL, command=[str(exe)], executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), source_sha256=hashlib.sha256(recursive.read_bytes()).hexdigest()))
	recursive = out/'recursive-owning-cache.astra'
	recursive.write_text(TYPES+'class Recursive{init(){}lazy property owned Item content{get{if(this.content!=null){}var item=new Item(1);return move item;}}}int main(){var holder=new Recursive();if(holder.content==null){return 81;}return 82;}')
	exe = out/'recursive-owning-cache'
	p = subprocess.run([str(compiler), '-O2', str(recursive), '-o', str(exe)], cwd=ROOT, capture_output=True, timeout=40)
	assert p.returncode == 0 and not p.stderr, p.stderr
	p = subprocess.run([str(exe)], cwd=out, capture_output=True, timeout=10)
	assert p.returncode == -signal.SIGILL, p.returncode
	rows.append(dict(name='recursive-owning-cache', status='EXPECTED_FATAL_REENTRANCY', actual=p.returncode, expected_exit=-signal.SIGILL, command=[str(exe)], executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), source_sha256=hashlib.sha256(recursive.read_bytes()).hexdigest()))
	(out/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
	print(f'{len(rows)} controls, including the Surge10 owning-record promotion and retained invalid-copy controls; receipts: {out}')

if __name__ == '__main__':
	main(*sys.argv[1:])
