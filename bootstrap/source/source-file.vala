// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public class SourceFile : Object {
	public bool native_interface { get; private set; }
	public string path { get { return filename; } }
	private string filename;
	public int length { get { return content.length; } }
	private uint8[] content;
	private GLib.Array<int> line_starts = new GLib.Array<int> ();

	// Correct, bounded GLib declarations: the stock VAPI deprecates ndup
	// and declares utf8_validate_len's const output pointer as mutable.
	[CCode (cname = "g_strndup", cheader_filename = "glib.h")]
	private static extern string copy_bytes(char* bytes, size_t length);
	[CCode (cname = "g_utf8_validate_len", cheader_filename = "glib.h")]
	private static extern bool validate_bytes(char* bytes, size_t length, out unowned string end);

	public SourceFile (string path, owned uint8[] content, bool native_interface = false) {
		this.native_interface = native_interface;
		this.filename = normalize_path (path);
		this.content = (owned) content;
		int line_start = 0;
		line_starts.append_val (line_start);
		for (int i = 0; i < length; i++) {
			if (this.content[i] == '\r') {
				if (i + 1 < length && this.content[i + 1] == '\n') {
					i++;
				}
				line_start = i + 1;
				line_starts.append_val (line_start);
			} else if (this.content[i] == '\n') {
				line_start = i + 1;
				line_starts.append_val (line_start);
			}
		}
	}

	public SourceFile.from_text (string path, string text, bool native_interface = false) {
		this(path, text.data.copy (), native_interface);
	}

	// Lexical only: retain relative/absolute spelling, case and '..'. Removing
	// '..' could change symlink traversal. No realpath/inode identity is used.
	public static string normalize_path(string path) {
		var parts = new GenericArray<string> ();
		foreach (string part in path.split (Path.DIR_SEPARATOR_S)) {
			if (part != "" && part != ".") {
				parts.add (part);
			}
		}
		var result = new StringBuilder (Path.is_absolute (path) ? Path.DIR_SEPARATOR_S : "");
		foreach (string part in parts) {
			if (result.len != 0 && !result.str.has_suffix (Path.DIR_SEPARATOR_S)) {
				result.append (Path.DIR_SEPARATOR_S);
			}
			result.append (part);
		}
		return result.len == 0 ? "." : result.str;
	}

	public uint8 byte_at(int offset) {
		assert (offset >= 0 && offset < length);
		return content[offset];
	}

	public string slice(int start, int end) {
		assert (start >= 0 && start <= end && end <= length);
		if (start == end) {
			return "";
		}
		return copy_bytes ((char*) content + start, end - start);
	}

	public Diagnostic? validate_encoding() {
		if (length == 0) {
			return null;
		}
		unowned string end;
		if (validate_bytes ((char*) content, length, out end)) {
			return null;
		}
		int offset = (int) ((char*) end - (char*) content);
		string message = content[offset] == 0 ? "unexpected NUL byte" : "invalid UTF-8 encoding";
		return new Diagnostic (SourceSpan (this, offset, offset + 1), message);
	}

	public void locate(int offset, out int line, out int column) {
		assert (offset >= 0 && offset <= length);
		int low = 0;
		int high = (int) line_starts.length;
		while (low + 1 < high) {
			int middle = low + (high - low) / 2;
			if (line_starts.index (middle) <= offset) {
				low = middle;
			} else {
				high = middle;
			}
		}
		line = low + 1;
		column = 1;
		// Valid UTF-8 prefixes have one non-continuation byte per scalar.
		// Both bytes of CRLF denote the same end-of-line column.
		for (int i = line_starts.index (low); i < offset; i++) {
			if ((content[i] & 0xc0) != 0x80 && content[i] != '\r' && content[i] != '\n') {
				column++;
			}
		}
	}

}
}
