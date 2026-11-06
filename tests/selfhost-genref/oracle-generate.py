#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generate a raw AST observer from the syntax schema, independently of generics.

The resulting field/edge records have no acceptance authority. The Python oracle
reconstructs correspondence from original declaration roots and these AST edges.
Neither generator nor consumer reads the generic copier or its structural checker.
"""
import argparse
import json
from pathlib import Path
import re
from state import ROOT, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert not a.output.resolve().is_relative_to(ROOT)
	schema = ROOT/'compiler/syntax/model.json'; model = json.loads(schema.read_text())['nodes']
	accessors = (ROOT/'compiler/syntax/arena.astra').read_text()
	names = dict(re.findall(r'\b(\w+)SyntaxData (\w+)\(SyntaxNodeId (?:node|id)\)', accessors))
	lines = ['// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception', '// Generated read-only raw AST field observer; schema SHA-256 '+sha(schema),
		'void genref_ast_token(SyntaxArena arena, SyntaxNodeId node, string field, SyntaxTokenId token, Utf8ByteBuilder out) throws Error {',
		'\tsource_append_text(out, "AST_TOKEN"); flow_number(out, node.index); source_append_text(out, " "); source_append_text(out, field); flow_number(out, token.index); source_append_text(out, "\\n");', '}', '',
		'void genref_ast_edge(SyntaxArena arena, SyntaxNodeId parent, string field, int position, SyntaxNodeId child, bool[] seen, Utf8ByteBuilder out) throws Error {',
		'\tsource_append_text(out, "AST_EDGE"); flow_number(out, parent.index); source_append_text(out, " "); source_append_text(out, field); flow_number(out, position); flow_number(out, child.index); source_append_text(out, "\\n");',
		'\tgenref_ast(arena, child, seen, out);', '}', '',
		'void genref_ast(SyntaxArena arena, SyntaxNodeId node, bool[] seen, Utf8ByteBuilder out) throws Error {',
		'\tif (node.index == 0 || seen[node.index]) return;', '\tseen[node.index] = true;',
		'\tvar h = arena.header(node); source_append_text(out, "AST_NODE"); flow_number(out, node.index); flow_number(out, h.kind_code); flow_number(out, h.span.source.index); flow_number(out, h.span.start); flow_number(out, h.span.end); flow_number(out, h.depth); source_append_text(out, "\\n");',
		'\tmatch (arena.kind(node)) {']
	for name, row in sorted(model.items()):
		if row['abstract']: continue
		short = name.removesuffix('Syntax'); accessor = names.get(short)
		assert accessor, name
		lines += ['\t\tcase SyntaxKind.'+name+'(): {', '\t\t\tvar data = arena.'+accessor+'(node);']
		for field, kind in row['fields'].items():
			if field in ('foreign_member', 'foreign_channels', 'module_internal'): continue
			value = 'data.f_'+field
			if kind.rstrip('?') in model:
				lines += ['\t\t\tgenref_ast_edge(arena, node, "'+field+'", 0, '+value+', seen, out);']
			elif kind.startswith('GenericArray<') and kind[13:-1] in model:
				lines += ['\t\t\tint '+field+'_at = 0;', '\t\t\twhile ('+field+'_at < arena.list_count('+value+')) {', '\t\t\t\tgenref_ast_edge(arena, node, "'+field+'", '+field+'_at, arena.node_at('+value+', '+field+'_at), seen, out);', '\t\t\t\t'+field+'_at = '+field+'_at + 1;', '\t\t\t}']
			elif kind.rstrip('?') == 'Token':
				lines += ['\t\t\tgenref_ast_token(arena, node, "'+field+'", '+value+', out);']
		lines += ['\t\t}']
	lines += ['\t\telse: { assert_that(false); }', '\t}', '}', '']
	a.output.parent.mkdir(parents=True, exist_ok=True); a.output.write_text('\n'.join(lines))
	print(a.output, sha(a.output), len(lines), 'raw-schema observer lines')


if __name__ == '__main__':
	main()
