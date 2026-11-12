#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Time native compiler stages and independent verifiers with read-only hooks."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import os
import signal
import subprocess
import sys
import time

from acceleration import process_sample
from run import C0_SHA256

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--host', type=Path, required=True)
parser.add_argument('--core-map', type=Path)
parser.add_argument('--bootstrap', action='store_true', help='profile the exact original C0 by its retained native symbols')
parser.add_argument('--timeout-seconds', type=int, default=7200)
parser.add_argument('--profile-dir', type=Path, required=True)
parser.add_argument('arguments', nargs=argparse.REMAINDER)
a = parser.parse_args()
assert a.arguments and a.arguments[0] == '--'
arguments = a.arguments[1:]
leaf = a.profile_dir
leaf.mkdir()
assert a.timeout_seconds > 0
identity = dict(sha256=C0_SHA256) if a.bootstrap else json.loads(a.host.with_suffix('.identity.json').read_text())
assert sha256(a.host.read_bytes()).hexdigest() == identity['sha256']
assert a.bootstrap or a.core_map
core = a.core_map.read_text() if a.core_map else ''
names = re.findall(r'^\t\(function "([^"]+)"', core, re.M)
symbols = {v[2]:int(v[0], 16) for line in subprocess.check_output(['nm', '-n', str(a.host)], text=True).splitlines() if len(v := line.split()) == 3}
stages = {}
for label, candidates in [
	('source_load_parse', ['binding_load_program']),
	('binding', ['binding_index']),
	('semantic', ['checked_build_effects_profile', 'checked_build_profile', 'checked_build_profile_mode']),
	('Flow', ['recover_flow_lower_mode']),
	('Core', ['recover_core_lower']),
	('CFG', ['recover_cfg_lower']),
	('SSA', ['recover_ssa_lower']),
	('Flow_verify', ['recover_flow_verify']),
	('Core_verify', ['recover_core_verify']),
	('CFG_verify', ['recover_cfg_verify']),
	('SSA_verify', ['recover_ssa_verify']),
]:
	for name in candidates:
		if name in names and 'astra.fn.'+str(names.index(name)) in symbols:
			stages[label] = dict(name=name, address=symbols['astra.fn.'+str(names.index(name))])
			break
if not a.bootstrap:
	classes = re.findall(r'^\t\(class #(\d+) "RecoverLlvm"', core, re.M)
	assert len(classes) == 1
	class_id = int(classes[0])
	for label, method in [('LLVM_build', 'build'), ('LLVM_write', 'write')]:
		found = re.findall(r'^\t\(method #(\d+) "'+method+r'" \(declaring-class #'+str(class_id)+r' "RecoverLlvm"', core, re.M)
		assert len(found) == 1
		symbol = 'astra.class.method.'+str(class_id)+'.'+found[0]
		if symbol in symbols:
			stages[label] = dict(name=symbol, address=symbols[symbol])
if not a.bootstrap and 'binding' not in stages:
	binding_class = re.findall(r'^\t\(class #(\d+) "BindingIndex"', core, re.M)
	assert len(binding_class) == 1
	methods = re.findall(r'^\t\(method #(\d+) "run" \(declaring-class #'+binding_class[0]+r' "BindingIndex"', core, re.M)
	assert len(methods) == 1
	symbol = 'astra.class.method.'+binding_class[0]+'.'+methods[0]
	if symbol in symbols:
		stages['binding'] = dict(name=symbol, address=symbols[symbol])
if a.bootstrap:
	for label, symbol in {
		'source_load_parse':'astra_syntax_parser_parse',
		'semantic':'astra_semantic_semantic_analyzer_analyze_program',
		'Core':'astra_core_core_builder_build',
		'generic':'astra_core_core_generic_monomorphizer_build',
		'CFG':'astra_cfg_cfg_builder_build',
		'Flow':'astra_cfg_cfg_flow_checker_check',
		'SSA':'astra_ssa_ssa_builder_build',
		'LLVM_build':'astra_backend_llvm_llvm_lowering_lower',
		'LLVM_optimize':'astra_backend_llvm_llvm_target_machine_artifact_run_pipeline',
		'LLVM_write':'astra_backend_llvm_llvm_target_machine_artifact_emit_object',
		'link':'astra_driver_executable_output_link_and_commit',
	}.items():
		if symbol in symbols:
			stages[label] = dict(name=symbol, address=symbols[symbol])
assert stages, 'No usable retained stage symbols; no process was started'
for row in stages.values():
	row['breakpoint'] = row['name'] if a.bootstrap else '*'+hex(row['address'])
