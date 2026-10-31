#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe owned input retention and initialized-prefix rollback before catch."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-buffer-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-buffer-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-buffer-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped buffer rollback: 6 placements, 4 prefix failures, 14 buffer retirements and retained refusal pairs\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free', 'calloc']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-buffer-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-buffer-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	# A separate element/constructor/result path exercises vector pair storage.
	vector = e.output / 'vector.astra'
	vector.write_text("""[Allocator(kind="context",context="scoped-affine")]
class VectorPacket{private owned f32<4>[] data;init(owned f32<4>[] data){this.data=move data;}int count(){return len(this.data);}}
owned f32<4>[] replace(owned f32<4>[] first,owned f32<4>[] second){first=move second;return move first;}
int main(){owned u8[] backing=new u8[8197];var context=scoped_allocator<ScopedAllocator>(backing,1,7);owned f32<4>[] first=new f32<4>[17];owned f32<4>[] second=new f32<4>[37];var data=replace(move first,move second);var packet=try_new(context)VectorPacket(move data);if(packet==null){return 1;}return packet.count()-37;}
""")
	e.files(vector)
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('vector-' + level)
		e.run([e.compiler, '-' + level, vector, '--vapi', vapi, '--link-object', links[0], '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='')
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'vector-O2'], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('export(C) int scoped_buffer_rollback_run()')[0]
	negative_cases = [
		('local-result', declarations + """owned CheckedBufferHost escape() throws BufferConstructionFault {
	owned u8[] backing=new u8[8197];
	var context=scoped_allocator<ScopedAllocator>(backing,2,1);
	owned u8[] left=new u8[11];
	owned i32[] right=new i32[13];
	var host=new(context)CheckedBufferHost(1,move left,move right,0);
	return move host;
}
int main(){return 0;}
""", 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('if(host.read()!=identity*20+4)', 'len(left); if(host.read()!=identity*20+4)'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null)', 'release backing; if(context==null)'), 'exclusively borrowed'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
