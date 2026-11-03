# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent IR graph/flag and observed allocation/free oracles."""
from collections import defaultdict
import re


def inspect(ir, projection):
	text = ir.decode()
	assert re.search(r'target triple = "x86_64-[^"]*linux[^"]*"', text)
	assert 'target datalayout = "' in text
	assert not re.search(r'\b(?:nsw|nuw|exact|inbounds|noalias|nonnull|dereferenceable|readonly|nocapture|fast|reassoc|nnan|ninf|nsz|arcp|afn)\b', text)
	assert not re.search(r'\b(?:undef|poison)\b', text)
	assert not re.search(r'@(?:astra_c0|valac|system|exec|popen|dlopen)', text)
	rows = defaultdict(list)
	for line in projection.decode().splitlines():
		x = line.split()
		if x and x[0].startswith('SSA_'):
			try:
				rows[x[0]].append(list(map(int, x[1:])))
			except ValueError:
				pass
	blocks = {}
	for match in re.finditer(r'^([A-Za-z_][\w.]*):[^\n]*\n(.*?)(?=^[A-Za-z_][\w.]*:|^})', text, re.M | re.S):
		blocks[match[1]] = match[2]
	live = {x[0] for x in rows['SSA_BLOCK'] if x[12]}
	assert {int(x[1:]) for x in blocks if re.fullmatch(r'b\d+', x)} == live
	edges = 0
	for _, _, source, target, _, _ in rows['SSA_EDGE']:
		if source not in live:
			continue
		edges += 1
	for index, _, source, target, polarity, _ in rows['SSA_EDGE']:
		if source in live:
			assert re.search(r'br label %b'+str(target)+r'\b', blocks['e'+str(index)])
			assert len(re.findall(r'label %e'+str(index)+r'\b', text)) == 1
	phis = sum(x[2] == 3 and x[3] in live for x in rows['SSA_VALUE'])
	# Allocation guards introduce extra pointer PHIs, never replace SSA PHIs.
	assert len(re.findall(r' = phi ', text)) >= phis
	for value in rows['SSA_VALUE']:
		if value[2] != 3 or value[3] not in live:
			continue
		incoming = [x[3] for x in rows['SSA_ARG'] if x[1] == value[0] and x[3]]
		assert incoming
	return dict(source_blocks=len(live), exact_edges=edges, source_phis=phis, guard_blocks=len(blocks)-len(live)-edges, no_unproved_flags=True)


def memory(stderr, expected_trace=None):
	assert b'ERROR SUMMARY: 0 errors' in stderr, stderr[-1600:]
	for kind in (b'definitely', b'indirectly', b'possibly'):
		match = re.search(kind+rb' lost: ([\d,]+) bytes', stderr)
		if match:
			assert int(match[1].replace(b',', b'')) == 0
	live = {}
	trace = []
	for event in re.finditer(rb'calloc\((\d+),\s*(\d+)\) = (0x[0-9A-Fa-f]+)|free\((0x[0-9A-Fa-f]+)\)', stderr):
		count, width, address, freed = event.groups()
		if address:
			assert address not in live
			live[address] = int(count)*int(width)
			trace.append(['A', live[address]])
		elif int(freed, 16):
			assert freed in live, (freed, live)
			trace.append(['F', live.pop(freed)])
	if expected_trace is not None:
		assert not live and trace == [[kind, count*4] for kind, count in expected_trace], (trace, expected_trace, live)
	return dict(errors=0, lost_bytes=0, observed_trace=trace, reachable_library_bytes='see unsuppressed raw receipt')