script = '''set pagination off
set auto-load python-scripts off
set confirm off
set disable-randomization off
set python print-stack full
python
import gdb,json,pathlib,time,os
leaf=pathlib.Path(LEAF)
stages=STAGES
observations=[]
active={}
sequence=[0]
clock_ticks=os.sysconf('SC_CLK_TCK')
def sample():
    pid=gdb.selected_inferior().pid
    result=dict(monotonic_ns=time.monotonic_ns(),UTC_ns=time.time_ns(),pid=pid)
    if pid:
        fields=pathlib.Path('/proc/'+str(pid)+'/stat').read_text().rsplit(')',1)[1].split()
        result['CPU_seconds']=(int(fields[11])+int(fields[12]))/clock_ticks
        status=pathlib.Path('/proc/'+str(pid)+'/status').read_text().splitlines()
        for line in status:
            if line.startswith(('VmRSS:','VmHWM:')):result[line.split(':')[0]+'_KiB']=int(line.split()[1])
    return result
class Complete(gdb.FinishBreakpoint):
    def __init__(self,label,entry):
        super().__init__(gdb.newest_frame(),internal=True)
        self.label=label;self.entry=entry
        sequence[0]+=1;self.sequence=sequence[0]
        active[str(self.sequence)]=dict(stage=label,entry=entry)
        (leaf/'active.json').write_text(json.dumps(active,indent=2)+'\\n')
    def stop(self):
        end=sample();observations.append(dict(stage=self.label,entry=self.entry,exit=end,seconds=(end['monotonic_ns']-self.entry['monotonic_ns'])/1e9))
        active.pop(str(self.sequence),None)
        (leaf/'active.json').write_text(json.dumps(active,indent=2)+'\\n')
        (leaf/'stages.json').write_text(json.dumps(observations,indent=2)+'\\n')
        return False
class Enter(gdb.Breakpoint):
    def __init__(self,label,location):
        super().__init__(location,internal=True)
        self.label=label
    def stop(self):
        Complete(self.label,sample())
        return False
hooks=[Enter(label,row['breakpoint']) for label,row in stages.items()]
def ended(event):
    (leaf/'inferior-exit.json').write_text(json.dumps(dict(exit_code=getattr(event,'exit_code',None),observations=len(observations)),indent=2)+'\\n')
gdb.events.exited.connect(ended)
end
run
quit
'''.replace('LEAF', repr(str(leaf))).replace('STAGES', repr(stages))
script_path = leaf/'commands.gdb'
script_path.write_text(script)
argv = ['gdb', '-q', '--nx', '--batch', '-x', str(script_path), '--args', str(a.host), *arguments]
tools = {str(Path(shutil.which(name)).resolve()):sha256(Path(shutil.which(name)).resolve().read_bytes()).hexdigest() for name in ['gdb', 'nm', 'python3']}
command = dict(argv=argv, host_sha256=identity['sha256'], core_map_sha256=sha256(a.core_map.read_bytes()).hexdigest() if a.core_map else None, driver_sha256=sha256(Path(__file__).read_bytes()).hexdigest(), tools=tools, stages=stages, bootstrap=a.bootstrap, instrumentation='Read-only entry/return breakpoints. No verifier or plan mutations. Optimized-away symbols provide no standalone interval.')
(leaf/'command.json').write_text(json.dumps(command, indent=2)+'\n')
start = time.monotonic()
timed_out = False
with (leaf/'stdout').open('wb') as stdout, (leaf/'stderr').open('wb') as stderr:
	process = subprocess.Popen(argv, stdout=stdout, stderr=stderr, start_new_session=True)
	while True:
		try:
			process.wait(timeout=1)
			break
		except subprocess.TimeoutExpired:
			active_file = leaf/'active.json'
			try:
				active_stages = json.loads(active_file.read_text()) if active_file.exists() else {}
			except json.JSONDecodeError:
				active_stages = {}
			live = dict(elapsed_seconds=time.monotonic()-start, active_stage_functions=active_stages, process=process_sample(process.pid), status='RUNNING', qualification_credit=0)
			(leaf/'live.json').write_text(json.dumps(live, indent=2)+'\n')
			if time.monotonic()-start >= a.timeout_seconds:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL); process.wait(); break
out = (leaf/'stdout').read_bytes(); err = (leaf/'stderr').read_bytes()
sys.stdout.buffer.write(out)
sys.stderr.buffer.write(err)
stage_file = leaf/'stages.json'
if stage_file.exists():
	rows = json.loads(stage_file.read_text())
	source_stage = next((row for row in rows if row['stage'] == 'source_load_parse'), None)
	flow_stage = next((row for row in rows if row['stage'] == 'Flow'), None)
	if source_stage and flow_stage:
		interval = dict(stage='binding_and_semantic', entry=source_stage['exit'], exit=flow_stage['entry'], seconds=(flow_stage['entry']['monotonic_ns']-source_stage['exit']['monotonic_ns'])/1e9, scope='Exact interval after parsed program loading and before Flow lowering. Binding/type checking wrappers are inlined in optimized hosts.')
		(leaf/'binding-semantic-interval.json').write_text(json.dumps(interval, indent=2)+'\n')
exit_file = leaf/'inferior-exit.json'
actual = json.loads(exit_file.read_text())['exit_code'] if exit_file.exists() else None
result = dict(debugger_exit=process.returncode, native_exit=actual, timed_out=timed_out, seconds=time.monotonic()-start, stdout_sha256=sha256(out).hexdigest(), stderr_sha256=sha256(err).hexdigest(), stage_intervals_scope='Each retained stage function is timed including its nested work. Validation between stage calls appears in the unassigned intervals. Optimized-away symbols are not inferred. No cold speedup inference.')
(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
(leaf/'live.json').write_text(json.dumps(dict(status='TIMED_OUT' if timed_out else 'FINISHED', native_exit=actual, seconds=result['seconds']), indent=2)+'\n')
raise SystemExit(actual if actual is not None and process.returncode == 0 else 99)
