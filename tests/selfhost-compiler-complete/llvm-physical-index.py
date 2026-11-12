#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay fresh physical-checker indexes with scalar and full-population oracles."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha, declarations as syntax_declarations
from acceleration import execute, output_path, run_jobs, write


def between(raw, start, end):
	return raw[raw.index(start):raw.index(end)]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--original', type=Path, required=True)
	p.add_argument('--current', type=Path, required=True)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('llvm-physical-index-'+a.version), WORK/'runtime'); leaf.mkdir()
	build = output_path(a.build_root/leaf.name, WORK/'build'); build.mkdir()
	names = ['compiler/backend/llvm/recover-check.astra', 'compiler/semantic/recover-model.astra', 'compiler/semantic/recover-storage.astra', 'compiler/core/recover.astra']
	raw = [(ROOT/name).read_bytes() for name in names]
	kernel = between(raw[0], b'class RecoverLlvmIndex {', b'bool recover_llvm_call(')
	kernel += between(raw[1], b'struct RecoverNode {', b'class RecoverFlowData {')
	kernel += between(raw[2], b'struct RecoverSlot {', b'class RecoverStorage {')
	kernel += between(raw[3], b'struct RecoverCoreNode {', b'class RecoverCore {')
	view = leaf/'production-kernel.astra'; view.write_bytes(kernel)
	driver = Path(__file__).with_suffix('.astra'); (leaf/driver.name).write_bytes(driver.read_bytes())
	(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	commands = []
	def run(name, argv, expected=0, timeout=180):
		result = execute(argv, leaf/name, expected=expected, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, **result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result['exit'], (leaf/name/'stderr').read_text()[-2000:])
		print(name, round(result['seconds'], 3), flush=True)
		return (leaf/name/'stdout').read_bytes()
	run('toolchain', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'])
	full = []
	for i, data in enumerate(raw):
		path = leaf/('source-'+str(i)+'.astra'); path.write_bytes(data)
		full.extend(syntax_declarations(run('AST-'+str(i), [a.compiler, '--dump-syntax', path]).decode()))
	selected = syntax_declarations(run('AST-kernel', [a.compiler, '--dump-syntax', view]).decode())
	assert selected and all(full.count(row) == 1 for row in selected)
	captures = []; inputs = {}
	for label, directory, expected in [('original', a.original, (284425, 20656, 2392)), ('current', a.current, (320662, 22906, 2565))]:
		directory = output_path(directory, WORK/'runtime')
		for name in ('snapshot.json', 'core-nodes.bin', 'storage-slots.bin'): inputs[str(directory/name)] = sha(directory/name)
		snapshot = json.loads((directory/'snapshot.json').read_text())
		assert (snapshot['nodes'], snapshot['storage_slots'], snapshot['functions']) == expected
		nodes = list(struct.iter_unpack('<18i?3x', (directory/'core-nodes.bin').read_bytes()))
		slots = list(struct.iter_unpack('<5i??2x', (directory/'storage-slots.bin').read_bytes()))
		assert len(nodes) == expected[0] and len(slots) == expected[1]
		symbols = max(max(row[5] for row in nodes), max(row[0] for row in slots))+1
		# Independent forward occurrence lists; production builds reverse links.
		next_nodes = [0]*len(nodes); next_slots = [0]*len(slots)
		heads = [0]*expected[2]; slot_heads = [0]*expected[2]; previous = [0]*expected[2]; prior_slot = [0]*expected[2]
		declarations = [0]*symbols; binders = [0]*symbols
		for i, row in enumerate(nodes):
			f = row[1]-1; assert 0 <= f < len(heads)
			if previous[f]: next_nodes[previous[f]-1] = i+1
			else: heads[f] = i+1
			previous[f] = i+1
			if row[0] == 27:
				assert 0 < row[5] < symbols and not declarations[row[5]]
				declarations[row[5]] = i+1
		for i, row in enumerate(slots):
			f = row[3]-1; assert 0 <= f < len(slot_heads) and 0 < row[0] < symbols and not binders[row[0]]
			if prior_slot[f]: next_slots[prior_slot[f]-1] = i+1
			else: slot_heads[f] = i+1
			prior_slot[f] = i+1; binders[row[0]] = i+1
			if row[5]: assert not declarations[row[0]]
			else: assert declarations[row[0]] and nodes[declarations[row[0]]-1][1] == row[3]
		oracle = leaf/(label+'-expected.bin')
		arrays = [next_nodes, next_slots, heads, slot_heads, declarations, binders]
		oracle.write_bytes(b''.join(struct.pack('<'+str(len(row))+'i', *row) for row in arrays))
		captures.append(dict(label=label, paths=[str(directory/'core-nodes.bin'), str(directory/'storage-slots.bin'), str(oracle)], sizes=[len(nodes)*76, len(slots)*24, oracle.stat().st_size], counts=[len(nodes), len(slots), expected[2], symbols], lengths=list(map(len, arrays)), declarations=sum(bool(n) for n in declarations)))
	observer = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned char *data[2][3];
static const char *paths[2][3]=PATHS;
static const size_t sizes[2][3]=SIZES;
static const int counts[2][4]=COUNTS;
static const int lengths[2][6]=LENGTHS;
static void release(void) { for(int g=0;g<2;g++)for(int n=0;n<3;n++)free(data[g][n]); }
int physical_capture_count(int graph,int which) {
 if(graph<0||graph>1||which<0||which>3)exit(91);
 if(!data[graph][0]){for(int n=0;n<3;n++){FILE *f=fopen(paths[graph][n],"rb");data[graph][n]=malloc(sizes[graph][n]);if(!f||!data[graph][n]||fread(data[graph][n],1,sizes[graph][n],f)!=sizes[graph][n]||fclose(f))exit(92);}if(atexit(release))exit(93);}
 return counts[graph][which];
}
int physical_capture_get(int graph,int which,int index,int field) {
 if(graph<0||graph>1||which<0||which>1||index<0||index>=counts[graph][which]||field<0||field>5)exit(94);
 if(which==1&&field==5)return data[graph][1][index*24+20];
 int32_t value;memcpy(&value,data[graph][which]+index*(which?24:76)+field*4,4);return value;
}
int physical_expected(int graph,int which,int index) {
 if(graph<0||graph>1||which<0||which>5||index<0||index>=lengths[graph][which])exit(95);
 int offset=index;for(int n=0;n<which;n++)offset+=lengths[graph][n];int32_t value;memcpy(&value,data[graph][2]+offset*4,4);return value;
}
void physical_observed(int graph,int nodes,int slots,int declarations) { printf("%d %d %d %d\n",graph,nodes,slots,declarations); }
'''
	for token, key in [('PATHS', 'paths'), ('SIZES', 'sizes'), ('COUNTS', 'counts'), ('LENGTHS', 'lengths')]:
		observer = observer.replace(token, '{'+','.join('{'+','.join(json.dumps(value) for value in graph[key])+'}' for graph in captures)+'}')
	(leaf/'observer.c').write_text(observer)
	objects = []
	for name, path in [('observer', leaf/'observer.c'), ('args', ROOT/'lib/runtime/platform/args-posix.c')]:
		obj = build/(name+'.o'); run(name+'-build', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', path, '-o', obj]); objects.extend(['--link-object', obj])
	jobs = []
	for mode in ('O0', 'O2'):
		exe = '{work}/physical-index'
		jobs.append(dict(id=mode+'-build', argv=list(map(str, [a.compiler, '-'+mode, view, leaf/driver.name, *objects, '-o', exe])), expected_exit=0, timeout_seconds=300, estimated_RSS_bytes=1024**3, cache='fresh', artifacts=dict(executable=exe)))
		for case in ('small', 'original', 'current'):
			for memory in (False, True):
				argv = ['{artifact:'+mode+'-build:executable}', '--'+case]
				if memory: argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
				jobs.append(dict(id=mode+'-'+case+('-memory' if memory else ''), needs=[mode+'-build'], argv=argv, expected_exit=42, timeout_seconds=300, estimated_RSS_bytes=256*1024**2, cache='fresh'))
	tools = {str(a.compiler):sha(a.compiler), **{str(Path(shutil.which(name)).resolve()):sha(shutil.which(name)) for name in ('cc', 'valgrind')}}
	for job in jobs:
		job['tools'] = tools
		job['inputs'] = {str(path):sha(path) for path in [view, leaf/driver.name, leaf/'observer.c', *[Path(objects[i]) for i in (1, 3)], *map(Path, inputs)]}
	spec = dict(format='astra-native-jobs/1', jobs=jobs); write(leaf/'jobs.json', spec)
	result = run_jobs(spec, leaf/'jobs', build/'jobs', a.runtime_root/'physical-index-cache', jobs=4, max_jobs=4, reserve_bytes=8*1024**3, reuse=False)
	assert not result['failed_jobs'], result['failed_jobs']
	expected = dict(small=b'-1 16 15 5\n', original=b'0 284425 20656 13771\n', current=b'1 320662 22906 15288\n')
	for mode in ('O0', 'O2'):
		for case, out in expected.items():
			assert (leaf/'jobs'/(mode+'-'+case)/'stdout').read_bytes() == out
			memory = leaf/'jobs'/(mode+'-'+case+'-memory')
			assert (memory/'stdout').read_bytes() == out
			assert all(marker in (memory/'stderr').read_bytes() for marker in [b'in use at exit: 0 bytes in 0 blocks', b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
	assert driver.read_bytes() == (leaf/driver.name).read_bytes()
	assert all((ROOT/name).read_bytes() == data for name, data in zip(names, raw)) and all(sha(path) == digest for path, digest in inputs.items())
	write(leaf/'result.json', dict(status='FRESH_PHYSICAL_INDEX_REPLAYS_PASSED', production_sources={name:sha(ROOT/name) for name in names}, normalized_production_AST=selected, captured_inputs=inputs, driver_sha256=sha(leaf/driver.name), captures=captures, negative_source_twins=16, negative_index_twins=15, independent_dimension_negatives=4, restored_after_each=True, strict_memory_streams=6, products={mode:result['jobs'][mode+'-build']['artifacts']['executable'] for mode in ('O0', 'O2')}, scalar_differential_models=1024, full_original_native_credit=0, limitation='Exact production discovery/index kernels with minimal IDs, scalar discovery comparison and independent forward occurrence lists on captured original/current populations. Only discovery fields are loaded. No LLVM handles, integrated physical verifier, whole-source output or Stage1 credit.'))
	print('FRESH_PHYSICAL_INDEX_REPLAYS_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
