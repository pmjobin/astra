#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Extend the unchanged GENREF CLI with read-only EFFECTS observers."""
import argparse
import json
from pathlib import Path
import sys
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, load_module

INPUTS = RUNTIME/'compiler-inputs-v1'


def prepare():
	INPUTS.mkdir(exist_ok=True)
	def write(name, data):
		path = INPUTS/name; path.parent.mkdir(parents=True, exist_ok=True)
		if path.exists(): assert path.read_bytes() == data
		else: path.write_bytes(data)
	for name in ('inherited-query.astra', 'call-diagnostic.astra', 'call-diagnostic-reasons.json', 'oracle-v1/raw-ast.astra'):
		write(name, (PRIOR/name).read_bytes())
	text = (ROOT/'tests/selfhost-genref/query.astra').read_text(); assert text.count('int main(string[] args)') == 1
	write('genref-query.astra', text.replace('int main(string[] args)', 'int genref_cli(string[] args)').encode())
	checker = (ROOT/'compiler/semantic/flow-check.astra').read_text(); start = checker.index('bool flow_verify('); end = checker.index('\nSyntaxNodeId flow_node(', start)
	text = checker[start:end].replace('bool flow_verify(', 'int effects_flow_diagnose('); reasons = []; count = 0
	while 'return false;' in text:
		at = text.index('return false;'); count += 1
		reasons.append(dict(reason=count, source_line=checker[:start].count('\n')+text[:at].count('\n')+1))
		text = text[:at]+'return '+str(count)+';'+text[at+len('return false;'):]
	condition = 'return flow_source_matches(graph, checked, class_origins) && (!checked.semantic_flow || flowsem_verify_demands(graph, checked));'
	assert text.count(condition) == 1
	text = text.replace(condition, 'if (!(flow_source_matches(graph, checked, class_origins) && (!checked.semantic_flow || flowsem_verify_demands(graph, checked)))) return '+str(count+1)+'; return 0;')
	reasons.append(dict(reason=count+1, predicate=condition))
	write('flow-diagnostic.astra', text.encode()); write('flow-diagnostic-reasons.json', (json.dumps(reasons, indent=2)+'\n').encode())
	text = (ROOT/'tests/selfhost-effects/observe.astra').read_text()
	assert text.count('int main(string[] args)') == 1 and text.count('binding_load_program(args, 1)') == 1
	text = text.replace('int main(string[] args)', 'int effects_cli(string[] args, int start)').replace('binding_load_program(args, 1)', 'binding_load_program(args, start)')
	source_trace = '''effects_trace(checked);
		var root = effect_source_root(checked); int s = 1;
		while (s <= checked.generic_symbols) {
			if (checked.bindings.symbol(type_symbol(s)).kind == 1) {
				var result = effect_source_result(checked, type_symbol(s)); var bound = effect_source_bound(checked, type_symbol(s));
				if (result.index > 0 || bound.index > 0) {
					int within = 0; if (effect_source_subtype(checked, bound, root)) within = 1;
					var out = new Utf8ByteBuilder(); source_append_text(out, "SOURCE_SIGNATURE"); flow_number(out, s); flow_number(out, result.index); flow_number(out, bound.index); flow_number(out, root.index); flow_number(out, within); var text = out.snapshot(); println(text.text);
				}
			}
			s = s + 1;
		}'''
	assert text.count('effects_trace(checked);') == 1; text = text.replace('effects_trace(checked);', source_trace)
	anchor = 'var observation = flow_observation(flow); print(observation.text);'
	diagnostic = '''int g = 0;
		while (g < flow.graphs.count()) {
			int reason = effects_flow_diagnose(flow.graphs.entries[g], flow.checked, flow.class_origins);
			assert_that((reason == 0) == flow_verify(flow.graphs.entries[g], flow.checked, flow.class_origins));
			if (reason != 0) {
				var out = new Utf8ByteBuilder(); source_append_text(out, "FLOW_VERIFY_STOP"); flow_number(out, g + 1); flow_number(out, reason); var text = out.snapshot(); println(text.text);
			}
			g = g + 1;
		}
		'''
	assert text.count(anchor) == 1; text = text.replace(anchor, diagnostic+anchor)
	write('effects-observe.astra', text.encode())
	print('Explicit test-only entrypoint/diagnostic views prepared; original compiler predicates unchanged', flush=True)


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2')); p.add_argument('--prepare', action='store_true'); a = p.parse_args()
	prepare()
	if a.prepare: return
	assert a.mode
	genref = load_module('effects_genref_build', ROOT/'tests/selfhost-genref/build.py'); genref.RUNTIME = INPUTS
	original = genref.original
	def extend(*args, **kwargs):
		kwargs['consumer'] = ROOT/'tests/selfhost-effects/query.astra'
		kwargs['extra_sources'] = [*kwargs['extra_sources'], INPUTS/'genref-query.astra', INPUTS/'flow-diagnostic.astra', INPUTS/'effects-observe.astra', ROOT/'tests/selfhost-effects/source.astra']
		kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__), ROOT/'tests/selfhost-effects/observe.astra']
		return original(*args, **kwargs)
	genref.original = extend; genref.base.core.base.build = genref.build
	sys.argv = [sys.argv[0], '--compiler', str(C0), '--build', str(BUILD/('compiler-v1-'+a.mode)), '--runtime', str(RUNTIME/('compiler-build-v1-'+a.mode)), '--mode', a.mode]
	genref.base.main()


if __name__ == '__main__':
	main()
