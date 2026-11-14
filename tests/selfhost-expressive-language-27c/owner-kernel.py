#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused exact owner/physical-index helpers using the existing replay model."""
import argparse
import ast,hashlib,json,os,sys,subprocess,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute,write,sha,output_path,tool_identity
p=argparse.ArgumentParser(description=__doc__)
for name in ('c0','build','runtime','link'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--c0-sha256',required=True)
p.add_argument('--llvm-cursor',action='store_true',help='Select the exact production aggregate cursor and LLVM primitives')
a=p.parse_args();c0=a.c0;assert sha(c0)==a.c0_sha256
leaf=output_path(a.runtime,BASE/'runtime');build=output_path(a.build,BASE/'build');leaf.mkdir(exist_ok=False);build.mkdir(exist_ok=False)
(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
assert subprocess.check_output(['llvm-config','--version']).strip()==b'23.1.4'
tools=tool_identity([c0,sys.executable,*[shutil.which(n) for n in ('cc','gcc','valgrind')]])
env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1');env.pop('LD_PRELOAD',None);env.pop('VALGRIND_OPTS',None)
selected=[];origins={}
def take(name,first,last=None):
	p=ROOT/name;raw=p.read_bytes();origins[str(p)]=sha(p);a=raw.index(first.encode());b=raw.index(last.encode(),a) if last else len(raw);data=raw[a:b];selected.append(dict(source=name,start=a,end=b,sha256=hashlib.sha256(data).hexdigest()));return data
ssa='compiler/ssa/recover.astra';owners='compiler/ssa/recover-owners.astra'
kernel=take(ssa,'struct RecoverValue {','class RecoverSsa {')
kernel+=take('compiler/cfg/recover-model.astra','struct RecoverBlock {','class RecoverCfg {')
kernel+=take('compiler/semantic/recover-model.astra','struct RecoverNode {','class RecoverFlowData {')
kernel+=take('compiler/semantic/recover-model.astra','RecoverNode recover_empty(','// Keep mutable construction')
kernel+=take('compiler/semantic/recover-storage.astra','struct RecoverSlot {','class RecoverStorage {')
kernel+=take('compiler/core/recover.astra','struct RecoverCoreNode {','class RecoverCore {')
kernel+=take('compiler/semantic/recover-owner-check.astra','int recover_owner_unwrap(','bool recover_owner_value(')
kernel+=take(ssa,'int recover_ssa_dominance_order(','int recover_ssa_definition(')
kernel+=take(ssa,'int recover_ssa_definition(','RecoverValue recover_ssa_expected(')
kernel+=take(ssa,'void recover_ssa_value_shortcut(','// Explore each owner version')
kernel+=take(ssa,'bool recover_ssa_owner(','// Reconstruct declaration sites')
kernel+=take(ssa,'owned int[] recover_ssa_local_definitions(','// Read-only proof diagnostics')
kernel+=take(owners,'class RecoverSsaOwnerIndex {','bool recover_ssa_slots(')
kernel+=take(owners,'bool recover_ssa_temporary(')
kernel+=take('compiler/ssa/recover-owner-packs.astra','class RecoverSsaOwnerPacks {')
kernel+=take('compiler/semantic/recover-foreign.astra','bool recover_value_kind(','bool recover_constructor_kind(')
kernel+=take('compiler/backend/llvm/recover-check.astra','class RecoverLlvmIndex {','bool recover_llvm_call(')
kernel+=take('compiler/backend/llvm/recover-module.astra','int recover_llvm_emission_order(','struct RecoverRecordStorage {')
kernel+=take('tests/selfhost-compiler-complete/ssa-dominance.astra','bool dominance_oracle(','int main(')
if a.llvm_cursor:
	selected=[];origins={}
	kernel=take('compiler/backend/llvm/recover-lazy-check.astra','class RecoverLazyCursor {','void* recover_lazy_symbol_checked(')
	kernel+=take('compiler/backend/llvm/recover-check.astra','bool recover_llvm_extract(','bool recover_llvm_field(')
	kernel+=take('compiler/backend/llvm/recover-helpers-check.astra','bool recover_llvm_jump(','bool recover_llvm_helper_signature(')
	kernel+=take('compiler/backend/llvm/recover-range-check.astra','bool recover_range_counter_store(','int recover_range_loop_instruction(')
	kernel+=take('compiler/cfg/recover-model.astra','struct RecoverBlock {','class RecoverCfg {')
view=leaf/'production-kernel.astra';view.write_bytes(kernel);view.chmod(0o444)
model=ROOT/'tests/selfhost-compiler-complete/ssa-owner-packs-model.astra';driver=ROOT/'tests/selfhost-expressive-language-27c/owner-kernel.astra'
if a.llvm_cursor:driver=ROOT/'tests/selfhost-expressive-language-27c/cursor-kernel.astra'
inputs=[view]
reference_identity=None
packed_reference_identity=None
if not a.llvm_cursor:
	revision='7676e12e40f4583f6834275e6ba089779faf41f9';name='compiler/ssa/recover-owners.astra'
	original=subprocess.check_output(['git','-C',ROOT,'show',revision+':'+name]);first=original.index(b'bool recover_ssa_slot(');last=original.index(b'bool recover_ssa_slots(',first)
	data=original[first:last].replace(b'recover_ssa_slot(',b'reference_slot(')
	reference=leaf/'scalar-reference.astra';reference.write_bytes(data);reference.chmod(0o444);inputs.append(reference)
	reference_identity=dict(revision=revision,path=name,git_blob=subprocess.check_output(['git','-C',ROOT,'rev-parse',revision+':'+name],text=True).strip(),original_sha256=hashlib.sha256(original).hexdigest(),start=first,end=last,selected_sha256=hashlib.sha256(original[first:last]).hexdigest(),rename='recover_ssa_slot to reference_slot only')
	revision='dd31bc34aa19794da4ad9c9c4636ab6a3144e2b5';name='compiler/ssa/recover-owner-packs.astra'
	original=subprocess.check_output(['git','-C',ROOT,'show',revision+':'+name]);first=original.index(b'bool recover_ssa_packed_slots(');last=len(original)
	data=original[first:last].replace(b'recover_ssa_packed_slots(',b'baseline_packed_slots(')
	reference=leaf/'packed-reference.astra';reference.write_bytes(data);reference.chmod(0o444);inputs.append(reference)
	packed_reference_identity=dict(revision=revision,path=name,git_blob=subprocess.check_output(['git','-C',ROOT,'rev-parse',revision+':'+name],text=True).strip(),original_sha256=hashlib.sha256(original).hexdigest(),start=first,end=last,selected_sha256=hashlib.sha256(original[first:last]).hexdigest(),rename='recover_ssa_packed_slots to baseline_packed_slots only',scope='Exact preceding packed entry; unchanged production reservation paths and packed transfer helpers are shared.')
for p in ((driver,) if a.llvm_cursor else (model,driver)):
	q=leaf/p.name;q.write_bytes(p.read_bytes());q.chmod(0o444);inputs.append(q);origins[str(p)]=sha(p)
libmodel=ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text());libs=next(ast.literal_eval(n.value) for n in libmodel.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='LIBRARIES' for t in n.targets))
origins[str(ROOT/'tests/selfhost-typecore/build.py')]=sha(ROOT/'tests/selfhost-typecore/build.py')
for name in libs:
	p=ROOT/('lib/astra/'+name+'.astra');q=leaf/'libraries'/(name+'.astra');q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes());q.chmod(0o444);inputs.append(q);origins[str(p)]=sha(p)
