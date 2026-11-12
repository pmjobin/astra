#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact owner helpers against scalar references and captured full-size graphs."""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha, declarations
from acceleration import execute, output_path, write


def between(raw, first, last):
	return raw[raw.index(first):raw.index(last)]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--cfg-dump', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('ssa-owner-packs-'+a.version), WORK/'runtime'); leaf.mkdir()
	build = output_path(a.build_root/leaf.name, WORK/'build'); build.mkdir()
	dump = output_path(a.cfg_dump, WORK/'runtime'); snapshot = json.loads((dump/'snapshot.json').read_text())
	names = ['compiler/ssa/recover.astra', 'compiler/ssa/recover-owners.astra', 'compiler/ssa/recover-owner-packs.astra', 'compiler/cfg/recover-model.astra', 'compiler/semantic/recover-model.astra', 'compiler/semantic/recover-storage.astra', 'compiler/core/recover.astra', 'compiler/core/recover-owners.astra']
	raw = {name:(ROOT/name).read_bytes() for name in names}; ssa, owners, packs, cfg, flow, storage, core, unwrap = raw.values()
	kernel = between(ssa, b'struct RecoverValue {', b'class RecoverSsa {')
	kernel += between(cfg, b'struct RecoverBlock {', b'class RecoverCfg {')
	kernel += between(flow, b'struct RecoverNode {', b'class RecoverFlowData {')
	kernel += between(flow, b'RecoverNode recover_empty(', b'// Keep mutable construction')
	kernel += between(storage, b'struct RecoverSlot {', b'class RecoverStorage {')
	kernel += between(core, b'struct RecoverCoreNode {', b'class RecoverCore {')
	kernel += between(unwrap, b'int recover_owner_unwrap(', b'bool recover_owner_value(')
	kernel += between(ssa, b'int recover_ssa_dominance_order(', b'int recover_ssa_definition(')
	kernel += between(ssa, b'bool recover_ssa_owner(', b'// Reconstruct declaration sites')
	kernel += between(owners, b'class RecoverSsaOwnerIndex {', b'bool recover_ssa_slots(')
	kernel += owners[owners.index(b'bool recover_ssa_temporary('):]+packs
	view = leaf/'production-kernel.astra'; view.write_bytes(kernel)
	model = Path(__file__).with_name('ssa-owner-packs-model.astra'); driver = Path(__file__).with_suffix('.astra')
	for path in (model, driver, Path(__file__)):
		(leaf/path.name).write_bytes(path.read_bytes())
	reference = subprocess.check_output(['git', 'show', '7676e12e40f4583f6834275e6ba089779faf41f9:compiler/ssa/recover-owners.astra'], cwd=ROOT)
	reference = between(reference, b'bool recover_ssa_slot(', b'bool recover_ssa_slots(')+reference[reference.index(b'bool recover_ssa_temporary('):]
	reference = reference.replace(b'recover_ssa_slot(', b'reference_slot(').replace(b'recover_ssa_temporary(', b'reference_temporary(')
	(leaf/'reference.astra').write_bytes(reference)
	commands = []
	def run(name, argv, expected=0, timeout=600):
		result = execute(argv, leaf/name, expected=expected, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, **result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result['exit'], (leaf/name/'stderr').read_text()[:1500])
		print(name, result['seconds'], flush=True)
		return (leaf/name/'stdout').read_bytes()
	run('toolchain', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'])
	full = []
	for i, (name, data) in enumerate(raw.items()):
		saved = leaf/('production-'+str(i)+'.astra'); saved.write_bytes(data)
		full.extend(declarations(run('AST-'+str(i), [a.compiler, '--dump-syntax', saved]).decode()))
	selected = declarations(run('AST-kernel', [a.compiler, '--dump-syntax', view]).decode())
	assert selected and all(full.count(row) == 1 for row in selected)
	files = ['blocks.bin', 'core-nodes.bin', 'values.bin', 'storage-slots.bin', 'entries.bin', 'owner-slots.bin', 'owner-consumers.bin', 'catch-try.bin', 'reachable.bin']
	inputs = {str(dump/name):sha(dump/name) for name in [*files, 'snapshot.json']}
	slots = list(struct.iter_unpack('<5i??2x', (dump/'storage-slots.bin').read_bytes())); symbols = max(row[0] for row in slots)+1
	observer = '''#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
static unsigned char *data[9];
static void cleanup(void) { for(int n=0;n<9;n++)free(data[n]); }
int owner_graph_start(void) {
 const char *paths[]=PATHS; size_t sizes[]=SIZES;
 for(int n=0;n<9;n++) { FILE *f=fopen(paths[n],"rb");data[n]=malloc(sizes[n]);if(!f||!data[n]||fread(data[n],1,sizes[n],f)!=sizes[n]||fclose(f))exit(91); }
 if(atexit(cleanup))exit(92);
 return NB;
}
int owner_graph_count(int which) { const int counts[]={NN,NF,NS,NV,NY};return counts[which]; }
int owner_graph_get(int which,int index,int field) {
 if(which==8)return data[8][index];
 if(which==3&&field>=5)return data[3][index*24+20+field-5];
 const int stride[]={40,76,20,24,4,4,4,4};int32_t value;__builtin_memcpy(&value,data[which]+index*stride[which]+field*4,4);return value;
}
void owner_observed(int stage,int count,int work) { printf("%d %d %d\\n",stage,count,work); }
'''
	observer = observer.replace('PATHS', '{'+','.join(json.dumps(str(dump/name)) for name in files)+'}').replace('SIZES', '{'+','.join(str((dump/name).stat().st_size) for name in files)+'}')
	for token, value in [('NB', snapshot['blocks']), ('NN', snapshot['nodes']), ('NF', snapshot['functions']), ('NS', snapshot['storage_slots']), ('NV', snapshot['values']), ('NY', symbols)]:
		observer = observer.replace(token, str(value))
	(leaf/'observer.c').write_text(observer); objects = []
	for name, path in [('observer', leaf/'observer.c'), ('args', ROOT/'lib/runtime/platform/args-posix.c')]:
		obj = build/(name+'.o'); run(name+'-build', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', path, '-o', obj]); objects.extend(['--link-object', obj])
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('owner-packs-'+mode)
		run(mode+'-build', [a.compiler, '-'+mode, view, leaf/model.name, leaf/driver.name, leaf/'reference.astra', *objects, '-o', exe])
		for case in ('small', 'temporary', 'graph'):
			out = run(mode+'-'+case, [exe, '--'+case], 42)
			memory = run(mode+'-'+case+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe, '--'+case], 42)
			assert out == memory
			assert all(marker in (leaf/(mode+'-'+case+'-memory')/'stderr').read_bytes() for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(profile=mode, ELF_sha256=sha(exe), graph_counters=(leaf/(mode+'-graph')/'stdout').read_text(), small_slot_models=8192, small_temporary_models=8192, reservation_boundaries=33, strict_memory_streams=3))
	assert all((ROOT/name).read_bytes() == data for name, data in raw.items()) and all(sha(path) == digest for path, digest in inputs.items())
	write(leaf/'result.json', dict(status='EXACT_OWNER_HELPER_REPLAYS_PASSED', production_sources={name:sha(ROOT/name) for name in names}, normalized_production_AST=selected, captured_inputs=inputs, products=products, full_original_native_credit=0, limitation='Exact production helpers in minimal containers under original C0. Scalar references retain7676 bodies with only names changed. Model arrays reconstruct captured fields; the combined work replay starts at the measured original checkpoint adjusted only for actual dominance work. No actual native verifier is altered and no full compiler admission, object or qualification follows.'))
	print('EXACT_OWNER_HELPER_REPLAYS_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
