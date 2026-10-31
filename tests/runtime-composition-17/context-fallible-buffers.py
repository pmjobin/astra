#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe actual caller ownership on refusal and checked constructor rollback."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='direct'):
	assert profile in ['direct', 'selected']
	e = Evidence(compiler, output, 'runtime-composition-17-fallible-buffers-' + profile)
	here = Path(__file__).resolve().parent
	sources = [here / 'context-fallible-buffers.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-fallible-inputs-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-fallible-inputs.vapi']
	if profile == 'selected':
		variant = e.output / 'selected-inputs.astra'; text = sources[0].read_text()
		text = text.replace('class AdmissionChild {', '[Allocator(kind="context",context="owned-concurrent")]\nclass AdmissionChild {')
		text = text.replace('var context = concurrent_allocator(2, 512, 1, 64);', 'var child_context = concurrent_allocator(1, 8197, 13, 128); if(child_context==null){return 10;}\n\tvar context = concurrent_allocator(2, 512, 1, 64);')
		text = text.replace('new AdmissionChild(', 'new(child_context) AdmissionChild(')
		text = text.replace('return admission_finish();', 'if(concurrent_allocator_query(child_context,1)!=0){return 11;}\n\treturn admission_finish();')
		variant.write_text(text); sources = [variant]
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]; e.files(obj)
	expected = 'fallible inputs: refusal preserves caller owners, admission empties slots and rollback retires each input once\n'
	for level in ['0', '1', '2']:
		product = e.output / ('inputs-O' + level)
		e.run([e.compiler, '-O' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'inputs-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']: instrument(e, 'inputs', sources, providers, expected, sanitizer, vapis=vapis)
	template = sources[0].read_text()
	for name, text, diagnostic in [
		('ordinary-new-still-consumes', template.replace('var first = try_new(context)', 'var first = new(context)'), 'moved'),
		('nonnull-caller-slot', template.replace('var child =', 'owned nonnull AdmissionChild child =', 1), 'exact nullable source slot'),
		('recovered-owner-still-affine', template.replace('release first;', 'var moved = move pending; return pending.identity(); release first;'), 'moved')]:
		negative = e.output / (name + '.astra'); negative.write_text(text)
		e.run([e.compiler, '-c', negative, *imports, '-o', negative.with_suffix('.o')], expected=1, contains=diagnostic)
		e.files(negative)
	if profile == 'direct':
		fresh = e.output / 'fresh-buffers.astra'
		fresh.write_text('''// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}
[Allocator(kind="context",context="owned-concurrent")]class FreshBuffers{
	owned u8[] plain;owned ContextBytes<ConcurrentAllocator> bytes;
	init(owned u8[] plain,owned ContextBytes<ConcurrentAllocator> bytes,bool fail)throws Fault{
		this.plain=move plain;if(fail){throw new Fault("partial fresh input");}this.bytes=move bytes;
	}
}
int main(){var context=concurrent_allocator(2,1024,1,64);var buffers=concurrent_allocator(1,16387,7,128);
	try{var blocker=new(context)FreshBuffers(new u8[3],new(buffers)u8[5],false);
		var refused=try_new(context)FreshBuffers(new u8[7],new(buffers)u8[9],true);
		if(refused!=null||concurrent_allocator_query(buffers,1)!=1){return 1;}release blocker;
		bool caught=false;try{var failed=try_new(context)FreshBuffers(new u8[11],new(buffers)u8[13],true);return 2;}catch(Fault error){caught=true;}
		if(!caught||concurrent_allocator_query(context,1)!=0||concurrent_allocator_query(buffers,1)!=0){return 3;}
	}catch(Fault error){return 4;}return 0;
}
''')
		# Ordinary constructor arguments retain their explicit named-move rule.
		e.run([e.compiler, '-c', fresh, *imports, '-o', e.output / 'fresh.o'], expected=1, contains="owned parameter 'plain' requires explicit 'move owner'")
		e.files(fresh)
	e.files(*sources, *providers, *vapis, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
