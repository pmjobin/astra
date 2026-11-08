#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Shared source witnesses modeled on the original SourceSpan owner paths."""

VALUE = '''class SharedValue {
	private int number;
	init(int number) { this.number = number; }
	int read() { return this.number; }
}
int read_value(borrowed SharedValue value) { return value.read(); }
'''

HOLDER = '''class SharedHolder {
	private owned shared SharedValue handle;
	init(owned shared SharedValue handle) { this.handle = move handle; }
	int read() { var retained = shared_clone(this.handle); return read_value(shared_borrow(retained)); }
	void replace(owned shared SharedValue replacement) { this.handle = move replacement; }
}
'''


def corpus():
	start = 'var value = new SharedValue(42); var handle = shared_acquire(move value); '
	rows = {
		'shared-clone-borrow-success': VALUE+'int main() { '+start+'var retained = shared_clone(handle); return read_value(shared_borrow(retained)); }\n',
		'shared-field-success': VALUE+HOLDER+'int main() { '+start+'var retained = shared_clone(handle); var holder = new SharedHolder(move retained); return holder.read(); }\n',
		'shared-scope-success': VALUE+'int main() { '+start+'{ var retained = shared_clone(handle); if (read_value(shared_borrow(retained)) != 42) return 3; } return read_value(shared_borrow(handle)); }\n',
		'shared-field-replacement-success': VALUE+HOLDER+'int main() { var first = new SharedValue(3); var first_handle = shared_acquire(move first); var holder = new SharedHolder(move first_handle); '+start+'holder.replace(move handle); return holder.read(); }\n',
	}
	for name, body, extra in [
		('acquire', start, ''),
		('clone', start+'var retained = shared_clone(handle); ', ''),
		('two-clones', start+'var retained = shared_clone(handle); var other = shared_clone(retained); ', ''),
		('field', start+'var holder = new SharedHolder(move handle); if (holder.read() != 42) return 3; ', HOLDER),
		('replacement', 'var first = new SharedValue(3); var first_handle = shared_acquire(move first); var holder = new SharedHolder(move first_handle); '+start+'holder.replace(move handle); if (holder.read() != 42) return 3; ', HOLDER),
	]:
		rows['shared-'+name+'-error'] = VALUE+extra+'int leaf() throws Error { '+body+'throw new Error("'+name+'"); } int main() { try { return leaf(); } catch (Error caught) { if (caught.message == "'+name+'") return 42; return 4; } }\n'
	rows['shared-owned-parameter-error'] = VALUE+'int fail(owned shared SharedValue handle) throws Error { if (read_value(shared_borrow(handle)) != 42) return 3; throw new Error("owned"); } int main() { try { '+start+'return fail(move handle); } catch (Error caught) { if (caught.message == "owned") return 42; return 4; } }\n'
	rows['shared-borrowed-parameter-error'] = VALUE+'int fail(borrowed shared SharedValue handle) throws Error { var retained = shared_clone(handle); if (read_value(shared_borrow(retained)) != 42) return 3; throw new Error("borrowed"); } int main() { '+start+'try { return fail(handle); } catch (Error caught) { if (caught.message == "borrowed") return read_value(shared_borrow(handle)); return 4; } }\n'
	rows['shared-nested-error'] = VALUE+'int fail(borrowed shared SharedValue handle) throws Error { var retained = shared_clone(handle); throw new Error("nested"); } int main() { '+start+'try { { var retained = shared_clone(handle); return fail(retained); } } catch (Error caught) { if (caught.message == "nested") return read_value(shared_borrow(handle)); return 4; } }\n'
	assert len(rows) == 12 and sum(not name.endswith('-success') for name in rows) == 8
	return rows