if a.llvm_cursor:
	for name in ('capi','recover-capi','recover-shared-capi'):
		p=ROOT/('compiler/backend/llvm/'+name+'.astra');q=leaf/(name+'.astra');q.write_bytes(p.read_bytes());q.chmod(0o444);inputs.append(q);origins[str(p)]=sha(p)
manifest=json.loads(a.link.read_text());excluded=('arguments.o',) if a.llvm_cursor else ('llvm-capi.o','arguments.o')
provider={p:h for p,h in manifest['objects'].items() if Path(p).name not in excluded};assert len(provider)==(6 if a.llvm_cursor else 5) and all(sha(p)==h for p,h in provider.items())
commands=[]
def run(name,argv,expected=0):
	r=execute(argv,leaf/name,expected=expected,timeout=600,env=env);commands.append(dict(name=name,argv=list(map(str,argv)),result=r));write(leaf/'commands.json',commands);print(name,r['exit'],round(r['seconds'],3),flush=True);assert r['exit']==expected,(leaf/name/'stderr').read_text();return (leaf/name/'stdout').read_text()
recipe=ROOT/'tests/selfhost-compiler-complete/run-recipe.py';tree=ast.parse(recipe.read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='declarations');ns={'hashlib':hashlib};exec(compile(ast.Module(body=[fn],type_ignores=[]),str(recipe),'exec'),ns);declarations=ns['declarations']
full=[]
for n,p in enumerate(origins):
	if not p.startswith(str(ROOT/'compiler')) and p not in (str(ROOT/'tests/selfhost-compiler-complete/ssa-dominance.astra'),str(ROOT/'tests/selfhost-compiler-complete/ssa-owner-packs.astra')):continue
	source=leaf/('source-'+str(n)+'.astra');source.write_bytes(Path(p).read_bytes());source.chmod(0o444);full.extend(declarations(run('syntax-'+str(n),[c0,'--dump-syntax',source])))
