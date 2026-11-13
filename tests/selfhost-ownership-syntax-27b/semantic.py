#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Inject source-policy and ownership fact faults at independent consumers."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
SOURCE = '''language astra27b;
class Item { int value; init(int value) { this.value = value; } }
Item make() { var result = new Item(42); return move result; }
class Holder { Item item; init(owned Item input) { this.item = move input; } }
int main() { Item selected = make(); var holder = new Holder(move selected); return holder.item.value; }
'''
GDB = '''set pagination off
set confirm off
set disable-randomization off
set auto-load python-scripts off
python
import gdb,json,pathlib,struct
configuration=@CONFIGURATION@
leaf=pathlib.Path(configuration['leaf']);offsets=configuration['offsets'];sizes=configuration['sizes']
read=lambda p,n:bytes(gdb.selected_inferior().read_memory(p,n))
ptr=lambda p:struct.unpack('<Q',read(p,8))[0]
i32=lambda p:struct.unpack('<i',read(p,4))[0]
field=lambda owner,kind,name:owner+offsets[kind][name]
def save(name,value):(leaf/name).write_text(json.dumps(value,indent=2)+'\\n')
class Returned(gdb.FinishBreakpoint):
 def stop(self):
  save('consumer-return.json',dict(returned=int(gdb.parse_and_eval('$al'))))
  return False
class Corrupt(gdb.Breakpoint):
 def stop(self):
  self.enabled=False;argument=int(gdb.parse_and_eval('$rdi'));action=configuration['action'];changes=[];facts={}
  if action.startswith('call-'):
   data=argument;checked=int(gdb.parse_and_eval('$rsi'));types=ptr(field(data,'RecoverTypes','types'));count=i32(field(data,'RecoverTypes','types')+8)
   uses=ptr(field(checked,'CheckedIndex','uses'));members=ptr(field(data,'RecoverTypes','members'));borrows=ptr(field(data,'RecoverTypes','borrows'))
   assert count==i32(field(checked,'CheckedIndex','uses')+8) and 0<count<100000
   calls=[];messages=[]
   for n in range(1,count):
    use=uses+n*sizes['CheckedTypeUse'];deferred=i32(field(use,'CheckedTypeUse','deferred'));flags=i32(field(use,'CheckedTypeUse','flags'))
    if deferred==15 and flags==0 and i32(types+n*4)>0:
     assert i32(field(use,'CheckedTypeUse','node'))==n
     calls.append(n)
    if i32(members+n*4)>0 and i32(borrows+n*4)>0:
     assert deferred==12 and flags==0 and i32(types+n*4)==15
     messages.append(n)
   assert len(calls)==2 and len(messages)==2,(calls,messages)
   if action=='call-result':changes=[(types+calls[0]*4,1)]
   elif action=='call-message-member':changes=[(members+messages[0]*4,0)]
   elif action=='call-message-borrow':changes=[(borrows+messages[0]*4,0)]
   elif action=='call-message-type':changes=[(types+messages[0]*4,1)]
   elif action=='call-pending-origin':changes=[(field(uses+calls[0]*sizes['CheckedTypeUse'],'CheckedTypeUse','deferred'),17)]
   else:assert action=='call-control'
   facts=dict(table_count=count,calls=calls,messages=messages)
  elif action.startswith('borrow-'):
   data=ptr(field(argument,'RecoverFlow','data'));nodes=ptr(field(data,'RecoverFlowData','nodes'));edges=ptr(field(data,'RecoverFlowData','edges'));owners=ptr(field(data,'RecoverFlowData','catch_owners'))
   count=i32(field(data,'RecoverFlowData','node_count'));owner_count=i32(field(data,'RecoverFlowData','catch_owners')+8)
   assert 0<count<=i32(field(data,'RecoverFlowData','nodes')+8)<100000 and 0<owner_count<100000
   node=lambda n:struct.unpack('<13i',read(nodes+(n-1)*sizes['RecoverNode'],sizes['RecoverNode']))
   calls=[]
   for n in range(1,count+1):
    row=node(n)
    if row[0]!=4 or row[10]!=2:continue
    message=i32(edges+row[9]*4);assert 1<=message<=count
    value=node(message)
    if value[0]==6:
     assert value[3]==15 and value[1]==row[1] and 0<value[5]<owner_count
     owner=i32(owners+value[5]*4);assert 1<=owner<=count
     caught=node(owner);assert caught[0]==25 and caught[5]==value[5] and caught[1]==row[1]
     other=i32(edges+(row[9]+1)*4);assert 1<=other<=count and node(other)[0]==1
     calls.append((n,message,owner,other,value[5],row[1]))
   assert len(calls)==1,calls
   call,message,owner,other,root,function=calls[0]
   if action=='borrow-missing-owner':changes=[(owners+root*4,0)]
   elif action=='borrow-owner-function':changes=[(field(nodes+(owner-1)*sizes['RecoverNode'],'RecoverNode','function'),0)]
   elif action=='borrow-message-type':changes=[(field(nodes+(message-1)*sizes['RecoverNode'],'RecoverNode','type'),1)]
   elif action=='borrow-coargument-move':changes=[(field(nodes+(other-1)*sizes['RecoverNode'],'RecoverNode','kind'),10),(field(nodes+(other-1)*sizes['RecoverNode'],'RecoverNode','symbol'),root)]
   else:assert action=='borrow-control'
   facts=dict(node_count=count,call=call,message=message,owner=owner,coargument=other,root=root,function=function)
  elif action.startswith('profile'):
   arena=ptr(field(argument,'SyntaxProgram','arena'));table=field(arena,'SyntaxArena','language_directives')
   assert ptr(table)>0 and i32(table+8)==1
   directive=ptr(table);values=struct.unpack('<3i',read(directive,12));assert all(v>0 for v in values)
   facts=dict(directive=values)
   if action=='profile-clear':changes=[(directive+i*4,0) for i in range(3)]
   elif action=='profile-rebind':changes=[(directive+4,values[0])]
   else:assert action=='profile-control'
  else:
   checked=ptr(field(argument,'RecoverFlow','checked'));binding=ptr(field(checked,'CheckedIndex','bindings'))
   table=field(binding,'BindingIndex','symbols');symbols=ptr(table);count=i32(field(binding,'BindingIndex','symbol_count'))
   flags=ptr(field(checked,'CheckedIndex','symbol_flags'));types=ptr(field(checked,'CheckedIndex','symbol_types'))
   assert 1<count<1000 and i32(table+8)>=count and i32(field(checked,'CheckedIndex','symbol_flags')+8)==count+1
   entries=[]
   for index in range(1,count+1):
    row=symbols+(index-1)*sizes['BindingSymbol'];kind=i32(field(row,'BindingSymbol','kind'));flag=i32(flags+index*4)
    span=field(row,'BindingSymbol','span');source,first,last=struct.unpack('<3i',read(span,12))
    assert source==1 and 0<=first<=last<=len(configuration['source'])
    entries.append(dict(index=index,kind=kind,flags=flag,spelling=configuration['source'][first:last]))
   facts=dict(symbol_count=count,symbols=entries)
   if action=='field-default':
    selected=[row for row in entries if row['kind']==6 and row['flags']==4];assert len(selected)==1
    changes=[(flags+selected[0]['index']*4,0)]
   elif action=='local-default':
    selected=[row for row in entries if row['kind']==8 and row['flags']==4 and 'selected' in row['spelling']];assert len(selected)==1,entries
    changes=[(flags+selected[0]['index']*4,0)]
   elif action=='result-default':
    selected=[row for row in entries if row['kind']==1 and row['flags']==4];assert len(selected)==1,entries
    index=selected[0]['index'];table=ptr(field(checked,'CheckedIndex','types'))
    rows=ptr(field(table,'TypeTable','rows'));edges=ptr(field(table,'TypeTable','edges'));callable=i32(types+index*4)
    descriptor=rows+(callable-1)*sizes['TypeDescriptor'];assert i32(field(descriptor,'TypeDescriptor','kind'))==25
    first=i32(field(descriptor,'TypeDescriptor','first'));edge=edges+first*sizes['TypeEdge'];assert i32(field(edge,'TypeEdge','flags'))==4
    signatures=ptr(field(checked,'CheckedIndex','signatures'));signature=i32(ptr(field(checked,'CheckedIndex','symbol_signatures'))+index*4)
    signature=signatures+(signature-1)*sizes['CheckedSignature'];assert i32(field(signature,'CheckedSignature','declaration'))==index and i32(field(signature,'CheckedSignature','flags'))==4
    changes=[(flags+index*4,0),(field(edge,'TypeEdge','flags'),0),(field(signature,'CheckedSignature','flags'),0)]
   else:assert action=='ownership-control'
  observation=dict(action=action,facts=facts,writes=[])
  for address,value in changes:
   before=i32(address);assert before!=value
   gdb.selected_inferior().write_memory(address,struct.pack('<i',value));assert i32(address)==value
   observation['writes'].append(dict(address=address,before=before,after=value))
  save('injection.json',observation);Returned(gdb.newest_frame(),internal=True)
  return False
def ended(event):save('inferior-exit.json',dict(exit=getattr(event,'exit_code',None)))
gdb.events.exited.connect(ended)
Corrupt('*'+hex(configuration['address']),internal=True)
end
run
'''


