#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One current compiler with preserved inherited routes and genuine effects."""
import argparse
from pathlib import Path
import sys
import types
from state import ROOT, C0, load_module, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--check', action='store_true'); p.add_argument('--core-check', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('recover_full_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	full = load_module('recover_full_inputs', ROOT/'tests/selfhost-effects/full-build.py')
	full.RUNTIME = paths.RUNTIME; full.BUILD = paths.BUILD; full.INPUTS = paths.RUNTIME/('full-inputs-'+a.version); full.prepare()
	def view(path, old, new, name):
		text = path.read_text(); assert text.count(old) == 1; text = text.replace(old, new); target = full.INPUTS/name
		if target.exists(): assert target.read_text() == text
		else: target.write_text(text)
		return target
	typecore = view(ROOT/'tests/selfhost-effects/r1-typecore.astra', 'int main(string[] args)', 'int r1_typecore_cli(string[] args)', 'r1-typecore.astra')
	# The original observer's mutation spelling is distinct from older routes.
	text = typecore.read_text().replace('args[1] == "--mutations"', 'args[1] == "--r1-type-mutations"'); renamed = full.INPUTS/'r1-typecore-renamed.astra'
	if renamed.exists(): assert renamed.read_text() == text
	else: renamed.write_text(text)
	recover = view(ROOT/'tests/selfhost-effects/recover-query.astra', 'int main(string[] args)', 'int recover_cli(string[] args)', 'recover-query.astra')
	r2 = view(ROOT/'tests/selfhost-effects/r2-query.astra', 'int main(string[] args)', 'int r2_cli(string[] args)', 'r2-query.astra')
	genref = load_module('recover_genref_build', ROOT/'tests/selfhost-genref/build.py'); genref.RUNTIME = full.INPUTS
	original = genref.original
	def extend(*args, **kwargs):
		kwargs['consumer'] = ROOT/'tests/selfhost-effects/recover-full-query.astra'
		kwargs['extra_sources'] = [*kwargs['extra_sources'], full.INPUTS/'genref-query.astra', full.INPUTS/'flow-diagnostic.astra', full.INPUTS/'effects-observe.astra', renamed, recover, r2, ROOT/'tests/selfhost-effects/source.astra', ROOT/'tests/selfhost-effects/r1-owner.astra', ROOT/'tests/selfhost-effects/r2-abi.astra', ROOT/'tests/selfhost-effects/recover-mutations.astra', ROOT/'tests/selfhost-effects/recover-owner-mutations.astra']
		kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__), ROOT/'tests/selfhost-effects/observe.astra', ROOT/'tests/selfhost-effects/r1-typecore.astra', ROOT/'tests/selfhost-effects/recover-query.astra', ROOT/'tests/selfhost-effects/r2-query.astra']
		return original(*args, **kwargs)
	genref.original = extend; genref.base.core.base.build = genref.build
	genref.base.subprocess = types.SimpleNamespace(**vars(genref.base.subprocess))
	def run(argv, **kwargs):
		kwargs.setdefault('timeout', 3600); return bounded_run(argv, **kwargs)
	genref.base.subprocess.run = run
	if a.core_check:
		original_run = run
		def core_run(argv, **kwargs):
			words = list(map(str, argv))
			if '--check' in words: words[words.index('--check')] = '--dump-core'
			return original_run(words, **kwargs)
		genref.base.subprocess.run = core_run
	sys.argv = [sys.argv[0], '--compiler', str(C0), '--build', str(paths.BUILD/('full-'+a.version+'-'+a.mode)), '--runtime', str(paths.RUNTIME/('full-build-'+a.version+'-'+a.mode)), '--mode', a.mode]
	if a.check or a.core_check: sys.argv += ['--semantic-only']
	genref.base.main()


if __name__ == '__main__':
	main()
