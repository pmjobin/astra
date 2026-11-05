#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain explicit source bytes while long independent products are built."""
import argparse
import json
import subprocess
from state import ROOT, RUNTIME, sha, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--name', required=True); a = p.parse_args()
	assert a.name.replace('-', '').isalnum()
	leaf = RUNTIME/('source-'+a.name); leaf.mkdir(exist_ok=False)
	names = set(git('ls-files').splitlines())
	names.update(str(path.relative_to(ROOT)) for path in (ROOT/'tests/selfhost-genresource').iterdir() if path.suffix in ('.py', '.astra', '.md'))
	rows = {}
	for name in sorted(names):
		source = ROOT/name; assert source.is_file() and not source.is_symlink()
		target = leaf/name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read_bytes())
		assert sha(source) == sha(target); rows[name] = dict(bytes=source.stat().st_size, sha256=sha(source))
	(RUNTIME/('source-'+a.name+'.json')).write_text(json.dumps(dict(head=git('rev-parse', 'HEAD').strip(), tree=git('rev-parse', 'HEAD^{tree}').strip(), status=git('status', '--porcelain=v1', '--untracked-files=all'), files=rows), indent=2)+'\n')
	print(leaf, len(rows), 'source files')


if __name__ == '__main__':
	main()
