#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real Error object owners, normal cleanup and guarded throw-move transfer."""
import sys
from state import ROOT, load_module


def corpus():
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 4; }'
	rows = {
		'error-local-cleanup-success': 'int main() { var value = new Error("kept"); return 42; }\n',
		'error-local-move-error': 'int main() { try { var value = new Error("kept"); throw move value; } '+catch+' }\n',
		'derived-error-local-move-error': 'int main() { try { var value = new RuntimeError("kept"); throw move value; } catch (RuntimeError caught) { if (caught.message == "kept") return 42; return 4; } catch (Error caught) { return 5; } }\n',
		'error-owned-input-error': 'void entered(owned Error value) throws Error { throw move value; }\nint main() { var value = new Error("kept"); try { entered(move value); return 3; } '+catch+' }\n',
		'error-owned-input-success': 'void entered(owned Error value) {}\nint main() { var value = new Error("kept"); entered(move value); return 42; }\n',
		'error-result-move-error': 'owned Error make() { var value = new Error("kept"); return move value; }\nint main() { try { var value = make(); throw move value; } '+catch+' }\n',
		'error-checked-result-success': 'owned Error make(bool fail) throws Error { if (fail) { throw new Error("other"); } var value = new Error("kept"); return move value; }\nint main() { try { var value = make(false); return 42; } catch (Error caught) { return 4; } }\n',
		'error-checked-result-error': 'owned Error make(bool fail) throws Error { if (fail) { throw new Error("kept"); } var value = new Error("other"); return move value; }\nint main() { try { var value = make(true); return 3; } '+catch+' }\n',
		'error-null-result-success': 'owned Error make(bool empty) { if (empty) return null; var value = new Error("kept"); return move value; }\nint main() { var value = make(true); return 42; }\n'
	}
	assert len(rows) == len(set(rows.values()))
	return rows


if __name__ == '__main__':
	runner = load_module('error_owned_runner', ROOT/'tests/selfhost-effects/recover-qualify.py'); runner.expanded_corpus = corpus; sys.argv.append('--expanded'); runner.main()
