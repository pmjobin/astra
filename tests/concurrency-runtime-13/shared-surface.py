# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Shared owner surface and container cleanup, with an independent destructor oracle."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-shared-surface')
	here = Path(__file__).parent
	oracle = e.output / 'oracle.o'
	e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c',
		here / 'intrinsic-oracle.c', '-o', oracle])
	text = (here / 'intrinsic.astra').read_text()
	text = text.replace('shared_clone(first)', 'first.clone()').replace('shared_downgrade(first)', 'first.downgrade()')
	text = text.replace('weak_upgrade(weak)', 'weak.upgrade()')
	text = text.replace('release first;', 'var transferred = first;\n\trelease transferred;')
	member = e.output / 'member.astra'
	member.write_text(text)
	boxed = e.output / 'boxed.astra'
	boxed.write_text('''class Snapshot { int n; init(int n){this.n=n;} }
int read(borrowed Snapshot s){return s.n;}
int main(){var unique=new Snapshot(23);shared Snapshot box=shared_acquire(move unique);
var clone=box.clone();var moved=box;release moved;
if(read(shared_borrow(clone))!=23){return 81;}return 0;}
''')
	bag = e.output / 'bag.astra'
	bag.write_text(text[:text.index('int main()')] + '''int main(){
var root=new Resource(17);var weak=root.downgrade();
var bag=new Bag<Resource>();if(!bag.reserve(2)){return 81;}
var a=root.clone();var b=root.clone();bag.append(move a);bag.append(move b);
release bag; if(root.read()!=17){return 82;}
release root;var expired=weak.upgrade();if(expired!=null){return 83;}
release weak;return intrinsic_finish();}
''')
	prefix = text[:text.index('int main()')]
	record = e.output / 'record.astra'
	record.write_text(prefix + '''struct Snapshot{int tag;owned Resource payload;}
int main(){var root=new Resource(17);var weak=root.downgrade();
{var copy=root.clone();Snapshot snapshot={tag=9,payload=move copy};release root;
if(snapshot.tag!=9){return 81;}}
var expired=weak.upgrade();if(expired!=null){return 82;}release weak;return intrinsic_finish();}
''')
	closure = e.output / 'closure.astra'
	closure.write_text(prefix + '''int invoke(borrowed Resource resource,int n){return resource.read()+n;}
int main(){var root=new Resource(17);var weak=root.downgrade();var copy=root.clone();
var callback=closure_bind(move copy,invoke);release root;
if(closure_invoke(callback,2)!=19){return 81;}release callback;
var expired=weak.upgrade();if(expired!=null){return 82;}release weak;return intrinsic_finish();}
''')
	cache = e.output / 'cache.astra'
	cache.write_text(prefix + '''class Card{init(){}lazy property owned Resource content{
get{var value=new Resource(17);return move value;}}}
Resource acquire(borrowed Resource source){var copy=source.clone();return move copy;}
int main(){var card=new Card();var root=acquire(card.content);var weak=root.downgrade();release card;
if(root.read()!=17){return 81;}release root;
var expired=weak.upgrade();if(expired!=null){return 82;}release weak;return intrinsic_finish();}
''')
	defaults = e.output / 'defaults.astra'
	defaults.write_text('''class Holder{Resource child;init(Resource child){this.child=move child;}}
''' + prefix + '''Resource forward(Resource resource){var moved=resource;return move moved;}
int main(){Resource root=new Resource(17);var weak=root.downgrade();
Resource second=root;Resource third=forward(move second);var holder=new Holder(move third);
release holder;var expired=weak.upgrade();if(expired!=null){return 81;}
release weak;return intrinsic_finish();}
''')
	polymorphic = e.output / 'polymorphic.astra'
	polymorphic.write_text('''extern(C) int intrinsic_destroy(int value);extern(C) int intrinsic_finish();
[Shared,Monitor]interface Measure{int read(int n);}
[Shared,Monitor]class Derived:Measure{private int value;init(int value):base(){this.value=value;}
override int read(int n){return this.value+n;}deinit(){intrinsic_destroy(this.value);}}
int inspect(borrowed Measure view,int n){var hold=view.clone();var weak=hold.downgrade();
var again=weak.upgrade();if(again==null){return -1;}return again.read(n);}
int main(){var root=new Derived(17);var weak=root.downgrade();
if(inspect(root,2)!=19){return 81;}var copy=root.clone();release root;
if(inspect(copy,3)!=20){return 82;}release copy;
var expired=weak.upgrade();if(expired!=null){return 83;}release weak;return intrinsic_finish();}
''')
	for source, libraries, expected in [(member, [], 'intrinsic: one payload destruction, expired weak handle\n'),
		(boxed, [], ''), (bag, [ROOT / 'lib/astra/collections/bag.astra'], 'intrinsic: one payload destruction, expired weak handle\n'),
		*[(source, [], 'intrinsic: one payload destruction, expired weak handle\n') for source in [record, closure, cache, defaults, polymorphic]]]:
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (source.stem + '-' + level)
			links = ['--link-object', oracle]
			if source == polymorphic:
				monitor = e.output / 'monitors.o'
				e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pthread', '-c', ROOT / 'lib/runtime/runtime/monitors-13.c', '-o', monitor])
				links += ['--link-object', monitor, '--link-library', 'pthread']
			e.run([e.compiler, '-' + level, source, *libraries, *links, '-o', product])
			e.run([product], stdout=expected)
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
				'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
				product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	e.files(here / 'intrinsic.astra', here / 'intrinsic-oracle.c', Path(__file__), member, boxed, bag, record, closure, cache, defaults, polymorphic)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
