#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless GENREF receipts for the unchanged installed pm-next publisher."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, BASE, COHORTS, read, sha, git


def load(name, path):
	spec = importlib.util.spec_from_file_location(name, path); module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.replace('-', '').isalnum()
	assert git('status', '--porcelain=v1', '--untracked-files=all') == ''
	audit = read(RUNTIME/'final-audit.json'); head = git('rev-parse', 'HEAD').strip(); tree = git('rev-parse', 'HEAD^{tree}').strip()
	assert audit['status'] == 'PASS' and audit['final_commit'] == head and audit['final_tree'] == tree
	output = RUNTIME/('handoff-'+a.version); output.mkdir(exist_ok=False); files = {}; omissions = []; started = time.monotonic()
	def collect(root, prefix):
		for path in sorted(root.rglob('*')):
			if path.is_dir(): continue
			if root == RUNTIME and path.relative_to(root).parts[0].startswith('handoff-'): continue
			assert path.is_file() and not path.is_symlink(), path
			name = prefix+'/'+str(path.relative_to(root))
			if path.suffix == '.zip':
				omissions.append(dict(path=name, bytes=path.stat().st_size, sha256=sha(path), reason='Exact predecessor report remains externally preserved; its compressed ZIP is not duplicated in the successor.')); continue
			files[name] = path
	collect(RUNTIME, 'task-runtime'); collect(BUILD, 'task-build')
	# Every old task source version used by a failed, cancelled or successful
	# build is already recovered by exact recorded hash, without session logs.
	recovery = read(RUNTIME/'recovered-build-inputs/result.json'); assert recovery['status'] == 'PASS' and recovery['expected'] == recovery['recovered']
	for row in recovery['inputs']:
		path = RUNTIME/'recovered-build-inputs'/row['sha256']; assert sha(path) == row['sha256']
	for name in git('ls-files').splitlines():
		path = ROOT/name
		prefixes = ('compiler/', 'tests/selfhost-genref/', 'tests/selfhost-callplace/', 'tests/selfhost-typecore/', 'tests/selfhost-llvm/', 'tests/selfhost-classstorage/', 'tests/selfhost-textclass/', 'tools/qualification/', 'tools/format/', 'format/')
		if path.is_file() and (name.startswith(prefixes) or name in audit['changed_paths'] or name in ('AGENTS.md', 'CODING_STYLE.md', 'docs/selfhost-membercall-22-checkpoint.md')): files['repository/'+name] = path
		# Original cohorts, including synthetic-source metadata, and the exact raw
		# before observations are retained. Population identities never use a new
		# convenience extraction or a simplified caller.
	for name in COHORTS:
		ledger = PRIOR/('ledger-v2-'+name)/'ledger.json'; files['historical/ledger-before-'+name+'.json'] = ledger
		for row in read(ledger)['files']:
			if 'synthetic_source_hex' not in row:
				path = Path(row['path']); assert sha(path) == row['sha256']; files['historical/source/'+row['sha256']+'/'+path.name] = path
	for mode in ('O0', 'O2'):
		for row in read(RUNTIME/('inherited-v3-'+mode)/'programs.json'):
			for source in row['sources']:
				path = Path(source['path']); assert sha(path) == source['sha256']; files['program-inputs/'+source['sha256']+'/'+path.name] = path
			for product in row['prior_products'].values():
				path = Path(product['path']); assert sha(path) == product['sha256']; files['historical/program-products/'+product['sha256']+'/'+path.name] = path
			path = Path(row['prior_receipt']); assert sha(path) == row['prior_receipt_sha256']; files['historical/receipts/'+str(path.relative_to(PRIOR))] = path
		for leaf in ('inherited-v2-'+mode, 'qualified-v3-'+mode):
			path = PRIOR/leaf/'result.json'; files['historical/callplace23/'+leaf+'/result.json'] = path
	for name in ('final-audit.json', 'cohorts-v2.json', 'archive-integrity.json', 'initial.json'): files['historical/callplace23/'+name] = PRIOR/name
	for name in ('checkpoint-audit.json', 'inference-operands-v2/result.json', 'facts-v2/result.json'): files['historical/membercall22/'+name] = RUNTIME.parent/'membercall22'/name
	files['historical/proof-output-inventory.json'] = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'
	collect(RUNTIME.parent/'native-current/input', 'submission/input'); files['submission/intake.json'] = RUNTIME.parent/'native-current/pm-next-intake.json'
	decoder = ROOT/'tests/selfhost-textclass/derived-ledgers.py'; encoder = ROOT/'tools/qualification/encoded-evidence.py'; transport_path = ROOT/'tests/selfhost-callplace/transport.py'; observation_path = ROOT/'tests/selfhost-callplace/observations.py'
	for name, path in [('restore-ledgers.py', decoder), ('encoded-evidence.py', encoder), ('transport.py', transport_path), ('restore-observations.py', observation_path)]: files['recipes/'+name] = path
	observations = load('observations', observation_path); transport = load('transport', transport_path)
	observation_directory = output/'derived-observations'; observation_directory.mkdir()
	observation_plan = dict(format='astra-lossless-native-observations/1', final_commit=head, final_tree=tree, files=[])
	for logical, path in list(files.items()):
		# The inherited codec accepts the ten-column whole-source NODE schema.
		# Core/CFG/SSA also print NODE, with a different schema; keep those raw.
		if path.name not in ('whole-compiler.stdout', 'ledger.stdout'): continue
		with path.open('rb') as stream: contains_nodes = any(line.startswith(b'NODE ') for line in stream)
		if contains_nodes: observation_plan['files'].append(observations.encode(path, observation_directory, logical, len(observation_plan['files'])))
	observation_plan_path = observation_directory/'restore-plan.json'; observation_plan_path.write_text(json.dumps(observation_plan, indent=2)+'\n'); observation_receipt = output/'observation-reconstruction.json'
	subprocess.run([sys.executable, '-B', observation_path, output, '--plan', observation_plan_path, '--verify-only', '--receipt', observation_receipt], check=True)
	plan = dict(format='astra-lossless-derived-ledgers/1', final_commit=head, final_tree=tree, files=[]); metadata = output/'derived-ledgers/metadata'; metadata.mkdir(parents=True)
	for logical, path in list(files.items()):
		if path.suffix != '.json' or not ('ledger' in path.name or logical.startswith('historical/ledger-before-')): continue
		model = read(path)
		if not isinstance(model, dict) or model.get('format') != 'astra-whole-source-ledger/1': continue
		if logical.startswith('historical/ledger-before-'):
			name = logical.removeprefix('historical/ledger-before-').removesuffix('.json'); raw_name = 'task-runtime/baseline-v2-'+name+'/ledger.stdout'
		else: raw_name = str(Path(logical).with_name('whole-compiler.stdout'))
		assert raw_name in files
		model['nodes'] = None; target = metadata/(str(len(plan['files']))+'.json'); target.write_text(json.dumps(model, indent=2)+'\n'); files['derived-ledgers/metadata/'+target.name] = target
		plan['files'].append(dict(path=logical, bytes=path.stat().st_size, mode=path.stat().st_mode & 0o777, sha256=sha(path), raw=raw_name, raw_sha256=sha(files[raw_name]), metadata='metadata/'+target.name, metadata_sha256=sha(target))); del files[logical]
	plan_path = output/'derived-ledgers/restore-plan.json'; plan_path.write_text(json.dumps(plan, indent=2)+'\n'); receipt = output/'ledger-reconstruction.json'
	subprocess.run([sys.executable, '-B', decoder, output, '--plan', plan_path, '--original-runtime', RUNTIME, '--verify-only', '--receipt', receipt], check=True)
	files['derived-ledgers/restore-plan.json'] = plan_path; files['derived-ledgers/reconstruction.json'] = receipt
	for row in observation_plan['files']: del files[row['path']]
	for path in observation_directory.iterdir(): files['derived-observations/'+path.name] = path
	files['derived-observations/reconstruction.json'] = observation_receipt
	index = dict(format='astra-genref24-evidence/1', storage_format='astra-line-chunk/1', final_commit=head, final_tree=tree, files=[], omissions=omissions)
	archive = output/'evidence.tar.xz'
	with tarfile.open(archive, 'w:xz', preset=9) as packed:
		writer = transport.ChunkWriter(packed)
		for name, path in sorted(files.items()):
			before = sha(path); index['files'].append(writer.add(name, path, None, path.stat().st_mode & 0o777, before)); assert sha(path) == before
		data = (json.dumps(index, indent=2)+'\n').encode(); entry = tarfile.TarInfo('ARCHIVE-INDEX.json'); entry.size = len(data); entry.mode = 0o644; packed.addfile(entry, io.BytesIO(data))
	verification = transport.verify(archive); assert verification['status'] == 'PASS'; (output/'transport-verification.json').write_text(json.dumps(verification, indent=2)+'\n')
	assert archive.stat().st_size < 24*1024**2, 'Preserve the report cap; improve lossless transport rather than dropping evidence'
	attachments = output/'attachments'; subprocess.run([sys.executable, '-B', encoder, 'pack', '--input', archive, '--output', attachments, '--stem', 'genref24'], check=True)
	for name in ('final-audit.json', 'cohorts-v3-O0.json', 'cohorts-v3-O2.json', 'baseline.json'): shutil.copy2(RUNTIME/name, attachments/name)
	for mode in ('O0', 'O2'): shutil.copy2(RUNTIME/('next-blocker-v3b-'+mode)/'result.json', attachments/('next-blocker-'+mode+'.json'))
	shutil.copy2(output/'transport-verification.json', attachments/'transport-verification.json')
	# Bootstrap decoders can be inspected before restoring the inner archive.
	for name, path in [('decode-evidence.py.txt', encoder), ('restore-transport.py.txt', transport_path), ('restore-observations.py.txt', observation_path), ('restore-ledgers.py.txt', decoder)]: shutil.copy2(path, attachments/name)
	(attachments/'review-guide.txt').write_text('GENREF-24: read final-audit.json and docs/selfhost-genref-24.md first. Scoped reference-correspondence PASS; MEMBERCALL-22 remains PARTIAL. All original calls retain obligation 19. Both complete original throws Error callers remain DEFERRED. No exception/error ABI or Stage 1 is qualified.\nRecover evidence.tar.xz with decode-evidence.py.txt and genref24-encoding.json. Use restore-transport.py.txt to restore byte-exact indexed files, then restore-observations.py.txt, then restore-ledgers.py.txt. Each decoder supports receipts and verifies original SHA-256 identities. Reconstructions are byte transport, not fresh executions or safety proofs. The inner archive includes the same recipes.\nAll 187 inherited plus 15 new program source identities/profile have fresh native LLVM/object/ELF execution. The 15 new sources/profile have independent C0/ABI/Valgrind evidence. Source-bound reference oracles prove 2394/2394/2367/2367 reference correspondences and unchanged source/node/span identities; all four actual consumers advance from 1 7 to 1 25. The next actual blocker is index.graphs.append(move graph), argument TypeId 0, owned flag 4, obligation 19.\nThere are 37 new native reference-model mutation categories/profile, including three well-linked wrong targets demonstrably accepted by retained v1 and rejected by final code; 27 separate Python oracle mutations and seven independent LLVM-valid physical alternatives/profile. Failed drafts, cancelled builds, intermediate v1 qualification, exact old build source versions, allocation traces, timing/RSS and final warm-reuse checks remain attributed to their actual products. Reports stay preserved externally by exact archive hashes; donor source and private session logs are not collected.\n')
	(attachments/'packaging.json').write_text(json.dumps(dict(final_commit=head, final_tree=tree, archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), seconds=time.monotonic()-started, preserved_external_reports=omissions), indent=2)+'\n')
	evidence = dict(format='pm-next-evidence/1', files=[dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(attachments.iterdir())]); assert len(evidence['files']) <= 128 and sum(row['bytes'] for row in evidence['files']) <= 64*1024**2 and all(row['bytes'] <= 2*1024**2 for row in evidence['files'])
	(attachments/'INDEX.json').write_text(json.dumps(evidence, indent=2)+'\n'); print(attachments/'INDEX.json', archive.stat().st_size, sha(archive), flush=True)


if __name__ == '__main__':
	main()
