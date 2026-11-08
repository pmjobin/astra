#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep independently rejected owned results/receiver forms rejected by Astra."""
from state import ROOT, load_module


def main():
	oracle = load_module('negative_owner_forms', ROOT/'tests/selfhost-effects/recover-owner-form-oracles.py')
	positive = {'derived-error-field', 'derived-error-computed-base', 'derived-error-snapshot', 'field-receiver', 'owned-result-explicit-transfer'}
	negative = load_module('negative_owner_runner', ROOT/'tests/selfhost-effects/recover-array-source-negative.py')
	negative.GROUP = 'owner'
	negative.CASES = {name: source for name, source in oracle.CASES.items() if name not in positive}
	assert len(negative.CASES) == 6
	negative.main()


if __name__ == '__main__':
	main()