actual=declarations(run('syntax-kernel',[c0,'--dump-syntax',view]));assert actual and all(full.count(row)==1 for row in actual)
identity=dict(c0_sha256=sha(c0),recipe_sha256=sha(__file__),tools=tools,recipe_inputs={str(recipe):sha(recipe),str(a.link):sha(a.link)},origins=origins,selected=selected,normalized_declarations=actual,actual_inputs={str(p):sha(p) for p in inputs},providers=provider,limitation='Exact helper kernels with existing minimal containers; no full source, native feature, compiler or ABI qualification. The enum predicate is a declared test stub; selected-sum paths are outside this kernel scope.')
if reference_identity:identity['scalar_reference']=reference_identity
if packed_reference_identity:identity['packed_reference']=packed_reference_identity
if a.llvm_cursor:identity['limitation']='Exact production aggregate cursor and primitive checks on actual LLVM arguments/constants/corruptions only; no complete compiler, formatting-site or milestone qualification.'
write(leaf/'identity.json',identity)
run('semantic-preflight',[c0,'--dump-semantics',*inputs])
products={}
for mode in ('O0','O2'):
	target=build/('kernel-'+mode);links=[x for p in provider for x in ('--link-object',p)]
	if a.llvm_cursor:links.extend(x for library in manifest['libraries'] for x in ('--link-library',library[2:]))
	run(mode+'-build',[c0,'-'+mode,*inputs,*links,'-o',target]);run(mode+'-native',[target],42);run(mode+'-memory',['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',target],42)
	log=(leaf/(mode+'-memory')/'stderr').read_bytes();assert all(s in log for s in (b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)'));products[mode]=dict(path=str(target),sha256=sha(target))
assert all(sha(p)==h for p,h in {**identity['actual_inputs'],**provider,**tools}.items())
write(leaf/'result.json',dict(status='FOCUSED_OWNER_AND_PHYSICAL_INDEX_KERNELS_PASS',identity_sha256=sha(leaf/'identity.json'),commands_sha256=sha(leaf/'commands.json'),products=products,limitation=identity['limitation']))
