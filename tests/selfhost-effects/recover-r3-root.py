#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently inspect predicate 26 without changing a verifier or root."""
import argparse
import hashlib
import json
from pathlib import Path
from state import ROOT, load_module, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--regression', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_root_paths', ROOT/'tests/selfhost-effects/recover-build.py'); directory = paths.RUNTIME/a.regression/('first-failure-v1-'+a.mode); result = read(directory/'result.json'); assert result['first_stop'] == ['55', '26']; raw = directory/'stdout'; assert sha(raw) == result['stdout_sha256']; slots = []; captures = []; graph = None
	for line in raw.open():
		row = line.split()
		if len(row) < 3 or row[1] != '55': continue
		if row[0] == 'G': graph = row
		if row[0] == 'S' or row[0] == 'E' and row[3] == '24':
			path = Path(bytes.fromhex(row[-3]).decode()); first, last = int(row[-2]), int(row[-1]); data = path.read_bytes(); fragment = data[first:last]; item = dict(index=int(row[2]), source=str(path), source_sha256=sha(path), start_byte=first, end_byte=last, fragment=fragment.decode(), fragment_sha256=hashlib.sha256(fragment).hexdigest())
			if row[0] == 'S': item.update(symbol=int(row[3]), type=int(row[5]), flags=int(row[6])); slots.append(item)
			else: item.update(operation=int(row[3]), slot=int(row[4]), region=int(row[7]), side=int(row[8])); captures.append(item)
	assert graph and graph[2] == '2053' and len(slots) == 9 and len(captures) == 2
	left = next(r for r in captures if r['side'] == 1); right = next(r for r in captures if r['side'] == 2)
	assert left['fragment'] == 'this.signatures' and left['slot'] == 0
	assert right['fragment'] == 'grown' and right['slot'] == 6
	assert next(r for r in slots if r['index'] == 6)['fragment'] == 'grown' and all(r['fragment'] != 'this' for r in slots)
	output = paths.RUNTIME/('root-'+a.version+'-'+a.mode+'.json'); output.write_text(json.dumps(dict(status='DEFERRED', graph=55, symbol=2053, predicate=26, component_sha256=result['component_sha256'], raw_sha256=sha(raw), slots=slots, captures=captures, verifier_source_sha256=sha(ROOT/'compiler/semantic/flow-owner-exchange.astra'), interpretation='The actual graph has no borrowed receiver slot. The left Class field capture has root/slot zero; the local right operand has slot six. Existing flow_owner_capture_verified requires a real field Place or positive owned local slot. No exact Class-field root authority has been established, so no slot, alias attribute or verifier exemption is introduced. This is independent of recoverable-effect transport.'), indent=2)+'\n'); print(a.mode, 'graph 55 / symbol 2053 / predicate 26 independently retained DEFERRED', flush=True)


if __name__ == '__main__':
	main()
