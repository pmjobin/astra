# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A82: independent inventory units, runtime transactions and exact owner trace."""
from pathlib import Path
import os
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/systems-dsp-9'))
from support import Evidence

APPS = ROOT/'examples/language-generalization-10'
EXPORTS = ['Depot10.'+name for name in ['StockTicket','StockBatch','StockOrder','Repository<Depot10.StockOrder>',
	'build_order','open_depot','transfer_depot','order_receipt']]


def oracle(seed, count, quantity):
	if not (1 <= seed <= 20 and 3 <= count <= 6 and 1 <= quantity <= 5):
		return 'depot range\nN0\n', 2
	def receipt(key, size):
		units = [(key*13+i*7)%101 for i in range(size)]
		return key*11+size+sum((i+2)*value for i,value in enumerate(units))
	rows = [f'E{7000+seed+i}' for i in range(count)]+[f'N{count}']
	rows += [f'E{7100+seed+1}', f'N{receipt(seed+1,quantity+1)}', f'E{7040+seed}', f'E{7100+seed}', f'N{count-1}']
	remaining = [(seed+40,quantity+1)]+[(seed+i,quantity+i%2) for i in range(2,count)]
	total = 0
	for ordinal,(key,size) in enumerate(remaining,1):
		value = receipt(key,size); total += ordinal*value
		rows += [f'E{7100+key}', f'N{value}']
	return '\n'.join(rows+[f'N{total}','N0'])+'\n', 0


def main(compiler, output):
	out = Path(output).resolve(); out.mkdir(parents=True,exist_ok=True)
	e = Evidence(compiler, tempfile.mkdtemp(prefix='a82-',dir=out), 'a82')
	e.data['application'] = 'a82'
	provider,consumer = APPS/'a82-provider.astra',APPS/'a82-repository.astra'
	libraries = [ROOT/'lib/astra'/name for name in ['base/errors.astra','collections/bag.astra','collections/vector.astra',
		'text/utf8-message.astra','text/utf8-byte-builder.astra','hosted/text.astra','hosted/text-ops.astra','text/unicode-scalars.astra']]
	api = APPS/'resources.vapi'
	adapters = [APPS/'resources.c',*[ROOT/'lib/runtime/platform'/name for name in ['args-posix.c','text-posix.c','text-ops-posix.c']]]
	def run(command, expected=0, stdout='', diagnostic=None, memory=False):
		result = e.run(command,expected=expected,stdout=stdout,contains=diagnostic)
		if diagnostic:
			assert diagnostic in result.stderr and all(word not in result.stderr for word in ['internal error','assertion','CRITICAL'])
		elif memory:
			assert all(word in result.stderr for word in ['ERROR SUMMARY: 0 errors','in use at exit: 0 bytes in 0 blocks','(suppressed: 0 from 0)'])
		else:
			assert not result.stderr, result.stderr
		return result.stdout
	for source in [provider,consumer]:
		run([e.compiler,'--format','--check',source])
	objects = []
	for adapter in adapters:
		obj=e.output/(adapter.stem+'.o'); objects.append(obj)
		run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',adapter,'-o',obj])
	units = {}
	for level in [0,1,2]:
		directory=e.output/f'provider-O{level}';directory.mkdir()
		copy=directory/'provider.astra';copy.write_bytes(provider.read_bytes())
		interface,obj=directory/'depot.asti',directory/'depot.o'
		run([e.compiler,f'-O{level}','-c','--module','Depot10','--emit-interface',interface,
			*[arg for name in EXPORTS for arg in ['--native-export',name]],copy,'-o',obj])
		assert b'generic=Depot10.Repository;' in interface.read_bytes() and b'buffer=I32:' in interface.read_bytes()
		assert b'private_fee' not in interface.read_bytes() and str(copy).encode() not in interface.read_bytes()
		copy.unlink();assert not copy.exists()
		units[level]=interface,obj;e.files(interface,obj)
	identities={re.search(rb'^identity=(.+)$',interface.read_bytes(),re.M).group(1) for interface,_ in units.values()}
	assert len(identities)==1,'optimization changed the public unit identity'
	interface,_=units[0]
	inputs=['--vapi',api,*libraries,consumer]
	for stage in ['--check','--dump-core','--dump-cfg','--dump-ssa','--dump-nabi','--dump-llvm']:
		run([e.compiler,stage,'--import-module',interface,*inputs],stdout=None)
	for pl,cl in [(0,0),(0,2),(2,0),(2,2),(1,1)]:
		interface,implementation=units[pl]
		obj,exe=e.output/f'p{pl}-c{cl}.o',e.output/f'p{pl}-c{cl}'
		run([e.compiler,f'-O{cl}','--entry-object','--import-module',interface,*inputs,'-o',obj])
		run(['cc','-no-pie',obj,implementation,*objects,'-o',exe])
		for seed,count,quantity in [(2,3,2),(7,6,5),(11,4,1),(0,3,2)]:
			expected,status=oracle(seed,count,quantity)
			run([exe,seed,count,quantity],expected=status,stdout=expected)
			run(['valgrind','--default-suppressions=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--error-exitcode=99',exe,seed,count,quantity],expected=status,stdout=expected,memory=True)
		e.files(obj,exe)
	interface,_=units[0]
	for name,before,after,diagnostic in [
		('order-copy','order_receipt(move dispatched)','order_receipt(dispatched)','move'),
		('private-ticket','var dispatched = depot.take(1);','var dispatched = depot.take(1); var ticket = move dispatched.batch.ticket; number(ticket.key);','private'),
		('wrong-specialization','var opened = open_depot(seed, count, quantity);','var opened = open_depot(seed, count, quantity); owned Repository<StockOrder> wrong = new Vector<StockOrder>(0);','exact destination class'),
	]:
		invalid=e.output/(name+'.astra');invalid.write_text(consumer.read_text().replace(before,after,1))
		for stage in ['--check','--dump-core','--dump-cfg','--dump-ssa','--dump-nabi','--dump-llvm']:
			run([e.compiler,stage,'--import-module',interface,'--vapi',api,*libraries,invalid],expected=1,diagnostic=diagnostic)
	baseline=interface.read_bytes()
	for name,old,new in [('abi',b'runtime-units/6',b'composite-owners/1'),('target',b'target=',b'target=wrong-'),('module',b'module=Depot10',b'module=Other10')]:
		assert old in baseline,name
		interface.write_bytes(baseline.replace(old,new,1))
		run([e.compiler,'--check','--import-module',interface,*inputs],expected=1,diagnostic='native module:')
		interface.write_bytes(baseline)
	run([e.compiler,'--check','--import-module',interface,*inputs])
	e.files(provider,consumer,api,*libraries,*adapters,*[path.with_suffix('.h') for path in adapters if path.with_suffix('.h').is_file()],Path(__file__),ROOT/'tests/systems-dsp-9/support.py')
	e.complete()


if __name__=='__main__':
	main(*sys.argv[1:])
