#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent original-AST/Binder reference oracle; never trusts generic maps.

Input is the read-only raw schema observer. Correspondence is reconstructed by
walking declaration roots and typed child edges, then matching exact declaration
node/token identities and scope owner/parent relations. Builder maps are compared
only after this reconstruction. Equal names/spans alone never identify symbols.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
from state import ROOT, sha


class Refusal(Exception):
	def __init__(self, category, detail):
		self.category, self.detail = category, detail
		super().__init__(category+': '+repr(detail))


def require(condition, category, detail):
	if not condition: raise Refusal(category, detail)


class Model:
	def __init__(self, path):
		self.tables = defaultdict(dict); self.edges = defaultdict(lambda: defaultdict(dict)); self.tokens = defaultdict(dict)
		self.maps = defaultdict(lambda: defaultdict(dict)); self.headers = {}; self.symbol_nodes = defaultdict(list)
		for line in Path(path).read_text().splitlines():
			r = line.split()
			if not r: continue
			label = r[0]
			if label.startswith('NEXT_CALL_'): continue
			if label == 'AST_EDGE':
				parent, field, position, child = int(r[1]), r[2], int(r[3]), int(r[4]); before = self.edges[parent][field].get(position, child); require(before == child, 'duplicate-ast-edge', r); self.edges[parent][field][position] = child
			elif label == 'AST_TOKEN':
				parent, field, token = int(r[1]), r[2], int(r[3]); before = self.tokens[parent].get(field, token); require(before == token, 'duplicate-ast-token', r); self.tokens[parent][field] = token
			elif label == 'AST_NODE':
				n = int(r[1]); values = tuple(map(int, r[2:])); require(self.headers.get(n, values) == values, 'duplicate-ast-node', r); self.headers[n] = values
			elif label.startswith('MAP_'):
				p, original, actual = map(int, r[1:]); require(original not in self.maps[label][p], 'duplicate-map-row', r); self.maps[label][p][original] = actual
			elif label == 'UNIVERSE': self.universe = tuple(map(int, r[1:]))
			elif label in ('TOKEN', 'SOURCE_ID'):
				key = int(r[1]); values = tuple(map(int, r[2:-1]))+(bytes.fromhex(r[-1]),); require(self.tables[label].get(key, values) == values, 'duplicate-token-source', r); self.tables[label][key] = values
			else:
				values = tuple(map(int, r[1:])); require(values[0] not in self.tables[label], 'duplicate-record', r); self.tables[label][values[0]] = values[1:]
		self.kinds = {int(code): name for name, code in re.findall(r'case SyntaxKind\.(\w+)\(\): \{\s*return (\d+);', (ROOT/'compiler/syntax/model.astra').read_text())}
		for symbol, row in self.tables['C_SYMBOL'].items(): self.symbol_nodes[row[0]].append(symbol)
		self.pairs, self.symbols, self.scopes = {}, {}, {}
		self.parents = defaultdict(set)
		for parent, fields in self.edges.items():
			for field, positions in fields.items():
				for child in positions.values():
					if child: self.parents[child].add((parent, field))


	def kind(self, node):
		return self.kinds[self.headers[node][0]]


	def children(self, node, field):
		return [child for _, child in sorted(self.edges[node].get(field, {}).items())]


	def child(self, node, field):
		values = self.children(node, field); return values[0] if values else 0


	def pairs_for(self, ordinal):
		plan = self.tables['INSTANCE'][ordinal]; origin, concrete, enclosing = plan[:3]
		pairs = {}; reverse = {}; roots = (self.tables['B_SYMBOL'][origin][0], self.tables['C_SYMBOL'][concrete][0])
		def walk(left, right):
			require(bool(left) == bool(right), 'missing-ast-child', (ordinal, left, right))
			if not left: return
			require(right > self.universe[0], 'original-clone-collision', (left, right))
			if left in pairs:
				require(pairs[left] == right, 'doubly-cloned-child', (ordinal, left, pairs[left], right)); return
			require(right not in reverse, 'merged-clone-child', (ordinal, left, right))
			require(self.headers[left] == self.headers[right], 'node-kind-source-span-depth', (ordinal, left, right))
			require(self.tokens[left] == self.tokens[right], 'ast-token-identity', (ordinal, left, right))
			pairs[left] = right; reverse[right] = left; kind = self.kind(left)
			fields = set(self.edges[left]) | set(self.edges[right])
			for field in sorted(fields):
				a, b = self.children(left, field), self.children(right, field)
				if field == 'where_clauses' and kind in ('ClassDeclarationSyntax', 'StructDeclarationSyntax', 'FunctionDeclarationSyntax'):
					require(not b, 'retained-generic-constraints', (ordinal, left)); continue
				if kind == 'ClassDeclarationSyntax' and field == 'methods':
					require(not b, 'retained-class-method-template', (ordinal, left)); continue
				if kind == 'ClassDeclarationSyntax' and field == 'members': a = [n for n in a if self.kind(n) in ('LifecycleDeclarationSyntax', 'StructFieldDeclarationSyntax')]
				if field == 'parameters' and left == roots[0] and enclosing:
					require(len(b) == len(a)+1, 'hidden-receiver-count', (ordinal, a, b)); b = b[1:]
					hidden = self.children(right, field)[0]; hidden_symbols = self.symbol_nodes[hidden]
					require(len(hidden_symbols) == 1, 'hidden-receiver-symbol', hidden)
					h = hidden_symbols[0]; require(self.tables['C_SYMBOL'][h][6] == concrete and self.tables['C_SYMBOL'][h][7] == 7 and self.tables['SYMBOL_TYPE'][h] == (enclosing, 2), 'hidden-receiver-owner-type-borrow', (ordinal, h))
					require(self.tables['TOKEN'][self.tokens[hidden]['name']][-1] == b'_astra_receiver' and self.tokens[hidden]['owned_keyword'] == 0 and self.tokens[hidden]['borrowed_keyword'] != 0, 'hidden-receiver-syntax', (ordinal, hidden))
				require(len(a) == len(b), 'ast-child-count', (ordinal, left, right, field, a, b))
				for l, r in zip(a, b): walk(l, r)
		walk(*roots)
		require(pairs == self.maps['MAP_NODE'][ordinal], 'builder-node-map-versus-ast', ordinal)
		self.pairs[ordinal] = pairs
		return pairs


	def bindings_for(self, ordinal):
		pairs = self.pairs[ordinal]; origin, concrete = self.tables['INSTANCE'][ordinal][:2]; symbols = {}; scopes = {}
		for n, source in self.tables['B_SYMBOL'].items():
			if source[7] == 9 or source[0] not in pairs: continue
			candidates = [c for c in self.symbol_nodes[pairs[source[0]]] if c > self.universe[1] and self.tables['C_SYMBOL'][c][1] == source[1]]
			require(len(candidates) == 1, 'exact-clone-symbol-node-token', (ordinal, n, candidates)); symbols[n] = candidates[0]
		require(symbols.get(origin) == concrete, 'origin-concrete-declaration', ordinal)
		for n, source in self.tables['B_SCOPE'].items():
			if source[0] not in pairs: continue
			candidates = [c for c, row in self.tables['C_SCOPE'].items() if c > self.universe[2] and row[0] == pairs[source[0]] and row[4] == source[4]]
			require(len(candidates) == 1, 'exact-clone-scope-node-kind', (ordinal, n, candidates)); scopes[n] = candidates[0]
		for n, c in symbols.items():
			a, b = self.tables['B_SYMBOL'][n], self.tables['C_SYMBOL'][c]
			require(a[1:5] == b[1:5] and a[8:11] == b[8:11], 'symbol-token-span-domain-name', (ordinal, n, c))
			require(a[7] == b[7] or n == origin and a[7] in (11, 12) and b[7] == 1, 'symbol-kind', (ordinal, n, c))
			require(b[5] == scopes.get(a[5], a[5]) and b[6] == symbols.get(a[6], a[6]), 'symbol-scope-owner', (ordinal, n, c))
		for n, c in scopes.items():
			a, b = self.tables['B_SCOPE'][n], self.tables['C_SCOPE'][c]
			require(b == (pairs[a[0]], symbols.get(a[1], a[1]), scopes.get(a[2], a[2]), *a[3:]), 'scope-parent-owner-unit', (ordinal, n, c))
		require(symbols == self.maps['MAP_SYMBOL'][ordinal], 'builder-symbol-map-versus-declarations', ordinal)
		require(scopes == self.maps['MAP_SCOPE'][ordinal], 'builder-scope-map-versus-ast', ordinal)
		self.symbols[ordinal], self.scopes[ordinal] = symbols, scopes


	def remap(self, ordinal, target):
		if target in self.symbols[ordinal]: return self.symbols[ordinal][target]
		enclosing = self.tables['INSTANCE'][ordinal][2]
		if enclosing:
			nominal = self.tables['TYPE'][enclosing][1]
			outer = [p for p, row in self.tables['INSTANCE'].items() if row[1] == nominal]
			if outer: return self.symbols[outer[0]].get(target, target)
		return target


	def receiver_type(self, reference):
		node, token, source, start, end, scope = reference[:6]; kind = self.kind(node)
		if kind == 'FieldInitializerSyntax':
			parents = [parent for parent, field in self.parents[node] if field == 'fields' and self.kind(parent) == 'StructInitializerSyntax']
			require(len(parents) == 1, 'initializer-field-parent', (reference, parents))
			return self.tables['USE'].get(parents[0], (0,))[0]
		place = self.child(node, 'receiver_place' if kind == 'CallExpressionSyntax' else 'aggregate')
		if place: return self.tables['USE'].get(place, (0,))[0]
		token = self.tokens[node].get('receiver' if kind == 'CallExpressionSyntax' else 'identifier', 0)
		if not token: return 0
		if self.tables['TOKEN'][token][-1] == b'this':
			owner = self.tables['C_SCOPE'][scope][1]; symbol = self.tables['C_SYMBOL'][owner]
			plans = [row for row in self.tables['INSTANCE'].values() if row[1] == owner]
			if plans and plans[0][2]: return plans[0][2]
			return self.tables['SYMBOL_TYPE'].get(symbol[6], (0,))[0]
		refs = [r for r in self.tables['C_REF'].values() if r[0] == node and r[1] == token and r[8] == 1]
		require(len(refs) == 1, 'receiver-binding-identity', (node, token, refs))
		return self.tables['SYMBOL_TYPE'][refs[0][6]][0]


	def member(self, reference, method=False):
		target = reference[6]; require(target in self.tables['C_SYMBOL'], 'dead-member-target', target)
		symbol = self.tables['C_SYMBOL'][target]; receiver = self.receiver_type(reference)
		require(receiver in self.tables['TYPE'], 'missing-receiver-type', (reference, receiver))
		kind, nominal = self.tables['TYPE'][receiver][:2]
		require(kind in (30, 31, 34), 'receiver-nominal-kind', (reference, receiver))
		if method:
			outer = [row for row in self.tables['INSTANCE'].values() if row[1] == nominal]
			if outer: nominal = outer[0][0]
		require(symbol[6] == nominal and (symbol[7] == 11 if method else symbol[7] in (6, 14)), 'member-exact-owner-kind', (reference, nominal, target, symbol))
		require(self.tables['TOKEN'][reference[1]][-1] == self.tables['TOKEN'][symbol[1]][-1], 'member-source-spelling', (reference, symbol))


	def chains(self):
		references = self.tables['C_REF']; seen = set()
		for node, (head,) in self.tables['REF_HEAD'].items():
			current, local = head, set()
			while current:
				require(current in references and current not in local and current not in seen, 'node-chain-gap-cycle-duplicate', (node, current))
				require(references[current][0] == node, 'node-chain-wrong-node', (node, current)); local.add(current); seen.add(current); current = self.tables['REF_NEXT'][current][0]
		require(seen == references.keys(), 'unlinked-reference', list(references.keys()-seen)[:5])
		seen = set()
		for symbol, row in self.tables['C_SYMBOL'].items():
			current, local = row[11], set()
			while current:
				require(current in references and current not in local and current not in seen, 'target-chain-gap-cycle-duplicate', (symbol, current))
				r = references[current]; require(r[6] == symbol and r[8] == 1, 'target-chain-wrong-target-state', (symbol, current)); local.add(current); seen.add(current); current = r[11]
		require(seen == {n for n, r in references.items() if r[8] == 1}, 'unlinked-bound-reference', len(seen))


	def verify(self):
		for ordinal in self.tables['INSTANCE']: self.pairs_for(ordinal)
		for ordinal in self.tables['INSTANCE']: self.bindings_for(ordinal)
		self.chains(); summaries = []; ranges = set()
		for ordinal, plan in self.tables['INSTANCE'].items():
			origin, concrete, enclosing, first, count, state, arguments = plan[:7]; pairs = self.pairs[ordinal]
			expected = [(n, self.tables['C_REF'][n]) for n in self.tables['B_REF'] if self.tables['B_REF'][n][0] in pairs]
			require(state == 2 and first > self.universe[3] and count == len(expected), 'reference-range-count', (ordinal, first, count, len(expected)))
			lexical = 0; completed = 0
			for offset, (source, original) in enumerate(expected):
				number = first+offset; require(number not in ranges and number in self.tables['C_REF'], 'reference-range-overlap-missing', (ordinal, number)); ranges.add(number)
				before, actual = self.tables['B_REF'][source], self.tables['C_REF'][number]
				require(before[:6] == original[:6] and before[10] == original[10], 'mutated-original-source-binding', source)
				require(actual[0] == pairs[original[0]] and actual[1:5] == original[1:5] and actual[10] == original[10], 'reference-order-node-token-span-domain', (ordinal, source, number))
				require(actual[5] == self.scopes[ordinal].get(original[5], original[5]), 'reference-scope', (ordinal, source, number))
				require(actual[7] == self.symbols[ordinal].get(original[7], original[7]), 'reference-alternative', (ordinal, source, number))
				if original[8] == 1:
					method = original[10] == 4 and self.tables['B_SYMBOL'].get(original[6], (0,)*8)[7] == 11
					target = original[6] if method else self.remap(ordinal, original[6])
					require(actual[8:10] == original[8:10] and actual[6] == target, 'reference-state-reason-target', (ordinal, source, number, target, actual))
					if method: self.member(actual, True); lexical += 1
				else:
					transition = original[8] == 5 and actual[8] == 1 and original[9] in (1, 3)
					if transition:
						require(actual[9] == 0 and actual[6] > 0, 'completed-reference-reason-target', (ordinal, source, number))
						require(self.kind(actual[0]) in ('CallExpressionSyntax', 'FieldAccessExpressionSyntax', 'FieldInitializerSyntax'), 'unproved-completion-syntax', actual)
						self.member(actual, self.kind(actual[0]) == 'CallExpressionSyntax')
						completed += 1
					else: require(actual[6] == original[6] and actual[8:10] == original[8:10], 'unapproved-state-transition', (ordinal, source, number))
					# Original source completion must itself retain its pre-check authority.
				if before[8] != original[8]:
					require(before[8] == 5 and original[8] == 1 and before[9] in (1, 3, 7) and original[9] == 0, 'original-completion-policy', (source, before, original))
					if before[9] == 7: require(original[6] == before[7], 'original-contextual-alternative', source)
					else:
						require(self.kind(original[0]) in ('CallExpressionSyntax', 'FieldAccessExpressionSyntax', 'FieldInitializerSyntax'), 'unproved-original-completion-syntax', original)
						self.member(original, self.kind(original[0]) == 'CallExpressionSyntax')
			summaries.append(dict(ordinal=ordinal, origin=origin, concrete=concrete, enclosing=enclosing, references=count, lexical_method_edges=lexical, deferred_member_completions=completed, reconstructed_ast_nodes=len(pairs), reconstructed_symbols=len(self.symbols[ordinal]), reconstructed_scopes=len(self.scopes[ordinal])))
		keys = [(row[0], row[2], row[6:]) for row in self.tables['INSTANCE'].values()]
		require(len(keys) == len(set(keys)), 'merged-or-duplicate-specialization-key', keys)
		return dict(status='PASS', input_sha256=None, instances=len(summaries), verified_references=sum(r['references'] for r in summaries), plans=summaries, independent_of='Generic builder decisions and all three exported maps; maps are checked only against independently reconstructed AST/declaration/scope correspondences')


def main():
	p = argparse.ArgumentParser(); p.add_argument('input', type=Path); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	try: result = Model(a.input).verify()
	except Refusal as error: result = dict(status='REFUSED', category=error.category, detail=error.detail)
	result['input_sha256'] = sha(a.input); result['oracle_sha256'] = sha(__file__)
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps({k: v for k, v in result.items() if k != 'plans'}))
	raise SystemExit(0 if result['status'] == 'PASS' else 1)


if __name__ == '__main__':
	main()
