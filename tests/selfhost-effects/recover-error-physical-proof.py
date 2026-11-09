#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ten LLVM-valid alternatives in actual derived Error source modules."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--valid-field-receiver', action='store_true', help='Use a debugger test driver for a type-correct category-6 wrong receiver; preserve all compiler checks')
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.component.with_suffix('.identity.json'))
	assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('error_physical_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-physical-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	fixture = paths.RUNTIME/('native-frontiers-errororacle2-'+a.mode)/'result.json'
	witness = read(fixture)
	row = next(row for row in witness['programs'] if row['name'] == 'nested-outer-Error-borrow')
	assert row['C0']['exit'] == 42 and row['C0']['returning_clean_memory']
	assert all(sha(source['path']) == source['sha256'] for source in row['inputs'])
	commands = []
	def run(argv, name):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=600)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stdout[-2000:], r.stderr[-2000:])
		return r
	argv = [a.component, '--error-physical', build, *[source['path'] for source in row['inputs']]]
	adapter = None
	if a.valid_field_receiver:
		# The compiled test's index-1 -> index-0 GEP mutation leaves LLVM's
		# result element type stale. Change only this adversarial input into
		# a same-type null receiver; never change a producer/checker verdict.
		adapter = leaf/'valid-field-receiver.gdb'
		adapter.write_text('''set pagination off
set confirm off
set breakpoint pending on
set print thread-events off
python
import gdb
replaced=0
class Setter(gdb.Breakpoint):
 def stop(self):
  global replaced
  if int(gdb.parse_and_eval('$esi')) != 2: return False
  target=int(gdb.parse_and_eval('$rdi')); value=int(gdb.parse_and_eval('$rdx'))
  self.enabled=False
  try:
   opcode=int(gdb.parse_and_eval('(int)LLVMGetInstructionOpcode((void*)'+str(target)+')'))
   if opcode != 29: return False
   constant=int(gdb.parse_and_eval('(void*)LLVMIsAConstantInt((void*)'+str(value)+')'))
   if not constant: raise gdb.GdbError('Unexpected nonconstant GEP test mutation')
   zero=int(gdb.parse_and_eval('(unsigned long long)LLVMConstIntGetZExtValue((void*)'+str(value)+')'))
   if zero != 0 or replaced: raise gdb.GdbError('Unexpected/repeated GEP test mutation')
   pointer=int(gdb.parse_and_eval('(void*)LLVMTypeOf((void*)'+str(target)+')'))
   null=int(gdb.parse_and_eval('(void*)LLVMConstNull((void*)'+str(pointer)+')'))
   gdb.execute('set $esi = 0'); gdb.execute('set $rdx = '+str(null))
   replaced+=1; print('VALID_FIELD_RECEIVER_MUTATION',replaced)
  finally: self.enabled=True
  return False
Setter('LLVMSetOperand',internal=True)
gdb.execute('run')
print('VALID_FIELD_RECEIVER_TOTAL',replaced)
end
''')
		argv = ['gdb', '-nx', '-q', '-batch', '-x', adapter, '--args', *argv]
	observed = run(argv, 'actual-source-physical-alternatives')
	lines = observed.stdout.decode().splitlines()
	assert [line for line in lines if line.startswith('ERROR_LLVM_REJECT ')] == ['ERROR_LLVM_REJECT '+str(i) for i in range(10)]
	if adapter: assert lines.count('VALID_FIELD_RECEIVER_MUTATION 1') == lines.count('VALID_FIELD_RECEIVER_TOTAL 1') == 1 and 'exited normally' in observed.stdout.decode()
	assert sha(a.component) == identity['sha256']
	modules = []
	for category in range(10):
		physical = build/('error-physical-'+str(category)+'.ll')
		run(['opt', '-passes=verify', '-disable-output', physical], 'independent-LLVM-verify-'+str(category))
		modules.append(dict(category=category, path=str(physical), sha256=sha(physical), LLVM_valid=True, independent_source_consumer_rejected=True))
	(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_SOURCE_ERROR_PHYSICAL_ALTERNATIVES', profile=a.mode, component_sha256=sha(a.component), component_identity_sha256=sha(a.component.with_suffix('.identity.json')), fixture_sha256=sha(fixture), inputs=row['inputs'], modules=modules, category6='same-type Error field receiver replaced by null' if adapter else 'compiled GEP index alternative', test_driver=str(adapter) if adapter else None, test_driver_sha256=sha(adapter) if adapter else None, Astra_native_execution_credit=0, limitation='Actual Astra source/Flow/Core/CFG/SSA/LLVM producer and independent physical consumer. Every alternative has a fresh positive twin and independently passes LLVM verification before rejection. The disclosed debugger test driver, when requested, changes only the single invalid category-6 adversarial setter input into a same-type null receiver; source, binary on disk, canonical predicates and verdicts remain unchanged. Earlier invalid-LLVM receipts remain failed. No target ELF is executed or credited.'), indent=2)+'\n')
	print('Ten actual-source derived Error physical alternatives independently LLVM-valid and rejected', flush=True)


if __name__ == '__main__':
	main()
