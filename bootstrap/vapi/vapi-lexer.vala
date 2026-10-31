// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Vapi {
public class VapiLexer : Object {
	public Diagnostic? diagnostic { get; private set; }
	private SourceFile source;
	private int offset = 0;

	public VapiLexer (SourceFile source) {
		this.source = source;
		diagnostic = source.validate_encoding ();
	}

	private static bool identifier_start(uint8 value) {
		return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') || value == '_';
	}

	private bool skip_trivia() {
		while (offset < source.length) {
			uint8 value = source.byte_at (offset);
			if (value == ' ' || value == '\t' || value == '\n' || value == '\r' || value == '\v' || value == '\f') {
				offset++;
				continue;
			}
			if (value != '/' || offset + 1 == source.length) {
				break;
			}
			uint8 next = source.byte_at (offset + 1);
			if (next == '/') {
				offset += 2;
				while (offset < source.length && source.byte_at (offset) != '\n' && source.byte_at (offset) != '\r') {
					offset++;
				}
			} else if (next == '*') {
				int start = offset;
				offset += 2;
				while (offset + 1 < source.length && !(source.byte_at (offset) == '*' && source.byte_at (offset + 1) == '/')) {
					offset++;
				}
				if (offset + 1 >= source.length) {
					diagnostic = new Diagnostic (SourceSpan (source, start, start + 2), "unterminated VAPI block comment");
					return false;
				}
				offset += 2;
			} else {
				break;
			}
		}
		return true;
	}

	private VapiToken? string_token(int start) {
		var value = new StringBuilder ();
		while (offset < source.length) {
			uint8 next = source.byte_at (offset++);
			if (next == '"') {
				return new VapiToken (VapiTokenKind.STRING, SourceSpan (source, start, offset), value.str);
			}
			if (next == '\n' || next == '\r') {
				break;
			}
			if (next == '\\') {
				int escape_start = offset - 1;
				if (offset == source.length) {
					break;
				}
				switch (source.byte_at (offset++)) {
				case '"': next = '"';
					break;
				case '\\': next = '\\';
					break;
				case 'n':
					next = '\n';
					break;
				case 'r':
					next = '\r';
					break;
				case 't':
					next = '\t';
					break;
				default:
					diagnostic = new Diagnostic (SourceSpan (source, escape_start, escape_start + 1), "invalid VAPI string escape");
					return null;
				}
			}
			// SourceFile has already validated complete UTF-8 and rejected NUL.
			value.append_c ((char) next);
		}
		diagnostic = new Diagnostic (SourceSpan (source, start, start + 1), "unterminated VAPI string literal");
		return null;
	}

	public VapiToken? next_token() {
		if (diagnostic != null || !skip_trivia ()) {
			return null;
		}
		int start = offset;
		if (offset == source.length) {
			return new VapiToken (VapiTokenKind.EOF, SourceSpan (source, offset, offset));
		}
		uint8 value = source.byte_at (offset++);
		VapiTokenKind kind;
		if (identifier_start (value)) {
			while (offset < source.length) {
				uint8 next = source.byte_at (offset);
				if (!identifier_start (next) && !(next >= '0' && next <= '9')) {
					break;
				}
				offset++;
			}
			switch (SourceSpan (source, start, offset).text ()) {
			case "borrowed": kind = VapiTokenKind.BORROWED;
				break;
			case "owned":
				kind = VapiTokenKind.OWNED;
				break;
			case "handle":
				kind = VapiTokenKind.HANDLE;
				break;
			default:
				kind = VapiTokenKind.IDENTIFIER;
				break;
			}
		} else {
			switch (value) {
			case '"':
				return string_token (start);
			case '[':
				kind = VapiTokenKind.OPEN_BRACKET;
				break;
			case ']':
				kind = VapiTokenKind.CLOSE_BRACKET;
				break;
			case '=':
				kind = VapiTokenKind.EQUAL;
				break;
			case '(':
				kind = VapiTokenKind.OPEN_PAREN;
				break;
			case ')':
				kind = VapiTokenKind.CLOSE_PAREN;
				break;
			case ',':
				kind = VapiTokenKind.COMMA;
				break;
			case ';':
				kind = VapiTokenKind.SEMICOLON;
				break;
			case '*':
				kind = VapiTokenKind.STAR;
				break;
			default:
				int width = value < 0x80 ? 1 : value < 0xe0 ? 2 : value < 0xf0 ? 3 : 4;
				var span = SourceSpan (source, start, start + width);
				string message = value >= 0x80 ? "non-ASCII character is not supported outside VAPI comments or strings" : "unexpected VAPI character '%s'".printf (span.text ().escape ());
				diagnostic = new Diagnostic (span, message);
				return null;
			}
		}
		return new VapiToken (kind, SourceSpan (source, start, offset));
	}
}
}
