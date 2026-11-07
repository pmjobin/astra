#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""New source identities using the byte-exact original literal constructor."""
import hashlib
import sys
from state import ROOT, load_module


def corpus():
	data = (ROOT/'compiler/source/source.astra').read_bytes()
	declaration = data[134:220]
	assert hashlib.sha256(declaration).hexdigest() == 'd899055a27a7f6906036b3551ce2e5837712a8285c0f05a8e102ed32fa2eab8c'
	prefix = declaration.decode()+'\n'
	message = 'invalid source span or offset'
	catch = 'catch (Error caught) { if (caught.message == "'+message+'") return 42; return 4; }'
	leaf = 'int leaf(bool fail) throws SourceBoundsError { if (fail) { throw new SourceBoundsError(); } return 17; }\n'
	rows = {
		'literal-exact-catch': leaf+'int main() { try { return leaf(true); } catch (SourceBoundsError caught) { if (caught.message == "'+message+'") return 42; return 4; } catch (Error ancestor) { return 5; } }\n',
		'literal-ancestor-catch': leaf+'int main() { try { return leaf(true); } '+catch+' }\n',
		'literal-sibling-dispatch': leaf+'int main() { try { return leaf(true); } catch (RuntimeError sibling) { return 5; } '+catch+' }\n',
		'literal-nested-propagation': leaf+'int relay() throws Error { return leaf(true) + 25; }\nint main() { try { return relay(); } '+catch+' }\n',
		'literal-bare-rethrow': leaf+'int relay() throws Error { try { return leaf(true); } catch (SourceBoundsError caught) { throw; } }\nint main() { try { return relay(); } '+catch+' }\n',
		'literal-replacement-owner': 'int relay() throws Error { try { throw new Error("old"); } catch (Error old) { throw new SourceBoundsError(); } }\nint main() { try { return relay(); } '+catch+' }\n',
		'literal-owned-local-throw': 'int leaf() throws SourceBoundsError { var failure = new SourceBoundsError(); throw move failure; }\nint main() { try { return leaf(); } '+catch+' }\n',
		'literal-reservation-abort': 'int fail() throws SourceBoundsError { throw new SourceBoundsError(); }\nint consume(owned int[] data, int extra) { return len(data) + extra; }\nint main() { var data = new int[42]; try { return consume(move data, fail()); } catch (Error caught) { if (len(data) == 42) { if (caught.message == "'+message+'") return 42; } return 4; } }\n',
		'literal-loop-error': leaf+'int main() { int i = 0; try { while (i < 3) { if (i == 2) return leaf(true); i = i + 1; } return 3; } '+catch+' }\n',
		'literal-scalar-success': leaf+'int main() { try { return leaf(false) + 25; } catch (Error caught) { return 4; } }\n',
		'literal-void-success': 'void leaf(bool fail) throws SourceBoundsError { if (fail) { throw new SourceBoundsError(); } }\nint main() { try { leaf(false); return 42; } catch (Error caught) { return 4; } }\n',
		'literal-owner-retirement-success': 'int leaf() throws Error { var failure = new SourceBoundsError(); return 42; }\nint main() { try { return leaf(); } catch (Error caught) { return 4; } }\n',
		'literal-owned-input-success': 'void consume(owned SourceBoundsError value) {}\nint main() { var failure = new SourceBoundsError(); consume(move failure); return 42; }\n',
	}
	return {name: prefix+text for name, text in rows.items()}


def main():
	if '--oracle-only' in sys.argv:
		qualification = load_module('r3_literal_oracle', ROOT/'tests/selfhost-effects/recover-frontier.py')
		qualification.corpus = corpus
		qualification.main()
		return
	qualification = load_module('r3_literal_qualification', ROOT/'tests/selfhost-effects/recover-qualify.py')
	qualification.expanded_corpus = corpus
	sys.argv += ['--expanded']
	qualification.main()


if __name__ == '__main__':
	main()
