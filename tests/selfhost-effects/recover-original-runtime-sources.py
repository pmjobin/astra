#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Call complete original builder/source/formatter declarations without substitutes."""


def corpus():
	rows = {
		'flow-boundaries': '''int main() {
	try {
		var output = new Utf8ByteBuilder();
		flow_number(output, 0);
		flow_number(output, -1);
		flow_number(output, 2147483647);
		flow_number(output, -2147483648);
		flow_number(output, 123456789);
		flow_number(output, -123456789);
		var message = output.snapshot();
		if (message.text == " 0 -1 2147483647 -2147483648 123456789 -123456789") return 42;
		return 3;
	} catch (Error caught) { return 4; }
}
''',
		'builder-empty': '''int main() {
	try {
		var output = new Utf8ByteBuilder();
		if (output.capacity() != 0 || output.byte_count() != 0) return 3;
		var empty = new u8[0];
		if (!output.append_bytes(empty) || !output.reserve(0) || output.reserve(-1)) return 4;
		if (output.capacity() != 0 || output.byte_count() != 0) return 5;
		var message = output.snapshot();
		if (message.text == "") return 42;
		return 6;
	} catch (Error caught) { return 7; }
}
''',
		'builder-growth-snapshot': '''int main() {
	try {
		var output = new Utf8ByteBuilder();
		if (!source_append_text(output, "abc") || output.capacity() != 4) return 3;
		var first = output.snapshot();
		if (!output.reserve(20) || output.capacity() != 20) return 4;
		if (!source_append_text(output, "defghijklmnopqrstuvwxyz") || output.capacity() != 40) return 5;
		if (!output.reserve(2) || output.capacity() != 40 || output.reserve(-1)) return 6;
		var last = output.snapshot();
		if (first.text != "abc" || last.text != "abcdefghijklmnopqrstuvwxyz" || output.byte_count() != 26) return 7;
		return 42;
	} catch (Error caught) { return 8; }
}
''',
		'formatter-widths': '''int main() {
	try {
		var output = new Utf8ByteBuilder();
		if (!append_int(output, -2147483648) || !append_u32(output, 4294967295)) return 3;
		if (!append_bool(output, false) || !append_bool(output, true)) return 4;
		if (!append_i64(output, -9223372036854775808) || !append_u64(output, 18446744073709551615)) return 5;
		var message = output.snapshot();
		if (message.text == "-21474836484294967295falsetrue-922337203685477580818446744073709551615") return 42;
		return 6;
	} catch (Error caught) { return 7; }
}
''',
		'source-empty': '''int main() {
	try {
		var bytes = new u8[0];
		var source = source_buffer("", move bytes, true);
		if (source.length != 0 || !source.native_interface || source.encoding_error() != -1) return 3;
		var where = source.locate(0);
		if (where.line != 1 || where.column != 1 || !source.valid_span(0, 0)) return 4;
		var copied = source.copy_range(0, 0);
		var path = source_path(source);
		if (len(copied) == 0 && path.text == ".") return 42;
		return 5;
	} catch (Error caught) { return 6; }
}
''',
		'source-lines-copy': '''int main() {
	try {
		var bytes = new u8[7];
		bytes[0] = 65; bytes[1] = 13; bytes[2] = 10; bytes[3] = 195; bytes[4] = 169; bytes[5] = 10; bytes[6] = 122;
		var source = source_buffer("a/./b", move bytes, false);
		if (source.length != 7 || source.native_interface || source.encoding_error() != -1 || source.byte_at(6) != 122) return 3;
		var first = source.locate(0);
		var second = source.locate(5);
		var last = source.locate(7);
		if (first.line != 1 || first.column != 1 || second.line != 2 || second.column != 2 || last.line != 3 || last.column != 2) return 4;
		var copied = source.copy_range(3, 5);
		if (len(copied) != 2 || copied[0] != 195 || copied[1] != 169) return 5;
		var path = source_path(source);
		if (path.text == "a/b") return 42;
		return 6;
	} catch (Error caught) { return 7; }
}
''',
		'original-shared-span': '''int main() {
	try {
		var bytes = new u8[3]; bytes[0] = 65; bytes[1] = 10; bytes[2] = 66;
		var source = source_buffer("a/./b", move bytes, false);
		var handle = shared_acquire(move source);
		var retained = shared_clone(handle);
		var first = new SourceSpan(move retained, 0, 1);
		var last_handle = shared_clone(handle);
		var last = new SourceSpan(move last_handle, 2, 3);
		if (!first.same_source(last) || first.start != 0 || last.end != 3) return 3;
		var cover = first.cover(last);
		if (cover.start != 0 || cover.end != 3) return 4;
		var where = last.location();
		if (where.line != 2 || where.column != 1) return 5;
		var path = cover.path();
		var copied = cover.bytes();
		if (path.text == "a/b" && len(copied) == 3 && copied[0] == 65 && copied[1] == 10 && copied[2] == 66) return 42;
		return 6;
	} catch (Error caught) { return 7; }
}
''',
		'original-diagnostic': '''int main() {
	try {
		var bytes = new u8[3]; bytes[0] = 65; bytes[1] = 10; bytes[2] = 66;
		var source = source_buffer("a/./b", move bytes, false);
		var handle = shared_acquire(move source);
		var span = new SourceSpan(move handle, 2, 3);
		var text = new Utf8Message("oops");
		var diagnostic = new SourceDiagnostic(move span, move text);
		var message = diagnostic.format();
		if (message.text == "a/b:2:1: error: oops") return 42;
		return 3;
	} catch (Error caught) { return 4; }
}
''',
	}
	for name, expression in [('byte-negative', 'source.byte_at(-1)'), ('byte-end', 'source.byte_at(1)'), ('locate-past', 'source.locate(2)'), ('range-reversed', 'source.copy_range(1, 0)')]:
		rows['source-'+name+'-error'] = '''int main() {
	try {
		var bytes = new u8[1]; bytes[0] = 65;
		var source = source_buffer("x", move bytes, false);
		var invalid = '''+expression+''';
		return 3;
	} catch (SourceBoundsError caught) {
		if (caught.message == "invalid source span or offset") return 42;
		return 4;
	} catch (Error caught) { return 5; }
}
'''
	for name, values in [('continuation', [128]), ('truncated', [226, 130]), ('overlong', [192, 175]), ('surrogate', [237, 160, 128]), ('out-of-range', [244, 144, 128, 128]), ('bad-continuation', [226, 65, 128])]:
		rows['builder-'+name+'-error'] = '''int main() {
	try {
		var output = new Utf8ByteBuilder();
		u8['''+str(len(values))+'''] bytes = {'''+', '.join(map(str, values))+'''};
		if (!output.append_bytes(slice(bytes))) return 3;
		var invalid = output.snapshot();
		return 4;
	} catch (InvalidUtf8 caught) {
		if (caught.message == "invalid UTF-8") return 42;
		return 5;
	} catch (Error caught) { return 6; }
}
'''
	return rows
