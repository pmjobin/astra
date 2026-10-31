#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Hidden native factories preserve every returned graph's caller contexts."""
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-factory-units')
	here = Path(__file__).resolve().parent
	fixture = here / 'scoped-factory-unit.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	obj = e.output / 'context-17.o'
	e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
	e.files(fixture, vapi, provider, provider.with_suffix('.h'), obj, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	consumer = '''int main(){
	owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];
	var parent=scoped_allocator<ScopedAllocator>(a,2,1);
	var children=scoped_allocator<ScopedAllocator>(b,1,7);
	if(parent==null||children==null){return 1;}
	var first=ScopedFactory.make(parent,children,37);
	if(first.read()!=37||scoped_allocator_query(parent,1)!=1||scoped_allocator_query(children,1)!=1){return 2;}
	var refused=ScopedFactory.try_make(parent,children,41);
	if(refused!=null||scoped_allocator_query(parent,1)!=1||scoped_allocator_query(children,1)!=1){return 3;}
	release first;
	if(scoped_allocator_query(parent,1)!=0||scoped_allocator_query(children,1)!=0){return 4;}
	var later=ScopedFactory.try_make(parent,children,53);
	if(later==null||later.read()!=53){return 5;}
	release later;
	if(scoped_allocator_query(parent,1)!=0||scoped_allocator_query(children,1)!=0){return 6;}
	if(scoped_allocator_query(parent,4)!=2||scoped_allocator_query(parent,5)!=2){return 7;}
	if(scoped_allocator_query(children,4)!=3||scoped_allocator_query(children,5)!=3){return 8;}
	return 0;
}
'''
	exports = [arg for name in ['UnitLeaf', 'UnitPacket', 'UnitHost', 'make', 'try_make'] for arg in ['--native-export', 'ScopedFactory.' + name]]
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels); case.mkdir(exist_ok=True)
		producer = case / 'producer.astra'; producer.write_text(fixture.read_text())
		e.run([e.compiler, '-O' + levels[0], '-c', producer, '--vapi', vapi, '--module', 'ScopedFactory', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', vapi, obj, e.compiler]:
			shutil.copyfile(path, sdk / path.name)
		(sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert {p.name for p in sdk.glob('*.astra')}.issubset({'consumer.astra', 'local-child.astra'})
		command = [sdk / 'astrac', '-O' + levels[1], sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti', '--link-object', sdk / obj.name, '--link-library', 'pthread', '-o', sdk / 'consumer']
		e.run(command, cwd=sdk)
		e.run([sdk / 'consumer'], stdout='', cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout='', contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			executed_bytes = (sdk / 'consumer').read_bytes()
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(producer) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
			assert (sdk / 'consumer').read_bytes() == executed_bytes
			negative = sdk / 'local-child.astra'
			negative.write_text('owned ScopedFactory.UnitHost escape(borrowed ScopedAllocator parent){owned u8[] b=new u8[8197];var children=scoped_allocator<ScopedAllocator>(b,1,7);var host=ScopedFactory.make(parent,children,37);return move host;}int main(){return 0;}')
			e.run([sdk / 'astrac', '--check', negative, '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti'], expected=1, contains='result retains a scoped local allocation', cwd=sdk)
		e.files(producer, *[p for p in sdk.iterdir() if p.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
