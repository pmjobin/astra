#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Strict raw identities across R3/R4/R5; never normalize bytes into equality."""
import argparse
import json
from pathlib import Path
import zipfile
from state import ROOT, load_module, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_drift_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('drift-'+a.version+'-'+a.mode); leaf.mkdir(); history = paths.RUNTIME/'r4-history'
	r3 = paths.RUNTIME.parent/'effects25-r4/predecessor-report.zip'; assert sha(r3) == 'f3547341290442b90c59e45e949221c18421f7c5daa3448dfa2cd2c37b722c14'
	with zipfile.ZipFile(r3) as archive: r3_audit = json.loads(archive.read('evidence/final-audit.json')); (leaf/'R3-final-audit.json').write_bytes(archive.read('evidence/final-audit.json'))
	r3_native = {row['source_sha256']: row for row in r3_audit['profiles'][a.mode]['programs']}; assert len(r3_native) == 120
	r4_effects = read(history/('runtime/r4-retained-final16-'+a.mode+'/result.json')); assert len(r4_effects['programs']) == 120 and r4_effects['raw_LLVM_identical'] == 0
	r4 = {row['source_sha256']: dict(raw=row['raw_LLVM_sha256'], ELF=row['ELF_sha256'], R3_raw=row['old_raw_LLVM_sha256'], R3_ELF=r3_native[row['source_sha256']]['ELF_sha256']) for row in r4_effects['programs']}
	additional = read(history/('runtime/early-final16fields-'+a.mode+'/result.json'))
	for row in additional['programs']: r4[row['source_sha256']] = dict(raw=row['Astra_raw_LLVM_sha256'], ELF=row['Astra_ELF_sha256'], R3_raw=None, R3_ELF=None)
	assert len(r4) == 138
	rows = []
	for suffix in ('scalar', 'record', 'owned', 'errors', 'loops', 'literal', 'domain', 'fields'):
		result = read(paths.RUNTIME/('early-'+a.version+suffix+'-'+a.mode)/'result.json')
		for row in result['programs']:
			old = r4[row['source_sha256']]; raw = row['Astra_raw_LLVM_sha256']; elf = row['Astra_ELF_sha256']; build = paths.BUILD/('early-'+a.version+suffix+'-'+a.mode); assert sha(build/(row['name']+'-Astra.ll')) == raw and sha(build/(row['name']+'-Astra')) == elf
			rows.append(dict(name=row['name'], source_sha256=row['source_sha256'], R3_raw_LLVM_sha256=old['R3_raw'], R3_ELF_sha256=old['R3_ELF'], R4_raw_LLVM_sha256=old['raw'], R4_ELF_sha256=old['ELF'], R5_raw_LLVM_sha256=raw, R5_ELF_sha256=elf, R5_R4_raw_equal=raw == old['raw'], R5_R4_ELF_equal=elf == old['ELF'], R5_R3_raw_equal=raw == old['R3_raw'] if old['R3_raw'] else None, R5_R3_ELF_equal=elf == old['R3_ELF'] if old['R3_ELF'] else None))
	assert len(rows) == len({r['source_sha256'] for r in rows}) == 138
	inherited = read(paths.RUNTIME/('inherited-'+a.version+'-'+a.mode)/'result.json'); baseline = read(paths.RUNTIME/('inherited-baseline-'+a.mode)/'result.json'); old = read(history/('runtime/regression-final16-'+a.mode+'/inherited-v1-'+a.mode+'/result.json'))
	ordinary = []
	for before, current, original in zip(baseline['programs'], inherited['programs'], old['programs'], strict=True):
		assert before['name'] == current['name'] == original['name'] and [r['sha256'] for r in before['sources']] == [r['sha256'] for r in current['sources']] == [r['sha256'] for r in original['sources']]
		ordinary.append(dict(name=current['name'], source_sha256=[r['sha256'] for r in current['sources']], R4_raw_LLVM_sha256=original['fresh_products']['raw']['sha256'], R4_ELF_sha256=original['fresh_products']['native']['sha256'], relocated_R4_raw_LLVM_sha256=before['raw_LLVM_sha256'], relocated_R4_ELF_sha256=before['ELF_sha256'], R5_raw_LLVM_sha256=current['raw_LLVM_sha256'], R5_ELF_sha256=current['ELF_sha256'], R5_R4_raw_equal=current['raw_R4_identity'], R5_R4_ELF_equal=current['ELF_R4_identity'], R5_relocated_R4_raw_equal=current['raw_LLVM_sha256'] == before['raw_LLVM_sha256'], R5_relocated_R4_ELF_equal=current['ELF_sha256'] == before['ELF_sha256']))
	assert len(ordinary) == 202
	result = dict(status='STRICT_RAW_DRIFT_LEDGER', profile=a.mode, retained_138=rows, inherited_202=ordinary, effects_R4_R3_raw_identical=0, effects_R4_R3_total=120, effects_R5_R3_raw_identical=sum(r['R5_R3_raw_equal'] is True for r in rows), retained_R5_R4_raw_identical=sum(r['R5_R4_raw_equal'] for r in rows), retained_R5_R4_ELF_identical=sum(r['R5_R4_ELF_equal'] for r in rows), inherited_R5_R4_raw_identical=sum(r['R5_R4_raw_equal'] for r in ordinary), inherited_R5_relocated_R4_raw_identical=sum(r['R5_relocated_R4_raw_equal'] for r in ordinary), limitation='Strict SHA-256/byte identities only. No normalized text is called identity. Historical 0/120 R4-vs-R3 effect raw drift remains historical. R4 ordinary source paths removed by pre-task cleanup are explicitly relocated; generic identities encode those paths, so unchanged source bytes can yield changed raw IR/ELF. The relocated predecessor replay is distinct from the original checkpoint. Eighteen R4 additions have no R3 counterpart.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(a.mode, 'strict drift ledger recorded for all 340 retained source identities', flush=True)


if __name__ == '__main__':
	main()
