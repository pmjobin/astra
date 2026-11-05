#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reconcile actual current gates, source identities and measured resource work."""
import json
from pathlib import Path
import re
from state import RUNTIME, BUILD, PRIOR, COHORTS, read, sha


def metrics(path):
	text = Path(path).read_text(); result = {}
	for name,label in [('user_CPU_seconds','User time (seconds)'),('system_CPU_seconds','System time (seconds)'),('peak_RSS_KiB','Maximum resident set size (kbytes)')]:
		match = re.search(re.escape(label)+r':\s*([0-9.]+)',text); result[name] = float(match[1]) if match else None
	return result


def union(intervals):
	end = None; total = 0.0
	for left,right in sorted(intervals):
		total += right-max(left,end if end is not None else left) if end is None or right > end else 0
		end = max(right,end if end is not None else right)
	return total


def main():
	profiles = {}; old = read(PRIOR/'engineering-summary.json'); builds = []
	labels = ['inherited-native','inherited-text','inherited-indexpath','own-new','own-family','own-twins','own-extras','own-mutations','own-faults','own-lifetime','resource','models','physical','witness','new-repaired']
	for mode in ('O0','O2'):
		leaves = {label:RUNTIME/('final-v2-'+label+'-'+mode) for label in labels}
		gates = {label:read(path/'result.json') for label,path in leaves.items()}
		component = BUILD/('native-window-v2-'+mode)/('astra-llvm-'+mode)
		assert all(gate['status'] == 'PASS' and gate['mode'] == mode and gate['component_sha256'] == sha(component) for gate in gates.values())
		native = leaves['inherited-native']; text = leaves['inherited-text']
		legacy = read(native/('inherited-'+mode)/'observations/result.json')['profiles'][mode]
		classes = read(native/('Class-'+mode)/'observations/results.json'); generics = read(native/('new-'+mode)/'observations/results.json'); texts = read(text/('new-'+mode)/'observations/results.json'); indexed = read(leaves['inherited-indexpath']/'observations/results.json')
		assert tuple(map(len,(legacy,classes,generics,texts,indexed))) == (52,23,15,16,15)
		inherited = legacy+classes+generics+texts+indexed+[row for label in ('own-new','own-family','own-twins','own-extras') for row in read(leaves[label]/'observations/results.json')]
		assert len(inherited) == 145 and [(r['name'],r['sources']) for r in inherited] == [(r['name'],r['sources']) for r in old['profiles'][mode]['programs']]
		added = read(leaves['new-repaired']/'observations/results.json'); assert len(added) == 12
		extra = read(leaves['physical']/'valid/results.json')+read(leaves['witness']/'observations/results.json'); assert len(extra) == 2
		rows = inherited+added+extra
		assert len(rows) == len({tuple(source['sha256'] for source in row['sources']) for row in rows}) == 159
		for row in rows:
			assert all(sha(s['path']) == s['sha256'] for s in row['sources']) and all(sha(p['path']) == p['sha256'] for p in row['products'].values())
		statuses = read(native/('continuity-'+mode)/'observations/result.json')['outcomes']
		assert statuses == old['profiles'][mode]['original_source_statuses'] and sum(statuses.values()) == 80
		model = (leaves['models']/'models.stdout').read_text(); assert model.count('RESOURCE_MODEL_MUTATION ') == 14
		physical = gates['physical']['mutations']; assert len(physical) == 6 and all(row['LLVM_valid'] and row['qualification_rejected'] for row in physical)
		previous = (leaves['own-mutations']/'mutations.stdout').read_text(); assert previous.count('OWNEXCHANGE_MODEL_MUTATION ') == 26 and previous.count('OWNEXCHANGE_PHYSICAL_MUTATION ') == 11
		allocating = []
		for row in added:
			base = leaves['new-repaired']/'observations'
			if row['name'] == 'nested-record-reuse': base = RUNTIME/('final-v2-nested-ABI-'+mode)/'observations'
			else: base = RUNTIME/('final-v2-new-'+mode)/'observations'
			trace = (base/(row['name']+'-memory-native.stderr')).read_text()
			if re.search(r'calloc\([0-9]+,\s*[0-9]+\)',trace): allocating.append(row['name'])
		assert len(allocating) >= 4,allocating
		def elf(row): return row['products'].get('native',row['products'].get('executable'))['sha256']
		def raw(row): return row['products'].get('raw',{}).get('sha256')
		profiles[mode] = dict(component_sha256=sha(component),required_core_corpus=157,total_qualified_source_identities=159,inherited=145,new_core=12,additional_valid_twins_and_source_views=2,distinct_ELF_bytes=len({elf(row) for row in rows}),inherited_distinct_ELF_bytes=len({elf(row) for row in inherited}),inherited_raw_IR_byte_matches=sum(raw(left) == raw(right) and raw(left) is not None for left,right in zip(inherited,old['profiles'][mode]['programs'])),programs=rows,original_source_statuses=statuses,new_model_mutations=14,new_LLVM_valid_physical_controls=6,physical_control_boundary='Post-emission independent source/ABI/runtime qualification; two static ABI/identity controls and four runtime/memory controls. The compiler retained-module audit is covered by the separately rerun inherited physical gate.',retained_OWNEXCHANGE_mutations=37,retained_OWNEXCHANGE_LLVM_valid_mutations=11,material_allocation_Valgrind_cases=allocating,gate_receipts={name:dict(path=str(path/'result.json'),sha256=sha(path/'result.json')) for name,path in leaves.items()})
		for receipt in (RUNTIME/('native-window-v2-'+mode)).glob('build-*/ownflow-'+mode+'.json'):
			entry = read(receipt); assert entry['exit'] == 0
			builds.append(dict(mode=mode,**entry,**metrics(receipt.with_suffix('.stderr')),receipt=str(receipt),receipt_sha256=sha(receipt)))
		assert list((RUNTIME/('warm-window-v2-'+mode)).glob('build-*/ownflow-'+mode+'-exact-reuse.json'))
	assert [r['sources'] for r in profiles['O0']['programs']] == [r['sources'] for r in profiles['O2']['programs']]
	cohorts = read(RUNTIME/'cohorts-final-v2.json'); traces = {}
	for name in COHORTS:
		row = cohorts[name]; assert row['new_checked_prefix_uses'] > 0 and row['first_stop_before']['message'] == 'generic instance resource limit' and row['first_stop_after']['message'].startswith('DEFERRED: swap requires')
		before = read(RUNTIME/'trace-baseline/result.json')[name]; after = read(RUNTIME/'trace-window-v2/result.json')[name]
		assert not after['limits'] and before['limits'] and not before['cycles'] and not after['cycles']
		def info(value,kind):
			counts = value['counts']; scheduling = [event for event in value['events'] if event[1] == 3]
			depths = {}
			for request,edge in value['requests'].items(): depths[request] = 1+(depths[str(edge['parent'])] if edge['parent'] else 0)
			return dict(counts=counts,attempted_requests=counts[7],exact_unique_keys=value['distinct_prefix'],dedup_hits=counts[8],materialized_declarations=counts[3],generated_AST_nodes=counts[9]-counts[0],reserved_map_slots=counts[4:7],nonzero_map_entries=value['mapped'],maximum_request_depth=max(depths.values()),map_growth_storage_upper_bound_bytes=4*(sum(scheduling[-1][4:7])+sum(counts[4:7])),wall_seconds=value['end']-value['start'],**metrics(RUNTIME/kind/(name+'.time')))
		traces[name] = dict(before=info(before,'trace-baseline'),after=info(after,'trace-window-v2'),comparison='Identical frozen inputs, C0 toolchain, O0 diagnostic profile and fixed limits. More work completes after repair; no equal-work speedup claim. Map-growth bytes are a derived upper bound, RSS is measured.')
	controls = {label:read(RUNTIME/folder/'result.json') for label,folder in [('before','controls-baseline-parser-recheck'),('after','controls-window-v2')]}
	for name in ('duplicate','distinct','exhaust'): assert controls['before'][name]['source_sha256'] == controls['after'][name]['source_sha256']
	assert controls['after']['exhaust']['counts'][0][3] == 256 and controls['after']['exhaust']['exit'] == 1
	intervals = [(row['monotonic_start'],row['monotonic_end']) for row in builds]
	result = dict(format='astra-genresource20-summary/1',status='ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING',profiles=profiles,cohorts=cohorts,demand_and_cost=traces,controls=controls,cold_builds=builds,cold_build_active_union_seconds=union(intervals),cold_build_overlap_seconds=sum(b-a for a,b in intervals)-union(intervals),historical_proof_outputs=1044,historical_proof_classification='PRESERVED_HISTORICAL_NOT_FRESHLY_REPROVEN',deferrals=['All four whole compiler populations remain deferred at swap(this.signatures, grown) in their exact frozen CheckedIndex sources; typed prefix progress does not establish whole-source safety.','Genuine 257th distinct instance remains resource-DEFERRED at 256; no resource contract amendment authorized.','Complete original CfgWalk.inspect and separate three-specialization stress retain the independent 8000000-step SSA boundary.','Finite generic runtime recursion remains under the existing unsupported effect policy; no general recursive generic contract is added.','Utf8Message factory/exceptions/text_split; wide-u64-to-f32 Valgrind discrepancy; effectful/indexed owner targets and wider owning-element domains remain deferred.','The exact FlowGraph.outlives body executes in a disclosed source/dependency view, not the complete original Class or compiler; Stage 1 and release remain unqualified.'],recipe_sha256=sha(__file__))
	cycles = read(RUNTIME/'cycles-final-v3/result.json'); assert cycles['status'] == 'PASS'
	result['cycle_boundary'] = dict(receipt=str(RUNTIME/'cycles-final-v3/result.json'),sha256=sha(RUNTIME/'cycles-final-v3/result.json'),observed='Mutual by-value generic signature cycle rejects deterministically at an active origin. The repaired trace publishes zero failed declarations; the baseline published two despite overall failure. Both native profiles preserve previous output bytes on refusal.')
	result['exact_warm_builds'] = read(RUNTIME/'warm-timed.json')
	result['cost_limitations'] = 'Frozen inputs/flags/ceilings match, but more declarations and original checked uses complete after repair. Distinct-control runtime/RSS rises as it reaches full completion; no uniform speedup is claimed. Original historical cold-build times are descriptive and are not a controlled baseline.'
	(RUNTIME/'engineering-summary.json').write_text(json.dumps(result,indent=2)+'\n'); print('O0/O2: 145 inherited + 12 new + 2 additional native identities; 20 new mutation controls/profile; four exact typed-prefix advances')


if __name__ == '__main__':
	main()
