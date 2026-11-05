#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the actual original CfgWalk declaration to its independent bounded view."""
import importlib.util
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, sha, read


def main():
	leaf = RUNTIME/'diagnosis'; leaf.mkdir(exist_ok=False); commands = []
	selection = next(row for row in read(RUNTIME/'frozen-v2/selection.json') if row['name'] == 'original-CfgWalk')
	sources = [row['path'] for row in selection['sources']]
	c0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'
	old = ROOT.parent/'codex/work/astra/build/textclass17/native-v10-O0/astra-llvm-O0'
	def run(args, name, expected):
		start = time.monotonic(); r = subprocess.run(list(map(str, args)), capture_output=True, timeout=120)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, args)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.stderr[-1200:]); return r.stdout
	spec = importlib.util.spec_from_file_location('abi_probe', ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	original = ROOT/'compiler/cfg/consume.astra'; view = Path(sources[1])
	full = probe.syntax(run([c0, '--dump-syntax', original], 'original-C0-AST', 0).decode())
	bounded = probe.syntax(run([c0, '--dump-syntax', view], 'view-C0-AST', 0).decode())
	assert bounded == [full[0], next(row for row in full[1:] if row[:2] == ['class', 'CfgWalk'])]
	before = run([old, '--classstorage-admit', 'O0', leaf/'unused', *sources], 'predecessor-original-admit', 1)
	assert b'generic body syntax lacks a concrete specialization contract'.hex().encode() in before
	(leaf/'result.json').write_text(json.dumps(dict(classification='OBSERVED_FAILURE_AND_PINNED_SOURCE_CAUSAL_TRACE', original_sha256=sha(original), original_span=[650, 664], stopped_bytes=original.read_bytes()[650:664].decode(), complete_expression=original.read_bytes()[650:670].decode(), C0_AST_declaration_equal=True, view_sha256=sha(view), predecessor_component_sha256=sha(old), baseline_cohorts=sha(RUNTIME/'initial/result.json'), causal_path=['Every private Class method is elaborated as a concrete body, including non-generic CfgWalk.inspect.', 'generic_select_call calls generic_copy_node while copying the specialized method body.', 'IndexExpressionSyntax for d.functions[f] is absent from generate-specialization.py NAMES; generic_copy_node takes its explicit missing-contract failure branch at the original index span.', 'The separate generic structural consumer omits the same syntax schema.', 'After that obstruction, the old Core lowerer lacks an IndexExpressionSyntax value operation and only projects FieldAccessExpressionSyntax through an authoritative static Place. Dynamic copied record-member reads cannot use that schema.'], boundary='The frozen original failure is reproduced, as is the identical bounded original declaration. C0 executable oracles are independent. Full original CfgData shared identity, exception-facing cfg_walk wrappers and unrelated compiler modules remain outside this bounded operation witness.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
