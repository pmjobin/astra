#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute exact production dominance code against independently solved graphs."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
GRAPHS = [
	[(2, 0), (3, 0), (4, 0), (0, 0)],
	[(2, 3), (4, 0), (4, 0), (0, 0)],
	[(2, 0), (3, 4), (2, 0), (0, 0)],
	[(2, 0), (3, 6), (4, 5), (3, 0), (2, 0), (0, 0)],
	[(2, 0), (0, 0), (4, 0), (0, 0)],
	[(2, 3), (4, 5), (4, 5), (6, 0), (6, 0), (0, 0)],
]


def oracle(graph):
	reachable = {1}; pending = [1]
	while pending:
		for target in graph[pending.pop()-1]:
			if target and target not in reachable: reachable.add(target); pending.append(target)
	predecessors = {n:set() for n in reachable}
	for n in reachable:
		for target in graph[n-1]:
			if target: predecessors[target].add(n)
	dominators = {n:({1} if n == 1 else set(reachable)) for n in reachable}
	changed = True
	while changed:
		changed = False
		for n in sorted(reachable-{1}):
			value = {n}|set.intersection(*(dominators[p] for p in predecessors[n]))
			if value != dominators[n]: dominators[n] = value; changed = True
	return {(definition, use):use not in reachable or definition in dominators[use] for definition in range(1, len(graph)+1) for use in range(1, len(graph)+1)}


def extract(text, marker):
	start = text.index(marker); opening = text.index('{', start); depth = 1; end = opening+1
	while depth:
		if text[end] == '{': depth += 1
		if text[end] == '}': depth -= 1
		end += 1
	return text[start:end]+'\n'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('compiler', 'c0', 'build', 'runtime'): p.add_argument('--'+key, type=Path, required=True)
	for key in ('compiler', 'c0'): p.add_argument('--'+key+'-sha256', required=True)
	a = p.parse_args()
	for key in ('compiler', 'c0'): assert re.fullmatch('[0-9a-f]{64}', getattr(a, key+'_sha256')) and sha(getattr(a, key)) == getattr(a, key+'_sha256')
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	ssa = ROOT/'compiler/ssa/recover.astra'; cfg = ROOT/'compiler/cfg/recover-model.astra'; text = ssa.read_text()
	fragments = [extract(cfg.read_text(), 'struct RecoverBlock {'), extract(text, 'class RecoverWork {'), extract(text, 'int recover_ssa_dominance_order('), extract(text, 'bool recover_ssa_build_dominance('), extract(text, 'bool recover_ssa_dominates(')]
	fixture = 'extern(C) void report_cost(int graph, int remaining);\n'+'\n'.join(fragments)
	for ordinal, graph in enumerate(GRAPHS):
		fixture += 'int graph'+str(ordinal)+'() {\nvar blocks = new RecoverBlock['+str(len(graph))+'];\n'
		for index, (next_, other) in enumerate(graph):
			fixture += f'blocks[{index}].function = 1; blocks[{index}].next = {next_}; blocks[{index}].other = {other};\n'
		fixture += f'var entries = new int[1]; entries[0] = 1; var work = new RecoverWork(8000000); if (!recover_ssa_build_dominance(blocks, {len(graph)}, entries, work)) return 1;\n'
		for (definition, use), expected in oracle(graph).items():
			fixture += f'if (recover_ssa_dominates({definition}, {use}, work) != '+('true' if expected else 'false')+') return 2;\n'
		fixture += f'report_cost({ordinal}, work.remaining); return 0;\n}}\n'
	fixture += '''int scale() {
	int count = 100000; var blocks = new RecoverBlock[count]; int i = 0;
	while (i < count) { blocks[i].function = 1; if (i+1 < count) blocks[i].next = i+2; i = i+1; }
	var entries = new int[1]; entries[0] = 1; var work = new RecoverWork(8000000);
	if (!recover_ssa_build_dominance(blocks, count, entries, work) || work.exhausted || !recover_ssa_dominates(1, count, work) || recover_ssa_dominates(count, 1, work)) return 3;
	report_cost(100, work.remaining);
	var small = new RecoverWork(2); if (recover_ssa_build_dominance(blocks, count, entries, small) || !small.exhausted) return 4;
	blocks[0].next = count+1; var invalid = new RecoverWork(8000000); if (recover_ssa_build_dominance(blocks, count, entries, invalid)) return 5;
	return 0;
}
int main() {
'''
	for ordinal in range(len(GRAPHS)): fixture += f'if (graph{ordinal}() != 0) return {ordinal+1};\n'
	fixture += 'if (scale() != 0) return 20; return 42;\n}\n'
	source = runtime/'dominance.astra'; source.write_text(fixture)
	bridge = runtime/'cost.c'; bridge.write_text('#include <stdio.h>\nvoid report_cost(int graph,int remaining) { printf("%d:%d\\n",graph,remaining); }\n')
	inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), ssa, cfg, source, bridge)}
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('gcc', 'cc', 'as', 'ld', 'valgrind', 'opt', 'llc')]])
	write(runtime/'identity.json', dict(inputs=inputs, tools=tools, fragment_sha256=[__import__('hashlib').sha256(v.encode()).hexdigest() for v in fragments], oracle='Independent predecessor-set fixed-point dominators; unreachable-use convention matches the production contract.', scope='Exact read-only extracted production code in a focused component; no substitute algorithm, source edit or compiler acceptance credit.'))
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []; products = {}; observed = None
	def run(name, argv, expected=0):
		argv = list(map(str, argv)); r = execute(argv, runtime/name, expected=expected, timeout=600, env=env)
		commands.append(dict(name=name, argv=argv, result=r)); write(runtime/'commands.json', commands)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
		return (runtime/name/'stdout').read_bytes()
	obj = build/'cost.o'; run('cost-bridge', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', obj])
	for kind, compiler in [('C0', a.c0), ('Astra', a.compiler)]:
		for mode in ('O0', 'O2'):
			name = kind+'-'+mode; target = build/name
			if kind == 'C0': run(name+'-compile', [compiler, '-'+mode, source, '--link-object', obj, '-o', target])
			else:
				object_ = build/(name+'.o'); run(name+'-compile', [compiler, '-c', '-'+mode, '-o', object_, source]); run(name+'-link', ['cc', '-no-pie', object_, obj, '-o', target])
			out = run(name+'-native', [target], 42)
			if observed is None: observed = out
			assert out == observed
			if mode == 'O2':
				run(name+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 42)
				log = (runtime/(name+'-memory')/'stderr').read_bytes(); assert all(v in log for v in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			products[str(target)] = sha(target)
	assert all(sha(path) == h for path, h in {**inputs, **tools, **products}.items())
	write(runtime/'result.json', dict(status='FOCUSED_PRODUCTION_DOMINANCE_COMPONENT_PASS', compiler_sha256=a.compiler_sha256, finite_graphs=len(GRAPHS), scale_blocks=100000, work_limit=8000000, observed_remaining=observed.decode().splitlines(), products=products, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), scope='Actual extracted algorithm, independent graph expectations and all backend/optimization combinations; does not diagnose or qualify the entire compiler graph by itself.'))
	print('FOCUSED_PRODUCTION_DOMINANCE_COMPONENT_PASS', observed.decode(), flush=True)


if __name__ == '__main__': main()