def layouts(core):
	classes = dict(re.findall(r'^\t\(class #\d+ "([^"]+)"\n(.*?)^\t\)', core, re.M|re.S))
	structs = dict(re.findall(r'^\t\(struct "([^"]+)"\n(.*?)^\t\)', core, re.M|re.S))
	def fields(text):
		return [(name, kind.strip()) for _, name, kind in re.findall(r'^\t\t\(field #(\d+) "([^"]+)" : ([^()\n]+?)(?: \(|\))', text, re.M)]
	def size(kind):
		if kind.endswith('[]'): return 16, 8
		if kind in classes or kind.startswith(('Shared<', 'Weak<')) or kind.endswith('*'): return 8, 8
		if kind == 'bool' or kind in ('i8', 'u8'): return 1, 1
		if kind in ('i16', 'u16'): return 2, 2
		if kind in ('int', 'i32', 'u32', 'f32'): return 4, 4
		if kind in ('i64', 'u64', 'f64'): return 8, 8
		assert kind in structs, kind
		position = 0; alignment = 1
		for _, field in fields(structs[kind]):
			width, align = size(field); position = (position+align-1)//align*align+width; alignment = max(alignment, align)
		return (position+alignment-1)//alignment*alignment, alignment
	requested = {'RecoverFlow':['checked', 'data'], 'CheckedIndex':['bindings', 'types', 'uses', 'symbol_flags', 'symbol_types', 'symbol_signatures', 'signatures'], 'BindingIndex':['symbols', 'symbol_count'], 'BindingSymbol':['kind', 'span'], 'TypeTable':['rows', 'edges'], 'TypeDescriptor':['kind', 'first'], 'TypeEdge':['flags'], 'CheckedSignature':['flags', 'declaration'], 'SyntaxProgram':['arena'], 'SyntaxArena':['language_directives'], 'RecoverTypes':['types', 'members', 'borrows'], 'RecoverFlowData':['nodes', 'edges', 'catch_owners', 'node_count'], 'RecoverNode':['kind', 'function', 'type', 'symbol'], 'CheckedTypeUse':['node', 'flags', 'deferred']}
	result = {}
	for kind, names in requested.items():
		position = 0; result[kind] = {}
		for name, field in fields(classes.get(kind, structs.get(kind))):
			width, align = size(field); position = (position+align-1)//align*align
			if name in names: result[kind][name] = position
			position += width
			if len(result[kind]) == len(names): break
		assert set(result[kind]) == set(names), kind
	return result, {kind:size(kind)[0] for kind in ('BindingSymbol', 'TypeDescriptor', 'TypeEdge', 'CheckedSignature', 'RecoverNode', 'CheckedTypeUse')}


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('compiler', 'core-map', 'producer-ir', 'build', 'runtime'): p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	a = p.parse_args()
	assert re.fullmatch('[0-9a-f]{64}', a.compiler_sha256) and sha(a.compiler) == a.compiler_sha256
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	core = a.core_map.read_text(); names = re.findall(r'^\t\(function "([^"]+)"', core, re.M)
	offsets, sizes = layouts(core)
	symbols = {v[2]:int(v[0], 16) for line in subprocess.check_output(['nm', '-an', a.compiler], text=True).splitlines() if len(v := line.split()) == 3}
	addresses = {}
	ir = a.producer_ir.read_text()
	for kind, function in [('profile', 'syntax_program_languages_verified'), ('ownership', 'recover_flow_verify'), ('call', 'recover_types_verify'), ('borrow', 'recover_payload_calls_verified')]:
		assert names.count(function) == 1
		symbol = 'astra.fn.'+str(names.index(function)); addresses[kind] = symbols[symbol]
		arguments = r'ptr [^,\n]*, ptr [^,\n]*' if kind == 'call' else r'ptr [^,\n]*'
		assert re.search(r'^define [^\n]*@'+re.escape(symbol)+r'\('+arguments+r'\) ', ir, re.M), 'exact C0 pointer calling convention required'
	source = runtime/'ownership.astra'; source.write_text(SOURCE)
	caught = [ROOT/'tests/selfhost-bootstrap-27a/caught-message-call.astra', ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/hosted/text.astra']
	inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), a.core_map, a.producer_ir, source, *caught)}
	tools = tool_identity([a.compiler, '/usr/bin/time', *[shutil.which(n) for n in ('gdb', 'nm', 'opt')]])
	write(runtime/'identity.json', dict(compiler_sha256=a.compiler_sha256, inputs=inputs, tools=tools, offsets=offsets, sizes=sizes, addresses=addresses, scope='Exact C0-produced development Stage1 only; Core-map layouts and actual optimized pointer signatures authenticated.'))
	rows = []; env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1')
	env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	actions = ('profile-control', 'profile-clear', 'profile-rebind', 'ownership-control', 'field-default', 'local-default', 'result-default', 'call-control', 'call-result', 'call-message-member', 'call-message-borrow', 'call-message-type', 'call-pending-origin', 'borrow-control', 'borrow-missing-owner', 'borrow-owner-function', 'borrow-message-type', 'borrow-coargument-move')
	for action in actions:
		leaf = runtime/action; leaf.mkdir(); output = build/(action+'.ll')
		marker = b'ASTRA27B_SEMANTIC_REFUSAL_SENTINEL\n'; output.write_bytes(marker)
		kind = next((kind for kind in ('profile', 'call', 'borrow') if action.startswith(kind+'-')), 'ownership')
		configuration = dict(leaf=str(leaf), action=action, address=addresses[kind], offsets=offsets, sizes=sizes, source=SOURCE)
		script = leaf/'corrupt.gdb'; script.write_text(GDB.replace('@CONFIGURATION@', repr(configuration)))
		argv = list(map(str, ['gdb', '--batch', '--nx', '-x', script, '--args', a.compiler, '--emit-llvm', '-o', output, *([source] if kind in ('profile', 'ownership') else caught)]))
		r = execute(argv, leaf/'execution', env=env); assert r['status'] == 'EXPECTED_OUTCOME'
		observations = {key:json.loads((leaf/(key+'.json')).read_text()) for key in ('injection', 'consumer-return', 'inferior-exit')}
		control = action.endswith('control')
		assert observations['consumer-return']['returned'] == int(control), (action, observations)
		assert observations['inferior-exit']['exit'] == int(not control), (action, observations)
		if control:
			assert output.read_bytes() != marker
			assert execute(['opt', '-passes=verify', '-disable-output', str(output)], leaf/'independent-LLVM-verify', env=env)['status'] == 'EXPECTED_OUTCOME'
		else:
			assert output.read_bytes() == marker and (leaf/'execution/stderr').read_bytes()
		rows.append(dict(action=action, argv=argv, observations=observations, script_sha256=sha(script), output_sha256=sha(output), execution=r))
		write(runtime/'observations.json', rows); print(action, 'CONTROL_PASS' if control else 'INDEPENDENT_CONSUMER_REFUSAL', flush=True)
	assert all(sha(path) == h for path, h in {**inputs, **tools}.items())
	write(runtime/'result.json', dict(status='SELECTED_SOURCE_OWNERSHIP_FACT_MUTATIONS_PASS', compiler_sha256=a.compiler_sha256, mutations=14, controls=4, identity_sha256=sha(runtime/'identity.json'), observations_sha256=sha(runtime/'observations.json'), scope='Source-profile, implicit field/local/result, recovered call and source-rooted borrow facts at independent consumers; no complete gate or memory credit.'))


if __name__ == '__main__':
	main()
