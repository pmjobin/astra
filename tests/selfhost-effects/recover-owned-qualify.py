#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owned success storage, later-argument abort and entered-callee cleanup."""
import sys
from state import ROOT, load_module


def corpus():
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 4; }'
	leaf = 'owned int[] make(bool fail) throws Error { var value = new int[2]; if (fail) { throw new Error("kept"); } return move value; }\n'
	forward = 'owned int[] forward(owned int[] value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return move value; }\n'
	gate = 'int forty(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 40; }\n'
	consume = 'int consume(owned int[] value, int extra) { return len(value) + extra; }\n'
	rows = {
		'buffer-result-success': leaf+'int main() { try { var value = make(false); return len(value) + 40; } catch (Error caught) { return 4; } }\n',
		'buffer-result-error': leaf+'int main() { try { var value = make(true); return 3; } '+catch+' }\n',
		'buffer-forward-success': forward+'int main() { var input = new int[2]; try { var value = forward(move input, false); return len(value) + 40; } catch (Error caught) { return 4; } }\n',
		'buffer-entered-error': forward+'int main() { var input = new int[2]; try { var value = forward(move input, true); return 3; } '+catch+' }\n',
		'buffer-reservation-abort-error': gate+consume+'int main() { var input = new int[2]; try { return consume(move input, forty(true)); } catch (Error caught) { return consume(move input, 40); } }\n',
		'buffer-reservation-abort-retire-error': gate+consume+'int main() { var input = new int[2]; try { return consume(move input, forty(true)); } catch (Error caught) { return len(input) + 40; } }\n',
		'buffer-reservation-commit-success': gate+consume+'int main() { var input = new int[2]; try { return consume(move input, forty(false)); } catch (Error caught) { return 4; } }\n',
		'buffer-caller-retained-error': gate+'int main() { var input = new int[2]; try { return forty(true); } catch (Error caught) { return len(input) + 40; } }\n',
		'buffer-protected-scope-error': gate+'int main() { try { var input = new int[2]; return forty(true); } '+catch+' }\n',
		'buffer-lexical-exit-success': 'int main() { { var input = new int[2]; } return 42; }\n',
		'buffer-return-call-success': leaf+'owned int[] relay(bool fail) throws Error { return make(fail); }\nint main() { try { var value = relay(false); return len(value) + 40; } catch (Error caught) { return 4; } }\n'
	}
	for fail in (False, True):
		flag = str(fail).lower(); name = 'buffer-void-entered-'+('error' if fail else 'success')
		rows[name] = 'void entered(owned int[] value, bool fail) throws Error { if (fail) { throw new Error("kept"); } }\nint main() { var input = new int[2]; try { entered(move input, '+flag+'); return '+('3' if fail else '42')+'; } '+(catch if fail else 'catch (Error caught) { return 4; }')+' }\n'
	box = 'class Parcel { init() {} }\n'
	for failing in (False, True):
		flag = str(failing).lower(); suffix = '-error' if failing else '-success'
		rows['class-result'+suffix] = box+'owned Parcel make(bool fail) throws Error { var value = new Parcel(); if (fail) { throw new Error("kept"); } return move value; }\nint main() { try { var value = make('+flag+'); return '+('3' if failing else '42')+'; } '+(catch if failing else 'catch (Error caught) { return 4; }')+' }\n'
	rows['class-null-owner-success'] = box+'owned Parcel make(bool empty) throws Error { if (empty) return null; var present = new Parcel(); return move present; }\nint main() { try { var value = make(true); return 42; } catch (Error caught) { return 4; } }\n'
	assert len(rows) == len(set(rows.values()))
	return rows


if __name__ == '__main__':
	runner = load_module('owned_independent_runner', ROOT/'tests/selfhost-effects/recover-qualify.py')
	runner.expanded_corpus = corpus
	sys.argv.append('--expanded')
	runner.main()
