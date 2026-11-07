#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One final R3 suite, with explicit routing and per-job evidence identities."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--resume', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_final_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r3-consolidated-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=a.resume); identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	jobs = [('recover-regression', a.version, []), ('recover-qualify', a.version+'scalar', ['--expanded']), ('recover-record-qualify', a.version+'record', []), ('recover-owned-qualify', a.version+'owned', []), ('recover-error-owned-qualify', a.version+'errors', []), ('recover-loop-qualify', a.version+'loops', []), ('recover-r3-qualify', a.version+'literal', []), ('recover-r3-domain-qualify', a.version+'domain', []), ('recover-adversarial', a.version, []), ('recover-owner-adversarial', a.version, []), ('recover-loop-adversarial', a.version, []), ('recover-r3-adversarial', a.version, []), ('recover-r3-domain-adversarial', a.version, []), ('recover-class-policy', a.version, []), ('recover-r3-policy', a.version, []), ('recover-null-guard', a.version, []), ('recover-r3-receiver-guard', a.version, []), ('recover-r3-float-probe', a.version, []), ('recover-success-probe', a.version, []), ('recover-abi-limit', a.version+a.mode, []), ('recover-original', a.version, ['--provider-build', str(a.component.parent)]), ('recover-r3-original-view', a.version, ['--ledger-component', str(a.component)]), ('recover-frontier', a.version, []), ('recover-r3-fields', a.version+'fields', []), ('recover-r3-source-oracles', a.version, []), ('recover-r3-observe', a.version, ['--native-version', a.version+'literal']), ('recover-r3-root', a.version, ['--regression', 'regression-'+a.version+'-'+a.mode])]
	commands = read(leaf/'commands.json') if a.resume else []; versions = {}; environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
	for name, version, extra in jobs:
		previous = [row for row in commands if row['name'] == name]; prior = previous[-1] if previous else None
		if prior:
			assert prior['component_sha256'] == sha(a.component) and sha(leaf/(prior['label']+'.stdout')) == prior['stdout_sha256'] and sha(leaf/(prior['label']+'.stderr')) == prior['stderr_sha256']
			if prior['exit'] == 0:
				versions[name] = prior['version']; continue
			version += 'retry'+str(len(previous))
		label = name+('-retry'+str(len(previous)) if previous else ''); argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r3.py', name, '--version', version]
		if name != 'recover-abi-limit': argv += ['--mode', a.mode]
		if name not in ('recover-r3-observe', 'recover-r3-root', 'recover-r3-source-oracles'): argv += ['--component', a.component]
		argv += extra; start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *map(str, argv)], cwd=ROOT, env=environment, capture_output=True, timeout=2400); (leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, label=label, version=version, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(a.component), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, (name, r.stdout[-3000:], r.stderr[-3500:]); versions[name] = version; print(a.mode, name, 'recipe completed; actual results and deferrals retained', flush=True)
	def location(prefix, job): return prefix+'-'+versions[job]+'-'+a.mode
	configuration = dict(component=str(a.component), regression=location('regression', 'recover-regression'), native_results=[location('early', job) for job in ('recover-qualify', 'recover-record-qualify', 'recover-owned-qualify', 'recover-error-owned-qualify', 'recover-loop-qualify')], new_native_results=[location('early', job) for job in ('recover-r3-qualify', 'recover-r3-domain-qualify')], adversarial=[location(prefix, job) for prefix, job in [('adversarial', 'recover-adversarial'), ('owner-adversarial', 'recover-owner-adversarial'), ('loop-adversarial', 'recover-loop-adversarial')]], new_adversarial=[location(prefix, job) for prefix, job in [('r3-adversarial', 'recover-r3-adversarial'), ('r3-domain-adversarial', 'recover-r3-domain-adversarial')]], original=location('original', 'recover-original'), original_view=location('original-view', 'recover-r3-original-view'), receiver_guard=location('r3-receiver-guard', 'recover-r3-receiver-guard'), floating_probe=location('r3-float-probe', 'recover-r3-float-probe'), frontier=location('frontier', 'recover-frontier'), fields=location('frontier', 'recover-r3-fields'), source_oracles=location('source-oracles', 'recover-r3-source-oracles'), class_policy=location('class-policy', 'recover-class-policy'), r3_policy=location('r3-policy', 'recover-r3-policy'), dynamic_observer=location('r3-observer', 'recover-r3-observe'), root='root-'+versions['recover-r3-root']+'-'+a.mode+'.json', null_guard=location('null-guard', 'recover-null-guard'), ABI_success_probe=location('success-cell', 'recover-success-probe'), ABI_limit='abi-limit-'+versions['recover-abi-limit'])
	(leaf/'result.json').write_text(json.dumps(dict(status='R3_CONSOLIDATED_RECIPES_COMPLETED', profile=a.mode, component_sha256=sha(a.component), profile_configuration=configuration, limitation='Recipe completion is not milestone PASS. The final source-bound audit retains every incomplete bounded gate.'), indent=2)+'\n'); print(a.mode, 'final R3 recipes completed', flush=True)


if __name__ == '__main__':
	main()
