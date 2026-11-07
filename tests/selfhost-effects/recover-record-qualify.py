#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reuse the independent LLVM/C0/memory runner for record carrier programs."""
import sys
from state import ROOT, load_module


def corpus():
	header = 'struct Pair { int left; int right; }\n'
	leaf = 'Pair make(bool fail) throws Error { Pair value = {left = 17, right = 25}; if (fail) { throw new RuntimeError("kept"); } return value; }\n'
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 4; }'
	rows = {
		'record-result-success': leaf+'int main() { try { var pair = make(false); return pair.left + pair.right; } catch (Error caught) { return 4; } }\n',
		'record-result-error': leaf+'int main() { try { var pair = make(true); return 3; } '+catch+' }\n',
		'record-forward-success': leaf+'Pair relay(bool fail) throws Error { return make(fail); }\nint main() { try { var pair = relay(false); return pair.left + pair.right; } catch (Error caught) { return 4; } }\n',
		'record-forward-error': leaf+'Pair relay(bool fail) throws Error { return make(fail); }\nint main() { try { var pair = relay(true); return 3; } '+catch+' }\n',
		'record-input-success': 'int consume(Pair value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value.left + value.right; }\nint main() { Pair input = {left = 17, right = 25}; try { return consume(input, false); } catch (Error caught) { return 4; } }\n',
		'record-input-error': 'int consume(Pair value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value.left + value.right; }\nint main() { Pair input = {left = 17, right = 25}; try { return consume(input, true); } '+catch+' }\n',
		'record-local-success': 'int source(int value) { return value; }\nint main() { Pair input = {left = source(17), right = source(25)}; var copy = input; return copy.left + copy.right; }\n',
		'record-catch-error': leaf+'int main() { try { var pair = make(true); return 3; } catch (RuntimeError caught) { Pair replacement = {left = 17, right = 25}; return replacement.left + replacement.right; } catch (Error caught) { return 4; } }\n'
	}
	return {name:header+source for name, source in rows.items()}


if __name__ == '__main__':
	runner = load_module('record_independent_runner', ROOT/'tests/selfhost-effects/recover-qualify.py')
	runner.expanded_corpus = corpus
	sys.argv.append('--expanded')
	runner.main()
