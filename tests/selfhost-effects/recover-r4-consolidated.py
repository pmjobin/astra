#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R4 integrated qualification; every job outcome stays explicit, including failures."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--resume', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_final_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-consolidated-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=a.resume); identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	jobs = [('recover-regression', a.version, []), ('recover-qualify', a.version+'scalar', ['--expanded']), ('recover-record-qualify', a.version+'record', []), ('recover-owned-qualify', a.version+'owned', []), ('recover-error-owned-qualify', a.version+'errors', []), ('recover-loop-qualify', a.version+'loops', []), ('recover-r3-qualify', a.version+'literal', []), ('recover-r3-domain-qualify', a.version+'domain', []), ('recover-adversarial', a.version, []), ('recover-owner-adversarial', a.version, []), ('recover-loop-adversarial', a.version, []), ('recover-r3-adversarial', a.version, []), ('recover-r3-domain-adversarial', a.version, []), ('recover-class-policy', a.version, []), ('recover-r4-policy', a.version, []), ('recover-null-guard', a.version, []), ('recover-r3-receiver-guard', a.version, []), ('recover-r3-float-probe', a.version, []), ('recover-success-probe', a.version, []), ('recover-abi-limit', a.version+a.mode, []), ('recover-original', a.version, ['--provider-build', str(a.component.parent)]), ('recover-r3-original-view', a.version, ['--ledger-component', str(a.component)]), ('recover-frontier', a.version, []), ('recover-r3-fields', a.version+'fields', []), ('recover-r3-source-oracles', a.version, []), ('recover-r3-observe', a.version, ['--native-version', a.version+'literal']), ('recover-r3-root', a.version, ['--regression', 'regression-'+a.version+'-'+a.mode])]
	jobs += [('recover-r4-qualify', a.version+'fields', []), ('recover-r4-adversarial', a.version, []), ('recover-r4-message', a.version, []), ('recover-r4-lifetime', a.version, []), ('recover-r4-guard', a.version, []), ('recover-r4-loans', a.version, []), ('recover-r4-original-view', a.version, ['--ledger-component', str(a.component)]), ('recover-r4-source-policy', a.version, []), ('recover-r4-layout', a.version, []), ('recover-r4-extra-policy', a.version, []), ('recover-r4-retained', a.version, [])]
	commands = read(leaf/'commands.json') if a.resume else []; versions = {}; environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
	for name, version, extra in jobs:
		if name == 'recover-r3-observe': extra = ['--native-version', versions['recover-r3-qualify']]
		if name == 'recover-r3-root': extra = ['--regression', 'regression-'+versions['recover-regression']+'-'+a.mode]
		if name == 'recover-r4-source-policy': extra = ['--original-version', versions['recover-original'], '--view-version', versions['recover-r3-original-view'], '--minimal-view-version', versions['recover-r4-original-view']]
		previous = [row for row in commands if row['name'] == name]; prior = previous[-1] if previous else None
		if prior:
			assert prior['component_sha256'] == sha(a.component) and sha(leaf/(prior['label']+'.stdout')) == prior['stdout_sha256'] and sha(leaf/(prior['label']+'.stderr')) == prior['stderr_sha256']
			if prior['exit'] == 0:
				versions[name] = prior['version']; continue
			version += 'retry'+str(len(previous))
		label = name+('-retry'+str(len(previous)) if previous else ''); argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r4.py', name, '--version', version]
		if name != 'recover-abi-limit': argv += ['--mode', a.mode]
		if name not in ('recover-r3-observe', 'recover-r3-root', 'recover-r3-source-oracles', 'recover-r4-layout', 'recover-r4-extra-policy'): argv += ['--component', a.component]
		argv += extra; start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *map(str, argv)], cwd=ROOT, env=environment, capture_output=True, timeout=2400); (leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, label=label, version=version, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(a.component), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); versions[name] = version; print(a.mode, name, 'recipe exit', r.returncode, '; actual results and deferrals retained', flush=True)
	def location(prefix, job): return prefix+'-'+versions[job]+'-'+a.mode
	configuration = dict(component=str(a.component), regression=location('regression', 'recover-regression'), native_results=[location('early', job) for job in ('recover-qualify', 'recover-record-qualify', 'recover-owned-qualify', 'recover-error-owned-qualify', 'recover-loop-qualify')], new_native_results=[location('early', job) for job in ('recover-r3-qualify', 'recover-r3-domain-qualify')], adversarial=[location(prefix, job) for prefix, job in [('adversarial', 'recover-adversarial'), ('owner-adversarial', 'recover-owner-adversarial'), ('loop-adversarial', 'recover-loop-adversarial')]], new_adversarial=[location(prefix, job) for prefix, job in [('r3-adversarial', 'recover-r3-adversarial'), ('r3-domain-adversarial', 'recover-r3-domain-adversarial')]], original=location('original', 'recover-original'), original_view=location('original-view', 'recover-r3-original-view'), receiver_guard=location('r3-receiver-guard', 'recover-r3-receiver-guard'), floating_probe=location('r3-float-probe', 'recover-r3-float-probe'), frontier=location('frontier', 'recover-frontier'), fields=location('frontier', 'recover-r3-fields'), source_oracles=location('source-oracles', 'recover-r3-source-oracles'), class_policy=location('class-policy', 'recover-class-policy'), r4_policy=location('r4-policy', 'recover-r4-policy'), dynamic_observer=location('r3-observer', 'recover-r3-observe'), root='root-'+versions['recover-r3-root']+'-'+a.mode+'.json', null_guard=location('null-guard', 'recover-null-guard'), ABI_success_probe=location('success-cell', 'recover-success-probe'), ABI_limit='abi-limit-'+versions['recover-abi-limit'])
	configuration.update(r4_native=location('early', 'recover-r4-qualify'), r4_adversarial=location('r4-adversarial', 'recover-r4-adversarial'), original_message=location('r4-message', 'recover-r4-message'), lifetime=location('r4-lifetime', 'recover-r4-lifetime'), field_guard=location('r4-field-guard', 'recover-r4-guard'), independent_layout=location('r4-layout', 'recover-r4-layout'), independent_field_producers=location('r4-extra-policy', 'recover-r4-extra-policy'), exact_retained_inputs=location('r4-retained', 'recover-r4-retained'))
	configuration['minimal_original_view'] = location('r4-original-view', 'recover-r4-original-view')
	configuration.update(class_loans=location('r4-loans', 'recover-r4-loans'), original_policy=location('r4-source-policy', 'recover-r4-source-policy'))
	latest = {row['name']:row for row in commands}; failed = [name for name, row in latest.items() if row['exit'] != 0]
	(leaf/'result.json').write_text(json.dumps(dict(status='R4_CONSOLIDATED_RECIPES_PARTIAL' if failed else 'R4_CONSOLIDATED_RECIPES_COMPLETED', failed_jobs=failed, profile=a.mode, component_sha256=sha(a.component), profile_configuration=configuration, limitation='Recipe completion is not milestone PASS. The final source-bound audit retains every incomplete bounded gate.'), indent=2)+'\n'); print(a.mode, 'R4 integrated recipes complete; failed jobs:', failed, flush=True)
	if failed: raise SystemExit(1)


if __name__ == '__main__':
	main()
