#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
from pathlib import Path
from hashlib import sha256
import json,struct,subprocess,os,time,signal
from run import C0_SHA256, ROOT, WORK, declarations
import argparse
parser=argparse.ArgumentParser(description='Test exact SSA short-circuit helpers against legacy scans and actual frozen compiler graphs.')
parser.add_argument('--compiler',type=Path,required=True)
parser.add_argument('--runtime-root',type=Path,required=True)
parser.add_argument('--build-root',type=Path,required=True)
parser.add_argument('--cfg-dump',type=Path,required=True)
parser.add_argument('--dominance-intervals',type=Path,required=True)
parser.add_argument('--capsule-prefix',type=Path)
parser.add_argument('--version',required=True)
a=parser.parse_args();root=ROOT;r=a.runtime_root;b=a.build_root
assert a.version.isalnum() and sha256(a.compiler.read_bytes()).hexdigest()==C0_SHA256
for path,parent in [(r,WORK/'runtime'),(b,WORK/'build'),(a.cfg_dump,WORK/'runtime')]:
	assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
assert a.dominance_intervals.is_file() and a.dominance_intervals.resolve().is_relative_to((WORK/'runtime').resolve())
leaf=r/('ssa-short-inputs-'+a.version);build=b/leaf.name;leaf.mkdir();build.mkdir()
(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes());dump=a.cfg_dump;snapshot=json.loads((dump/'snapshot.json').read_text());n=snapshot['blocks'];ne=snapshot['edges'];nn=snapshot['nodes'];nv=snapshot['values']
ssa=(root/'compiler/ssa/recover.astra').read_bytes();short=(root/'compiler/ssa/recover-short-circuit.astra').read_bytes();cfg=(root/'compiler/cfg/recover-model.astra').read_bytes()
model=Path(__file__).with_name('ssa-short-inputs-model.astra').read_bytes()
kernel=ssa[ssa.index(b'struct RecoverValue {'):ssa.index(b'class RecoverSsa {')]+cfg[cfg.index(b'struct RecoverBlock {'):cfg.index(b'class RecoverCfg {')]+ssa[ssa.index(b'bool recover_ssa_dominates('):ssa.index(b'int recover_ssa_definition(')]+ssa[ssa.index(b'bool recover_ssa_use('):ssa.index(b'// Explore each owner version')]+short
view=leaf/'exact-kernel.astra';view.write_bytes(model+kernel)
reference=subprocess.check_output(['git','show','1734667ed8b45e4fa743d181845e086e91140ed4:compiler/ssa/recover-short-circuit.astra'],cwd=root).replace(b'recover_ssa_short_inputs(',b'reference_short_inputs(')
(leaf/'legacy-reference.astra').write_bytes(reference)
intervals=a.dominance_intervals;rows=[tuple(map(int,line.split())) for line in intervals.read_text().splitlines()];assert len(rows)==n
first=[0]*(n+1);end=[0]*(n+1)
for node,first_stamp,end_stamp in rows:first[node]=first_stamp;end[node]=end_stamp
(leaf/'first.bin').write_bytes(struct.pack('<'+'i'*len(first),*first));(leaf/'end.bin').write_bytes(struct.pack('<'+'i'*len(end),*end))
rawc='''#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
static int32_t *blocks,*edges,*nodes,*values,*first,*end;static unsigned char *reachable;
static void *load(const char *path,size_t size) { FILE *f=fopen(path,"rb");void *p=malloc(size);if(!f||!p||fread(p,1,size,f)!=size)exit(91);fclose(f);return p; }
static void cleanup(void){free(blocks);free(edges);free(nodes);free(values);free(first);free(end);free(reachable);}
int graph_start(void) {
 blocks=load(BLOCKS,NB*40);edges=load(EDGES,NE*16);nodes=load(NODES,NN*76);values=load(VALUES,NV*20);reachable=load(REACHABLE,NB);first=load(FIRST,(NB+1)*4);end=load(END,(NB+1)*4);if(atexit(cleanup))exit(92);return NB;
}
int graph_count(int which){if(which==0)return NE;if(which==1)return NN;return NV;}
int graph_block(int i,int field){return blocks[i*10+field];}
int graph_edge(int i,int field){return edges[i*4+field];}
int graph_node(int i,int field){return nodes[i*19+field];}
int graph_value(int i,int field){return values[i*5+field];}
int graph_reachable(int i){return reachable[i];}
int graph_interval(int i,int which){return which?end[i]:first[i];}
void work_observed(int joins,int work){printf("%d %d\\n",joins,work);}
'''
for token,value in [('NB',n),('NE',ne),('NN',nn),('NV',nv)]:rawc=rawc.replace(token,str(value))
for token,path in [('BLOCKS',dump/'blocks.bin'),('EDGES',dump/'edges.bin'),('NODES',dump/'core-nodes.bin'),('VALUES',dump/'values.bin'),('REACHABLE',dump/'reachable.bin'),('FIRST',leaf/'first.bin'),('END',leaf/'end.bin')]:rawc=rawc.replace(token,json.dumps(str(path)))
observer=leaf/'observer.c';observer.write_text(rawc)
driver=leaf/'query.astra';driver.write_bytes(Path(__file__).with_suffix('.astra').read_bytes())
prefix=json.loads(a.capsule_prefix.read_text()) if a.capsule_prefix else [];commands=[]
def sha(p):return sha256(Path(p).read_bytes()).hexdigest()
def run(label,args,expected=0):
	cmd=prefix+(['--'] if prefix else [])+['/usr/bin/time','-v','-o',str(leaf/(label+'.time')),*map(str,args)];start=time.monotonic()
	with (leaf/(label+'.stdout')).open('wb') as out,(leaf/(label+'.stderr')).open('wb') as err:
		p=subprocess.Popen(cmd,cwd=build,stdout=out,stderr=err,start_new_session=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		try:code=p.wait(600)
		except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();raise
	row=dict(name=label,argv=cmd,exit=code,seconds=time.monotonic()-start,stdout_sha256=sha(leaf/(label+'.stdout')),stderr_sha256=sha(leaf/(label+'.stderr')));commands.append(row);(leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(label,code,flush=True)
	assert code==expected,(label,code,(leaf/(label+'.stderr')).read_text()[-2000:]);return row
run('toolchain',['python3','-B',root/'tests/selfhost-compiler-complete/toolchain.py','--compiler',a.compiler,'--receipt',leaf/'toolchain.json'])
production=leaf/'production-only-kernel.astra';production.write_bytes(kernel)
run('kernel-syntax',[a.compiler,'--dump-syntax',production])
normalized=declarations((leaf/'kernel-syntax.stdout').read_text())
full=[]
for name,raw in [('ssa',ssa),('short',short),('cfg',cfg)]:
	saved=leaf/(name+'-production.astra');saved.write_bytes(raw);run(name+'-syntax',[a.compiler,'--dump-syntax',saved]);full.extend(declarations((leaf/(name+'-syntax.stdout')).read_text()))
assert len(normalized)==9 and all(full.count(row)==1 for row in normalized)
source_inputs={str(a.cfg_dump/p):sha(a.cfg_dump/p) for p in ['blocks.bin','edges.bin','core-nodes.bin','values.bin','reachable.bin','snapshot.json']}
source_inputs[str(a.dominance_intervals)]=sha(a.dominance_intervals)
objects=[]
for name,source in [('observer',observer),('args',root/'lib/runtime/platform/args-posix.c')]:
	obj=build/(name+'.o');run(name+'-build',['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',source,'-o',obj]);objects.extend(['--link-object',obj])
products=[]
for mode in ['O0','O2']:
	exe=build/('short-inputs-'+mode);run(mode+'-build',[a.compiler,'-'+mode,view,leaf/'legacy-reference.astra',driver,*objects,'-o',exe])
	for case in ['small','graph']:
		normal=run(mode+'-'+case,[exe,'--'+case],42)
		memory=run(mode+'-'+case+'-memory',['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',exe,'--'+case],42)
		assert normal['stdout_sha256']==memory['stdout_sha256']
		assert all(t in (leaf/(mode+'-'+case+'-memory.stderr')).read_bytes() for t in [b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)'])
	products.append(dict(profile=mode,ELF_sha256=sha(exe),small_differential_cases=4096,positive_then_negative_controls=8,actual_original_joins=9007,actual_graph_work=36028,clean_memory_streams=2))
assert (root/'compiler/ssa/recover.astra').read_bytes()==ssa and (root/'compiler/ssa/recover-short-circuit.astra').read_bytes()==short
assert all(sha(p)==h for p,h in source_inputs.items())
result=dict(normalized_production_AST=normalized,source_inputs=source_inputs,status='EXACT_SHORT_PHI_HELPER_C0_KERNEL_PASS',production_sources={str(root/'compiler/ssa/recover.astra'):sha(root/'compiler/ssa/recover.astra'),str(root/'compiler/ssa/recover-short-circuit.astra'):sha(root/'compiler/ssa/recover-short-circuit.astra')},products=products,whole_original_native_credit=0,limitation='Exact production short-input/use/dominance bodies under C0 with minimal surrounding containers. Small models compare with the preserved legacy full-edge scan and deliberate index/use corruptions. Large model uses actual original CFG/SSA dumps and independently reconstructed dominance intervals. This is helper/work evidence; full current compiler SSA and native objects remain unproved.')
(leaf/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'],flush=True)
