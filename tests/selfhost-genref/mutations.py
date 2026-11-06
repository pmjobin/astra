#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require real generic-reference verifier refusals with restored valid twins."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, read, sha

CATEGORIES = ('range-start-zero', 'missing-reference', 'extra-reference', 'shifted-reference-order', 'original-clone-node-collision', 'wrong-token', 'wrong-span-start', 'wrong-span-end', 'wrong-source', 'wrong-domain', 'stale-source-scope', 'unmapped-parameter-target', 'dead-target', 'wrong-alternative', 'forged-resolution-reason', 'unresolved-concrete-state', 'node-chain-cycle', 'missing-node-chain', 'node-chain-out-of-range', 'missing-reverse-target-chain', 'reverse-target-cycle', 'reverse-target-out-of-range', 'negative-reference-count', 'method-versus-executable-target', 'wrong-member-Class-owner', 'swapped-reference-pair')


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('models-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	case = next(row for row in read(RUNTIME/'corpus-v5/selection.json') if row['name'] == 'recursive-member-binding'); assert all(sha(s['path']) == s['sha256'] for s in case['sources'])
	argv = [str(a.component), *[s['path'] for s in case['sources']]]; start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'models.time', *argv], cwd=BUILD, capture_output=True, timeout=180)
	(leaf/'models.stdout').write_bytes(r.stdout); (leaf/'models.stderr').write_bytes(r.stderr); command = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic()); (leaf/'commands.json').write_text(json.dumps([command], indent=2)+'\n')
	assert r.returncode == 0, r.stderr.decode()
	rows = [line.split() for line in r.stdout.decode().splitlines() if line.startswith('GENREF_MODEL_MUTATION ')]
	assert len(rows) == len(CATEGORIES) and {int(row[1]) for row in rows} == set(range(len(CATEGORIES))) and all(row[2:] == ['7', 'VALID_RESTORED'] for row in rows)
	mutations = [dict(category=CATEGORIES[int(row[1])], ordinal=int(row[1]), consumer='Independent generic-reference verifier', stage=7, valid_twin_restored=True) for row in rows]
	transition = next(row for row in read(RUNTIME/'corpus-v5/selection.json') if row['name'] == 'generic-recursive-member'); assert all(sha(s['path']) == s['sha256'] for s in transition['sources'])
	argv = [str(a.component), '--transitions', *[s['path'] for s in transition['sources']]]; start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'transitions.time', *argv], cwd=BUILD, capture_output=True, timeout=180)
	(leaf/'transitions.stdout').write_bytes(r.stdout); (leaf/'transitions.stderr').write_bytes(r.stderr); commands = [command, dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic())]; (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
	assert r.returncode == 0, r.stderr.decode()
	extra = [line.split() for line in r.stdout.decode().splitlines() if line.startswith('GENREF_TRANSITION_MUTATION ')]; assert len(extra) == 11 and {int(row[1]) for row in extra} == set(range(11))
	names = ('completed-field-to-concrete-function', 'completed-field-to-Class', 'completed-field-to-unspecialized-field', 'disallowed-deferred-reason-7', 'disallowed-deferred-reason-0', 'completed-reference-wrong-reason', 'completed-reference-wrong-domain', 'completed-reference-extra-alternative', 'completed-reference-stale-scope', 'completed-reference-wrong-token', 'completed-reference-dead-target')
	for row in extra:
		ordinal, before, stage = map(int, row[1:4]); assert before == (0 if ordinal < 3 else 7) and stage == 7 and row[4] == 'VALID_RESTORED'
		mutations.append(dict(category=names[ordinal], ordinal=len(CATEGORIES)+ordinal, consumer='Independent generic-reference verifier', retained_v1_predicate=before, stage=stage, reverse_linkage_valid_before_target_check=True, valid_twin_restored=True))
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), source=case['sources'], transition_source=transition['sources'], mutations=mutations, commands=commands, limitation='Actual in-memory reference-model corruptions. Three validly linked wrong deferred-member targets expose a real v1 predicate acceptance and are refused by the final verifier. The unspecialized field retains the exact original token but has the wrong nominal owner. These are not parser denials or native application executions.'), indent=2)+'\n'); print(a.mode, len(mutations), 'reference mutants rejected; all valid twins restored')


if __name__ == '__main__':
	main()
