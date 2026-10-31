"""ASan on actual emitted Astra LLVM plus ASan/UBSan on independent C oracles."""
from pathlib import Path
import re
import sys
import evidence as support


def main(compiler,output):
	e=support.Evidence(compiler,output,'sanitizers')
	apps=support.ROOT/'examples/numerical-optimization-11'; lib=support.ROOT/'lib/astra/numerics'
	fixtures={85:('stencil',['vectors'],'application-oracle.c',48003),87:('pcm',['vectors','pcm'],'application-oracle.c',48000),93:('packet',[],'packet-oracle.c',48000),94:('metadata',[],'metadata-oracle.c',375)}
	e.inputs(Path(__file__))
	target=dict(line.split('=',1) for line in e.run([e.compiler,'--target-info']).stdout.splitlines() if '=' in line)
	e.data['target']=target
	for app,(name,modules,oracle_name,count) in fixtures.items():
		source=apps/f'a{app}-{name}.astra'; libraries=[lib/(module+'.astra') for module in modules]
		oracle=Path(__file__).with_name(oracle_name);e.inputs(source,*libraries,oracle)
		for mode in ('off','on'):
			folder=e.output/f'a{app}-{mode}';folder.mkdir(exist_ok=True); env={'ASTRA_TEST_OPTIMIZATIONS':mode}
			ssa=e.run([e.compiler,'--dump-ssa',source,*libraries]).stdout
			entry=int(re.search(r'\(function #(\d+) "main" -> int',ssa)[1])
			text=e.run([e.compiler,'--dump-llvm',source,*libraries],env=env).stdout
			text=f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n'+text
			text=re.sub(r'^(define .*?)\s*\{\s*$',r'\1 sanitize_address {',text,flags=re.M)
			text+=f'\ndefine i32 @main() sanitize_address {{\nentry:\n  %result = call fastcc i32 @astra.fn.{entry}()\n  ret i32 %result\n}}\n'
			raw,checked,obj,exe=folder/'input.ll',folder/'asan.ll',folder/'program.o',folder/'program'
			raw.write_text(text)
			e.run(['opt','-passes=default<O2>,asan','-S',raw,'-o',checked])
			assert '__asan_' in checked.read_text(), 'instrumentation must actually be present'
			e.run(['llc','-O2','-filetype=obj','-relocation-model=pic',checked,'-o',obj])
			e.run(['clang','-std=c11','-O1','-g','-ffp-contract=off','-fno-fast-math','-fsanitize=address,undefined','-fno-omit-frame-pointer','-Wall','-Wextra','-Werror',f'-DAPP_ID={app}','-DASTRA_SANITIZER_OBSERVER',obj,oracle,'-lm','-o',exe])
			data=folder/'output.bin'
			e.run([exe],env={'ASAN_OPTIONS':'detect_leaks=1:halt_on_error=1','UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1','ASTRA_NUMERICAL_OUTPUT':str(data)},contains=f'numerical:A{app}:{count}')
			assert data.stat().st_size==count*8
			e.files(raw,checked,obj,exe,data)
	e.data['instrumentation']='AddressSanitizer on emitted native Astra function bodies and C; UndefinedBehaviorSanitizer on the independent C oracles. System libraries are uninstrumented. The explicit allocation-count interposer is disabled only in sanitizer products; allocation ablations use the normal observer.'
	e.complete()


if __name__=='__main__':main(*sys.argv[1:])
