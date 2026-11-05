#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind immutable source/AST/checked-prefix facts to read-only observations."""
import importlib.util
import hashlib
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, COHORTS, read, sha, digest, population


def find(tree, tag, name):
	if not isinstance(tree,list): return []
	matched = tree[:1] == [tag] and (['name',name] in tree or tag == 'class' and tree[1:2] == [name])
	return ([tree] if matched else [])+[found for child in tree for found in find(child,tag,name)]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	leaf = RUNTIME/('facts-'+a.version); leaf.mkdir(exist_ok=False); commands = []; rows = {}
	spec = importlib.util.spec_from_file_location('probe',ROOT/'tests/selfhost-classstorage/abi-probe.py')
	probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	def syntax(path,name):
		start = time.monotonic(); argv = [C0,'--dump-syntax',path]
		r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=BUILD,capture_output=True,timeout=60)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == 0
		return probe.syntax(r.stdout.decode())
	for name in COHORTS:
		ledger = read(PRIOR/('ledger-v1-'+name)/'ledger.json'); original = read(RUNTIME/'initial.json')['cohorts'][name]; logical,nodes = population(ledger)
		assert digest(logical) == original['population_sha256'] and digest(nodes) == original['node_identity_sha256']
		stop = original['first_stop']; path = Path(stop['path']); raw = path.read_bytes()
		call = next(row for row in ledger['nodes'] if row['path'] == stop['path'] and row['start'] == stop['start'] and row['end'] == stop['end'] and row['syntax_kind'] == 15)
		function = ledger['declarations'][str(call['function_symbol'])]; function_bytes = raw[function['start']:function['end']]
		assert b'throws Error' in function_bytes.split(b'{',1)[0]
		ast = syntax(path,name+'-caller'); methods = find(ast,'function',function['name']); assert len(methods) == 1
		graph_path = next(Path(row['path']) for row in ledger['files'] if row['relative'] == 'compiler/semantic/flow-model.astra')
		graph_ast = syntax(graph_path,name+'-model'); graph = find(graph_ast,'class','FlowGraph'); assert len(graph) == 1
		view = syntax(RUNTIME/'reference-v4'/(name+'-FlowGraph.astra'),name+'-graph-view')
		assert find(view,'class','FlowGraph') == graph
		signatures = {}
		for method in ('slot_for','add'):
			selected = find(graph[0],'method',method); assert len(selected) == 1
			signatures[method] = selected[0]
		rows[name] = dict(population_sha256=digest(logical),node_identity_sha256=digest(nodes),first_stop=stop,call_node=call,call_bytes_hex=raw[stop['start']:stop['end']].hex(),enclosing_function=function,enclosing_bytes_sha256=hashlib.sha256(function_bytes).hexdigest(),enclosing_AST_sha256=digest(methods[0]),enclosing_AST=methods[0],declared_effect='throws Error',FlowGraph_source=str(graph_path),FlowGraph_source_sha256=sha(graph_path),FlowGraph_view_AST_equal=True,method_ASTs=signatures,prefix_uses=[row for row in ledger['nodes'] if row['path'] == stop['path'] and row['start'] >= stop['start']-180 and row['end'] <= stop['end']],observation_path=str(RUNTIME/'diagnosis-v3'/(name+'.stdout')),limitation='Read-only pre-repair facts. No source advancement, body effect proof, complete caller native execution or Stage 1 is claimed.')
		print(name,call['node'],function['name'],'throws Error; exact FlowGraph AST verified',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(format='astra-membercall22-source-facts/1',cohorts=rows,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
