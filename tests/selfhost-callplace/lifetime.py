#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Consume fresh unsuppressed traces using independently measured C0 layouts."""
import argparse
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from state import RUNTIME, read, sha


def allocations(path):
	live = {}; rows = []; events = []
	for ordinal,line in enumerate(path.read_text().splitlines()):
		match = re.fullmatch(r'--\d+-- calloc\((\d+),(\d+)\) = (0x[0-9A-Fa-f]+)',line)
		if match:
			count,size = int(match[1]),int(match[2]); address = match[3].lower(); assert address != '0x0' and address not in live
			row = dict(id=len(rows)+1,bytes=count*size,allocated=ordinal,address=address); rows.append(row); live[address] = row; events.append(['A',row['id'],row['bytes']]); continue
		match = re.fullmatch(r'--\d+-- free\((0x[0-9A-Fa-f]+)\)',line)
		if match and match[1].lower() in live:
			row = live.pop(match[1].lower()); row['freed'] = ordinal; events.append(['F',row['id'],row['bytes']])
	assert rows and not live
	return rows,events


def main():
	p = argparse.ArgumentParser(); p.add_argument('--qualification',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('lifetime-'+a.mode); leaf.mkdir(exist_ok=False); observations = []
	qualified = {row['name']:row for row in read(a.qualification/'results.json')}
	for name in ('record-add-growth','nested-owner-retirement'):
		row = qualified[name]; assert row['baseline_complete']; layout = (a.qualification/(name+'-ABI-probe.stdout')).read_text()
		trace = a.qualification/(name+'-memory-native.stderr'); records,events = allocations(trace)
		assert ET.parse(a.qualification/(name+'-native.xml')).getroot().find('error') is None
		if name == 'record-add-growth':
			match = re.search(r'^LAYOUT FlowEvent (\d+) (\d+) (\d+)$',layout,re.M); assert match; size = int(match[1])
			growth = []
			for count in (16,32,64):
				matched = [r for r in records if r['bytes'] == count*size]; assert len(matched) == 1; growth.append(matched[0])
			first,second,third = growth
			assert first['allocated'] < second['allocated'] < first['freed'] < third['allocated'] < second['freed'] < third['freed']
			witness = dict(independent_FlowEvent_bytes=size,capacities=[16,32,64],allocations=growth,contract='Each replacement allocates before the old backing is freed; the last backing survives until owner cleanup')
		else:
			sizes = {}
			for cls in ('Meter','Rack','Sample'):
				match = re.search(r'^LAYOUT '+cls+r' (\d+) (\d+) (\d+)$',layout,re.M); assert match; sizes[cls] = int(match[1])
			selected = []
			for size in (3*sizes['Sample'],sizes['Meter'],sizes['Rack']):
				matched = [r for r in records if r['bytes'] == size]; assert len(matched) == 1; selected.append(matched[0])
			assert selected[0]['freed'] < selected[1]['freed'] < selected[2]['freed']
			witness = dict(independent_sizes=sizes,retirements=selected,contract='Owned record backing retires before its containing child Class and the moved enclosing owner')
		observations.append(dict(name=name,source=row['sources'],trace_sha256=sha(trace),events=events,witness=witness,all_traced_native_allocations_retired=True,normal_return=True,memory_errors=0)); print(a.mode,name,'MATERIAL_ALLOCATION_AND_RETIREMENT_WITNESS')
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,observations=observations,recipe_sha256=sha(__file__),boundary='Fresh native Valgrind allocation identities and C0/C++ layout measurements. C0 allocation counts may differ through legal optimization; fatal abort paths are separate.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
