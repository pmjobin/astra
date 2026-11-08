#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Trace an unchanged compiler's physical refusal without bypassing it."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--fixture', type=Path, required=True); p.add_argument('--core-receipt', type=Path, required=True)
	a = p.parse_args(); assert a.version.isalnum()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	core = read(a.core_receipt); assert core['exit'] == 0
	assert '--dump-core' in core['argv'] or '--check' in core['argv'] and '--dump-core' in a.core_receipt.with_suffix('.stderr').read_text()
	native_sources = [sha(path) for path in identity['identity']['argv'] if str(path).endswith('.astra')]
	core_sources = [sha(path) for path in core['argv'] if str(path).endswith('.astra')]
	assert native_sources == core_sources
	core_text = a.core_receipt.with_suffix('.stdout').read_text()
	names = re.findall(r'^\t\(function "([^"]+)"', core_text, re.M)
	symbols = subprocess.check_output(['nm', '--defined-only', a.component], text=True)
	assert set(map(int, re.findall(r' astra\.fn\.([0-9]+)$', symbols, re.M))) == set(range(len(names)))
	declarations = '\n'.join(path.read_text() for path in (ROOT/'compiler/backend/llvm').glob('*.astra'))
	checks = []
	for ordinal, name in enumerate(names):
		if not name.startswith('recover_') or not ('llvm' in name or 'verified' in name): continue
		pattern = r'\bbool '+re.escape(name)+r'\([^\n]*?\)( throws Error)?\s*\{'
		matches = re.findall(pattern, declarations)
		if len(matches) == 1: checks.append(dict(symbol='astra.fn.'+str(ordinal), name=name, output='rdi' if matches[0] else None))
	for ordinal, name, checked in [(27, 'shared_helpers_verified', True), (28, 'array_helpers_verified', True), (29, 'integer_helpers_verified', True), (30, 'check', True)]:
		assert re.search(r'^\t\(method #'+str(ordinal)+r' "'+name+r'" \(declaring-class #9 "RecoverLlvm"\)', core_text, re.M)
		checks.append(dict(symbol='astra.class.method.9.'+str(ordinal), name='RecoverLlvm.'+name, output='rsi' if checked else None))
	paths = load_module('debug_physical_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('debug-physical-'+a.version); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	row = next(row for row in read(a.fixture)['programs'] if row['name'] == 'derived-error-computed-base')
	assert all(sha(source['path']) == source['sha256'] for source in row['inputs'])
	module = build/'observed.ll'; destination = build/'refused.ll'; destination.write_text('Debug refusal output sentinel\n'); before = sha(destination)
	script = leaf/'trace.gdb'
	program = '''import gdb, re
active = False
inside_physical = False
class Returned(gdb.FinishBreakpoint):
 def __init__(self, name, output=None, verifier=False):
  super().__init__(gdb.newest_frame(), internal=True)
  self.name=name; self.output=int(gdb.parse_and_eval('$'+output)) if output else None; self.verifier=verifier
 def stop(self):
  global inside_physical
  raw=int(gdb.parse_and_eval('$rax'))
  if self.verifier:
   print('LLVM_VERIFIER_RETURN',raw)
  elif self.output is not None:
   if raw: print('CHECK_ERROR',self.name,hex(raw))
   elif bytes(gdb.selected_inferior().read_memory(self.output,1))[0] == 0: print('CHECK_FALSE',self.name,hex(int(gdb.parse_and_eval('$pc'))))
  elif raw & 255 == 0: print('CHECK_FALSE',self.name,hex(int(gdb.parse_and_eval('$pc'))))
  if self.name == 'recover_llvm_check': inside_physical=False
  return False
class Check(gdb.Breakpoint):
 def __init__(self, spec):
  super().__init__(spec['symbol'], internal=True); self.spec=spec
 def stop(self):
  global inside_physical
  if self.spec['name'] == 'recover_llvm_check': inside_physical=True
  if active: Returned(self.spec['name'],self.spec['output'])
  return False
class CountReturned(gdb.FinishBreakpoint):
 def __init__(self, block):
  super().__init__(gdb.newest_frame(),internal=True); self.block=block
 def stop(self):
  count=int(gdb.parse_and_eval('$rax'))
  print('ACTUAL_BLOCK_COUNT',hex(self.block),count)
  instruction=gdb.newest_frame().architecture().disassemble(int(gdb.parse_and_eval('$pc')),count=1)[0]['asm']
  offset=re.search(r'0x([0-9a-f]+)\\(%rsp\\),%ecx',instruction)
  if offset:
   address=int(gdb.parse_and_eval('$rsp'))+int(offset[1],16)
   print('EXPECTED_BLOCK_COUNT',int.from_bytes(bytes(gdb.selected_inferior().read_memory(address,4)),'little'))
  print(gdb.execute('x/8i $pc',to_string=True))
  return False
class Count(gdb.Breakpoint):
 def stop(self):
  if inside_physical: CountReturned(int(gdb.parse_and_eval('$rdi')))
  return False
class Verify(gdb.Breakpoint):
 def stop(self):
  global active
  active=True
  target=int(gdb.parse_and_eval('$rdi'))
  print('ACTUAL_LLVM_MODULE',hex(target))
  try:
   result=gdb.parse_and_eval('(int)LLVMPrintModuleToFile((void*)'+str(target)+', '+DUMP_PATH+', (char**)0)')
   print('MODULE_DUMP_RETURN',int(result))
  except gdb.error as error: print('MODULE_DUMP_UNAVAILABLE',str(error))
  Returned('llvm12_verify',verifier=True)
  return False
for spec in CHECKS: Check(spec)
Count(COUNT_SYMBOL,internal=True)
Verify('llvm12_verify',internal=True)
gdb.execute('run')
'''
	program = 'CHECKS='+repr(checks)+'\nCOUNT_SYMBOL='+repr('astra.fn.'+str(names.index('recover_llvm_instruction_count')))+'\nDUMP_PATH='+repr(json.dumps(str(module)))+'\n'+program
	script.write_text('set pagination off\nset confirm off\nset print thread-events off\npython\n'+program+'\nend\n')
	argv = ['gdb', '-nx', '-q', '-batch', '-x', script, '--args', a.component, '--native', destination, *[source['path'] for source in row['inputs']]]
	start = time.monotonic(); env = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS'): env.pop(key, None)
	timed_out = False
	try: r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'observe.time', *map(str, argv)], cwd=build, env=env, capture_output=True, timeout=600)
	except subprocess.TimeoutExpired as error:
		timed_out = True; r = subprocess.CompletedProcess(argv, None, error.output or b'', error.stderr or b'')
	(leaf/'observe.stdout').write_bytes(r.stdout); (leaf/'observe.stderr').write_bytes(r.stderr)
	commands = [dict(name='observe', argv=list(map(str, argv)), exit=r.returncode, timed_out=timed_out, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/'observe.stdout'), stderr_sha256=sha(leaf/'observe.stderr'))]
	assert sha(a.component) == identity['sha256'] and sha(destination) == before
	if module.exists():
		argv = ['opt', '-passes=verify', '-disable-output', module]; start=time.monotonic(); v=bounded_run(argv,capture_output=True,timeout=60)
		(leaf/'independent-LLVM.stdout').write_bytes(v.stdout); (leaf/'independent-LLVM.stderr').write_bytes(v.stderr); commands.append(dict(name='independent-LLVM',argv=list(map(str,argv)),exit=v.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/'independent-LLVM.stdout'),stderr_sha256=sha(leaf/'independent-LLVM.stderr')))
	(leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
	(leaf/'result.json').write_text(json.dumps(dict(status='DIAGNOSTIC_DEADLINE_STOP' if timed_out else 'UNCHANGED_COMPILER_PHYSICAL_REFUSAL_DIAGNOSIS',component_sha256=sha(a.component),component_identity_sha256=sha(a.component.with_suffix('.identity.json')),core_receipt=str(a.core_receipt),core_receipt_sha256=sha(a.core_receipt),source_order_hashes=native_sources,checks=checks,inputs=row['inputs'],gdb_exit=r.returncode,timed_out=timed_out,LLVM_sha256=sha(module) if module.exists() else None,destination_preserved=True,Astra_target_execution_credit=0,limitation='Source-order-matched C0 Core names map the unchanged O0 compiler symbols. Debugger breakpoints trace actual returns; no source, executable on disk, predicate or verdict is changed. The actual module is a diagnostic witness only; a refused module is never executed. LLVM verification does not override the source physical consumer.'),indent=2)+'\n')
	print(r.stdout.decode(errors='replace')[-12000:]); print(r.stderr.decode(errors='replace')[-1000:])


if __name__ == '__main__':
	main()
