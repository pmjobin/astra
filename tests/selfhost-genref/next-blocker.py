#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the next actual call-verifier stop to immutable original source facts."""
import argparse
import json
from pathlib import Path
from oracle import Model
from state import RUNTIME, PRIOR, COHORTS, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--data', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('next-blocker-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False); results = {}
	for name in COHORTS:
		path = a.data/(name+'.stdout'); raw = path.read_text(); m = Model(path); reference = m.verify(); reference['input_sha256'] = sha(path); reference['oracle_sha256'] = sha(Path(__file__).with_name('oracle.py')); assert reference['status'] == 'PASS' and m.universe[-1] == 25
		facts = [line.split() for line in raw.splitlines() if line.startswith('NEXT_CALL_')]
		failure = next(row for row in facts if row[0] == 'NEXT_CALL_FAILURE'); reason, node, target, result_type, flags, deferred = map(int, failure[1:]); assert reason == 13 and deferred == 19
		span = next(row for row in facts if row[0] == 'NEXT_CALL_SPAN'); source = Path(bytes.fromhex(span[1]).decode()); start, end = map(int, span[2:]); text = source.read_bytes()[start:end]; assert text == b'index.graphs.append(move graph)'
		argument = next(row for row in facts if row[0] == 'NEXT_CALL_ARGUMENT'); ordinal, child, type_id, owned, obligation = map(int, argument[1:]); assert (ordinal, type_id, owned, obligation) == (0, 0, 4, 19)
		instance = next(row for row in facts if row[0] == 'NEXT_CALL_PLAN'); plan, origin, concrete, enclosing = map(int, instance[1:]); symbol = m.tables['C_SYMBOL'][origin]; method = m.tables['TOKEN'][symbol[1]][-1].decode(); assert method == 'append'
		bindings = [(number, row) for number, row in m.tables['C_REF'].items() if row[0] == child and row[8] == 1]; assert len(bindings) == 1
		binding_number, binding = bindings[0]; local = m.tables['C_SYMBOL'][binding[6]]; local_type, local_flags = m.tables['SYMBOL_TYPE'][binding[6]]; local_shape = m.tables['TYPE'].get(local_type, (0, 0))
		results[name] = dict(reference_oracle=reference, source=str(source), source_sha256=sha(source), span=[start, end], source_bytes_hex=text.hex(), first_call_node=node, target_instance=plan, origin=origin, concrete=concrete, enclosing=enclosing, lexical_method=method, consumer_code='CHECKED_CONSUMER 1 25', exact_predicate='generic_type_matches rejects the source argument because its checked TypeId is zero', predicate_reason=reason, result_type=result_type, result_flags=flags, result_obligation=deferred, argument=dict(node=child, type=type_id, flags=owned, obligation=obligation, binding_reference=binding_number, binding_target=binding[6], local_name=m.tables['TOKEN'][local[1]][-1].decode(), declared_type=local_type, declared_flags=local_flags, declared_type_kind=local_shape[0], declared_nominal=local_shape[1]), disposition='DEFERRED: owned move argument still has pending ownership/borrowing obligation 19. Reference coherence does not discharge it; no exception/error ABI or whole-module execution is authorized.')
		print(a.mode, name, node, child, 'append(move graph): TypeId 0 / owned 4 / obligation 19', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='REFERENCE_GATE_ADVANCED_NEXT_BLOCKER_BOUND', mode=a.mode, cohorts=results, recipe_sha256=sha(__file__)), indent=2)+'\n')


if __name__ == '__main__':
	main()
