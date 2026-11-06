#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Extend the established LLVM23 recipe with GENREF's separate consumers."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/genref24'
spec = importlib.util.spec_from_file_location('llvm_build', ROOT/'tests/selfhost-llvm/build.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
original = base.core.base.build


def build(*args, **kwargs):
	# The predecessor CLI remains byte-exact in Git. This explicit generated
	# test-only source renames its entrypoint so the new CLI can delegate to it.
	source = ROOT/'tests/selfhost-callplace/query.astra'; text = source.read_text()
	assert text.count('int main(string[] args)') == 1
	view = RUNTIME/'inherited-query.astra'; expected = text.replace('int main(string[] args)', 'int callplace_cli(string[] args)')
	if view.exists(): assert view.read_text() == expected
	else: view.write_text(expected)
	checker = (ROOT/'compiler/semantic/generic-check.astra').read_text()
	start = checker.index('bool generic_calls_verified('); end = checker.index('\nbool generic_token_equal(', start)
	diagnostic = checker[start:end].replace('bool generic_calls_verified(CheckedIndex index) {', 'bool genref_diagnose_calls(CheckedIndex index) throws Error {')
	count = 0; locations = []
	while 'return false;' in diagnostic:
		position = diagnostic.index('return false;'); count += 1
		locations.append(dict(reason=count, predicate_line=checker[start:end].splitlines()[diagnostic[:position].count('\n')]))
		diagnostic = diagnostic[:position]+'{ genref_call_stop(index, n, '+str(count)+'); return false_DIAGNOSTIC; }'+diagnostic[position+len('return false;'):]
	diagnostic = diagnostic.replace('return false_DIAGNOSTIC;', 'return false;')
	call_view = RUNTIME/'call-diagnostic.astra'; expected_diagnostic = '// Read-only observation of the unchanged separate call verifier.\n'+diagnostic
	if call_view.exists(): assert call_view.read_text() == expected_diagnostic
	else: call_view.write_text(expected_diagnostic)
	reasons = RUNTIME/'call-diagnostic-reasons.json'; expected_reasons = json.dumps(locations, indent=2)+'\n'
	if reasons.exists(): assert reasons.read_text() == expected_reasons
	else: reasons.write_text(expected_reasons)
	kwargs['consumer'] = ROOT/'tests/selfhost-genref/query.astra'
	kwargs['extra_sources'] = [*kwargs['extra_sources'], view, call_view, ROOT/'tests/selfhost-callplace/check.astra', ROOT/'tests/selfhost-genref/oracle-data.astra', ROOT/'tests/selfhost-genref/oracle-extra.astra', RUNTIME/'oracle-v1/raw-ast.astra']
	kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__), source, ROOT/'compiler/syntax/model.json', ROOT/'tests/selfhost-genref/oracle-generate.py']
	return original(*args, **kwargs)


if __name__ == '__main__':
	base.core.base.build = build
	base.main()
