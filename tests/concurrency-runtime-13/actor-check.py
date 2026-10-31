# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generated native Actor handlers, checked admission and exact owned lifetimes."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-actor')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/runtime/actors-13.c', here / 'actor-basic-oracle.c']
	astra = [here / 'actor-basic.astra', ROOT / 'lib/astra/base/errors.astra']
	expected = 'native Actor: named handler, full/closed consumption, queued cancellation, joined receiver destruction\n'
	links = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, *astra, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=20)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'actor-basic', astra, providers, expected, sanitizer)
	prefix = '[Actor]class Inbox{init(){}}class Parcel{init(){}}int handle(borrowed Inbox inbox,owned Parcel parcel){return 0;}'
	body = 'var inbox=new Inbox();var sender=actor_bind(move inbox,handle,2,"actor-test");'
	refusals = {
		'composition': ('[Actor,Monitor]class Inbox{init(){}}int main(){return 0;}', 'invalid concurrency declaration policy'),
		'affine-message': (prefix.replace('class Parcel', '[ThreadBound]class Parcel') + 'int main(){' + body + 'return 0;}', 'Send message'),
		'borrowed-message': (prefix.replace('owned Parcel parcel', 'borrowed Parcel parcel') + 'int main(){' + body + 'return 0;}', 'closure code arguments'),
		'ordinary-receiver': (prefix.replace('[Actor]', '') + 'int main(){' + body + 'return 0;}', 'exclusive Actor receiver'),
		'empty-mailbox': (prefix + 'int main(){' + body.replace('handle,2,', 'handle,0,') + 'return 0;}', 'bounded FIFO'),
		'oversized-mailbox': (prefix + 'int main(){' + body.replace('handle,2,', 'handle,1025,') + 'return 0;}', 'bounded FIFO'),
		'dynamic-mailbox': (prefix + 'int main(){int capacity=2;' + body.replace('handle,2,', 'handle,capacity,') + 'return 0;}', 'literal mailbox capacity'),
		'empty-name': (prefix + 'int main(){' + body.replace('"actor-test"', '""') + 'return 0;}', '1..15 printable ASCII'),
		'long-name': (prefix + 'int main(){' + body.replace('"actor-test"', '"abcdefghijklmnop"') + 'return 0;}', '1..15 printable ASCII'),
		'control-name': (prefix + 'int main(){' + body.replace('"actor-test"', '"actor\\n"') + 'return 0;}', 'control or non-ASCII'),
		'lexical-receiver': (prefix + 'int main(){' + body.replace('new Inbox()', 'Inbox.init()') + 'return 0;}', 'independently heap-allocated'),
		'direct-invoke': (prefix + 'int main(){' + body + 'return closure_invoke(sender,0);}', 'live exact typed closure'),
		'wrong-provider': (prefix + 'int main(){' + body + 'return thread_start(sender,0);}', 'live exact owned or borrowed'),
		'unmoved-message': (prefix + 'int main(){try{' + body + 'var parcel=new Parcel();actor_send(sender,parcel);return 0;}catch(Error error){return 1;}}', 'explicit move'),
		'lexical-message': (prefix + 'int main(){try{' + body + 'var parcel=Parcel.init();actor_send(sender,move parcel);return 0;}catch(Error error){return 1;}}', 'independently heap-owned'),
		'sender-use-after-move': (prefix + 'int main(){try{' + body + 'var peer=sender;var parcel=new Parcel();actor_send(sender,move parcel);return 0;}catch(Error error){return 1;}}', 'use of moved owned value'),
	}
	for name, (text, diagnostic) in refusals.items():
		source = e.output / (name + '.astra')
		source.write_text(text + '\n')
		refusal = e.run([e.compiler, '--check', source, ROOT / 'lib/astra/base/errors.astra'], expected=1, contains=diagnostic)
		assert ': error:' in refusal.stderr and 'internal' not in refusal.stderr.lower()
		e.files(source)
	e.files(*providers, *astra, Path(__file__), here / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
