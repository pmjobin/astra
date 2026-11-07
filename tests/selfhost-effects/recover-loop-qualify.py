#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Executed lexical loop exits, repeated owner versions and checked conditions."""
import sys
from state import ROOT, load_module


def corpus():
	leaf = 'void leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } }\n'
	rows = {
		'loop-break-cleanup-success': 'int main() { var outer = new int[5]; while (true) { var inner = new int[3]; break; } return len(outer) + 37; }\n',
		'loop-return-cleanup-success': 'int main() { while (true) { var inner = new int[3]; return len(inner) + 39; } return 3; }\n',
		'loop-continue-cleanup-success': 'int main() { int count = 0; while (count < 3) { var inner = new int[3]; count = count + 1; continue; } return count + 39; }\n',
		'loop-nested-break-success': 'int main() { int count = 0; while (count < 2) { var outer = new int[5]; while (true) { var inner = new int[3]; break; } count = count + 1; } return count + 40; }\n',
		'loop-catch-continue-error': leaf+'int main() { int count = 0; while (count < 3) { var inner = new int[3]; count = count + 1; try { leaf(true); } catch (Error caught) { if (caught.message != "kept") return 3; continue; } } return count + 39; }\n',
		'loop-catch-break-error': leaf+'int main() { while (true) { var inner = new int[3]; try { leaf(true); } catch (Error caught) { if (caught.message != "kept") return 3; break; } } return 42; }\n',
		'loop-condition-error': 'bool test(bool fail) throws Error { if (fail) { throw new Error("kept"); } return false; }\nint main() { var outer = new int[2]; try { while (test(true)) { var inner = new int[3]; return 4; } return 3; } catch (Error caught) { if (caught.message == "kept") return len(outer) + 40; return 5; } }\n',
		'loop-propagate-error': leaf+'int relay() throws Error { int count = 0; while (count < 2) { var inner = new int[3]; count = count + 1; leaf(count > 1); } return 3; }\nint main() { try { return relay(); } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }\n',
		'loop-throw-move-error': 'int main() { int count = 0; while (count < 3) { count = count + 1; try { var value = new Error("kept"); throw move value; } catch (Error caught) { if (caught.message != "kept") return 3; continue; } } return count + 39; }\n'
	}
	for operation, name in [('throw;', 'loop-bare-rethrow-error'), ('throw new Error(caught.message);', 'loop-replacement-error')]:
		rows[name] = leaf+'int relay() throws Error { int count = 0; while (count < 2) { var inner = new int[3]; count = count + 1; try { leaf(true); } catch (Error caught) { '+operation+' } } return 3; }\nint main() { try { return relay(); } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }\n'
	rows['loop-empty-owner-success'] = 'class Parcel { init() {} }\nowned Parcel make(bool empty) throws Error { if (empty) return null; var value = new Parcel(); return move value; }\nint main() { int count = 0; while (count < 3) { try { var value = make(true); count = count + 1; } catch (Error caught) { return 4; } } return count + 39; }\n'
	assert len(rows) == len(set(rows.values()))
	return rows


if __name__ == '__main__':
	runner = load_module('loop_runner', ROOT/'tests/selfhost-effects/recover-qualify.py'); runner.expanded_corpus = corpus; sys.argv.append('--expanded'); runner.main()
