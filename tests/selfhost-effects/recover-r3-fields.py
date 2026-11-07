#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh bounded field-authority attempts, retaining genuine source deferrals."""
from state import ROOT, load_module


def corpus():
	oracle = load_module('r3_field_oracle_sources', ROOT/'tests/selfhost-effects/recover-r3-source-oracles.py'); policy = load_module('r3_field_constructor_sources', ROOT/'tests/selfhost-effects/recover-r3-policy.py')
	rows = {name:text for name, text in oracle.corpus().items() if name in ('owned-writable-field-assignment', 'owned-call-field-error')}
	rows.update({name:text for name, (legal, text) in policy.corpus().items() if name in ('fielded-derived-Error', 'computed-base-message') and legal})
	assert len(rows) == 4
	return rows


def main():
	runner = load_module('r3_field_frontier_runner', ROOT/'tests/selfhost-effects/recover-frontier.py'); runner.corpus = corpus; runner.main()


if __name__ == '__main__':
	main()
