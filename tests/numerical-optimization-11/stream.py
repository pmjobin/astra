"""A96: independent native producer/consumer, owned streaming DSP and files."""
from pathlib import Path
import re
import sys
import evidence as support


def main(compiler,output):
	e = support.Evidence(compiler,output,'a96')
	apps = support.ROOT/'examples/numerical-optimization-11'
	producer_source, consumer = apps/'a96-producer.astra',apps/'a96-stream.astra'
	libraries = [support.ROOT/'lib/astra/numerics'/name for name in ('fir.astra','filters.astra')]
	oracle = Path(__file__).with_name('stream-oracle.c')
	e.inputs(producer_source,consumer,*libraries,oracle,Path(__file__))
	provider = e.output/'oracle.o'
	e.run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-fast-math','-Wall','-Wextra','-Werror','-c',oracle,'-o',provider])
	identities = []; outputs = {0:[],1:[]}
	for level in (0,1,2):
		folder = e.output/f'O{level}'; folder.mkdir(exist_ok=True)
		producer,interface,obj = folder/'producer.astra',folder/'producer.asti',folder/'producer.o'
		producer.write_bytes(producer_source.read_bytes())
		e.run([e.compiler,f'-O{level}','-c','--module','Aep11','--emit-interface',interface,'--native-export','Aep11.strict_sample','--native-export','Aep11.selected_sample',producer,'-o',obj])
		text = interface.read_text(); assert 'floating-policy=32;' in text
		identities.append(re.search(r'^identity=(.+)$',text,re.M)[1])
		producer.rename(folder/'producer.preserved-input'); e.files(folder/'producer.preserved-input')
		exe = folder/'stream'
		e.run([e.compiler,f'-O{2-level}','--import-module',interface,consumer,*libraries,'--link-object',provider,'--link-library','m','-o',exe])
		for mode in (0,1):
			binary = folder/f'stream-mode{mode}.bin'; env={'ASTRA_NUMERICAL_RELAXED':str(mode)}
			e.run([exe],env=dict(env,ASTRA_NUMERICAL_OUTPUT=str(binary)),contains=f'numerical:A96:192000 mode={mode}')
			assert binary.stat().st_size == 192000*8; outputs[mode].append(binary.read_bytes())
			e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],env=env,contains='failed=0',timeout=300)
			e.files(binary)
		ir = folder/'stream.ll'; ir.write_text(e.run([e.compiler,'--dump-llvm',f'-O{2-level}','--import-module',interface,consumer,*libraries]).stdout)
		assembly = folder/'stream.asm'; assembly.write_text(e.run(['objdump','-dr',exe]).stdout)
		e.files(interface,obj,exe,ir,assembly)
		bad = folder/'corrupt.asti'; bad.write_text(text.replace('floating-policy=32;','floating-policy=16;'))
		e.run([e.compiler,'--import-module',bad,'-c',consumer,*libraries,'-o',folder/'bad.o'],expected=1)
		assert not (folder/'bad.o').exists(); e.files(bad)
	assert len(set(identities)) == 1
	for mode,values in outputs.items():
		assert all(value == values[0] for value in values), mode
	e.files(producer_source,consumer,*libraries,oracle,provider)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
