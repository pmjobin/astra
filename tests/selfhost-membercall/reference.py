#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 checks of exact frozen methods/calls in disclosed dependency views."""
import json
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, COHORTS, read, sha


def declaration(path, spelling):
	data = path.read_bytes(); start = data.index(spelling.encode()); end = data.index(b'\n}', start)+2
	return data[start:end]+b'\n'


SUPPORT = '''class SyntaxArena {
	init() {}
	SyntaxTokenId get_token_identifier(SyntaxNodeId node) { SyntaxTokenId result = {index = node.index + 10}; return result; }
	SyntaxKind kind(SyntaxNodeId node) { return SyntaxKind.CallExpressionSyntax(); }
}
class SyntaxProgram {
	owned SyntaxArena arena;
	init() { var arena = new SyntaxArena(); this.arena = move arena; }
}
class BindingIndex {
	owned SyntaxProgram program;
	owned BindingReference[] references;
	init() { var program = new SyntaxProgram(); this.program = move program; this.references = new BindingReference[2]; }
	BindingReference reference(int n) { return this.references[n - 1]; }
}
class CheckedIndex {
	bool native_abi;
	owned BindingIndex bindings;
	owned SymbolId[] generic_calls;
	owned int[] node_references;
	owned int[] reference_next;
	init() { this.native_abi = false; var bindings = new BindingIndex(); this.bindings = move bindings; this.generic_calls = new SymbolId[4]; this.node_references = new int[4]; this.reference_next = new int[4]; }
}
void assert_that(bool value) { if (!value) { var none = new int[0]; int impossible = none[1]; } }
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v4'); a = p.parse_args()
	assert a.version.replace('-', '').isalnum()
	leaf = RUNTIME/('reference-'+a.version); leaf.mkdir(exist_ok=False); commands = []; results = []
	for name in COHORTS:
		ledger = read(RUNTIME.parent/'slotswap21'/('ledger-v1-'+name)/'ledger.json')
		files = {row['relative']: Path(row['path']) for row in ledger['files'] if row['relative'].startswith('compiler/')}
		model = files['compiler/semantic/flow-model.astra']; data = model.read_bytes(); start = data.index(b'class FlowGraph {'); end = data.index(b'\n}', start)+2
		graph = leaf/(name+'-FlowGraph.astra'); graph.write_bytes(data[:end]+b'\n')
		dependencies = leaf/(name+'-dependencies.astra')
		syntax = files['compiler/syntax/model.astra']; semantic = files['compiler/semantic/model.astra']
		content = b''.join(declaration(syntax, 'struct '+record+' {') for record in ('SyntaxNodeId', 'SyntaxTokenId', 'SyntaxListId', 'SyntaxSourceId', 'SyntaxSpan'))
		content += declaration(syntax, 'enum SyntaxKind {')
		content += b''.join(declaration(semantic, 'struct '+record+' {') for record in ('SymbolId', 'ScopeId', 'BindingReference'))
		content += declaration(files['compiler/semantic/types.astra'], 'struct TypeId {')
		content += declaration(files['compiler/syntax/arena-support.astra'], 'int syntax_grown_capacity(')
		content += declaration(files['compiler/syntax/arena-support.astra'], 'SyntaxSpan syntax_empty_span(')
		content += declaration(files['compiler/semantic/types.astra'], 'SymbolId type_symbol(')
		content += SUPPORT.encode(); dependencies.write_bytes(content)
		helper = leaf/(name+'-checked-target.astra'); helper.write_bytes(declaration(files['compiler/semantic/checked.astra'], 'SymbolId checked_target('))
		# Only original/LLVM23-base use this historical small helper; later helpers
		# have additional private-instance dependencies, outside this C0 view.
		use_helper = name in ('original', 'LLVM23-base')
		probe = leaf/(name+'-calls.astra')
		call = 'graph.slot_for(checked_target(checked, direct, checked.bindings.program.arena.get_token_identifier(direct)))' if use_helper else 'graph.slot_for(symbol)'
		probe.write_text('int probe(borrowed FlowGraph graph, CheckedIndex checked, SyntaxNodeId direct, SymbolId symbol, FlowEvent bad) { int result = '+call+'; return result + graph.add(bad); }\n')
		sources = [dependencies, graph, *([helper] if use_helper else []), probe]
		for label,argv in [('syntax',[C0,'--dump-syntax',*sources]),('check',[C0,'--check',*sources])]:
			prefix = name+'-'+label; start_time = time.monotonic()
			process = subprocess.Popen(['/usr/bin/time','-v','-o',str(leaf/(prefix+'.time')),*map(str,argv)],cwd=BUILD,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
			try: out,err = process.communicate(timeout=120)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid,signal.SIGTERM); out,err = process.communicate(); raise
			(leaf/(prefix+'.stdout')).write_bytes(out); (leaf/(prefix+'.stderr')).write_bytes(err)
			commands.append(dict(name=prefix,argv=list(map(str,argv)),exit=process.returncode,start=start_time,end=time.monotonic()))
			(leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			print(prefix,process.returncode,err.decode()[:2000],flush=True)
			assert process.returncode == 0
		results.append(dict(cohort=name,sources={str(path):sha(path) for path in sources},original_graph_sha256=sha(model),complete_FlowGraph_bytes_equal=graph.read_bytes()==data[:end]+b'\n',original_nested_call=use_helper,limitation='C0 checking only, no native or runtime claim. Complete original FlowGraph and model records; exact original checked_target for the first two cohorts. CheckedIndex/BindingIndex/Program/Arena are explicitly bounded support views; synthetic Arena token accessor. Original throwing caller functions are not replaced or claimed executed.'))
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_BOUNDED_CHECKS_PASS',results=results,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
