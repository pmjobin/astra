// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class CommentTrivia : Object {
	public SourceSpan span { get; private set; }
	internal CommentTrivia (SourceSpan span) {
		this.span = span;
	}

}

public class Lexer : Object {
	public GenericArray<CommentTrivia> comments { get; private set; default = new GenericArray<CommentTrivia> (); }
	public Diagnostic? diagnostic { get; private set; }
	private SourceFile source;
	private int offset = 0;

	public Lexer (SourceFile source) {
		this.source = source;
		diagnostic = source.validate_encoding ();
	}

	// Parser speculation owns an independent cursor and diagnostic.
	internal Lexer fork() {
		return new Lexer.from_cursor (this);
	}

	private Lexer.from_cursor (Lexer original) {
		this.source = original.source;
		this.offset = original.offset;
		this.diagnostic = original.diagnostic;
	}

	private static bool identifier_start(uint8 value) {
		return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') || value == '_';
	}

	private static bool digit(uint8 value) {
		return value >= '0' && value <= '9';
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
				int start = offset;
				offset += 2;
				while (offset < source.length && source.byte_at (offset) != '\n' && source.byte_at (offset) != '\r') {
					offset++;
				}
				comments.add (new CommentTrivia (SourceSpan (source, start, offset)));
			} else if (next == '*') {
				int start = offset;
				offset += 2;
				while (offset + 1 < source.length && !(source.byte_at (offset) == '*' && source.byte_at (offset + 1) == '/')) {
					offset++;
				}
				if (offset + 1 >= source.length) {
					diagnostic = new Diagnostic (SourceSpan (source, start, start + 2), "unterminated block comment");
					return false;
				}
				offset += 2;
				comments.add (new CommentTrivia (SourceSpan (source, start, offset)));
			} else {
				break;
			}
		}
		return true;
	}

	public Token? next_token() {
		if (diagnostic != null || !skip_trivia ()) {
			return null;
		}
		int start = offset;
		if (offset == source.length) {
			return new Token (TokenKind.EOF, SourceSpan (source, offset, offset));
		}
		uint8 value = source.byte_at (offset++);
		if (value == '"') {
			var decoder = new TextLiteralDecoder ();
			var payload = decoder.decode (source, start, ref offset);
			if (payload == null) {
				diagnostic = decoder.diagnostic;
				return null;
			}
			var token = new Token (TokenKind.TEXT, SourceSpan (source, start, offset));
			token.text_payload = payload;
			return token;
		}
		TokenKind kind;
		if (identifier_start (value)) {
			while (offset < source.length && (identifier_start (source.byte_at (offset)) || digit (source.byte_at (offset)))) {
				offset++;
			}
			switch (source.slice (start, offset)) {
			case "async": kind = TokenKind.ASYNC;
				break;
			case "await": kind = TokenKind.AWAIT;
				break;
			case "throws":
				kind = TokenKind.THROWS;
				break;
			case "throw":
				kind = TokenKind.THROW;
				break;
			case "try":
				kind = TokenKind.TRY;
				break;
			case "catch":
				kind = TokenKind.CATCH;
				break;
			case "enum":
				kind = TokenKind.ENUM;
				break;
			case "match":
				kind = TokenKind.MATCH;
				break;
			case "case":
				kind = TokenKind.CASE;
				break;
			case "struct":
				kind = TokenKind.STRUCT;
				break;
			case "class":
				kind = TokenKind.CLASS;
				break;
			case "this":
				kind = TokenKind.THIS;
				break;
			case "extern":
				kind = TokenKind.EXTERN;
				break;
			case "export":
				kind = TokenKind.EXPORT;
				break;
			case "return":
				kind = TokenKind.RETURN;
				break;
			case "true":
				kind = TokenKind.TRUE;
				break;
			case "false":
				kind = TokenKind.FALSE;
				break;
			case "null":
				kind = TokenKind.NULL;
				break;
			case "if":
				kind = TokenKind.IF;
				break;
			case "else":
				kind = TokenKind.ELSE;
				break;
			case "while":
				kind = TokenKind.WHILE;
				break;
			case "for":
				kind = TokenKind.FOR;
				break;
			case "foreach":
				kind = TokenKind.FOREACH;
				break;
			case "with":
				kind = TokenKind.WITH;
				break;
			case "nonnull":
				kind = TokenKind.NONNULL;
				break;
			case "break":
				kind = TokenKind.BREAK;
				break;
			case "all":
				kind = TokenKind.ALL;
				break;
			case "as":
				kind = TokenKind.AS;
				break;
			case "any":
				kind = TokenKind.ANY;
				break;
			case "dot_wrap":
				kind = TokenKind.DOT_WRAP;
				break;
			case "mac_wrap":
				kind = TokenKind.MAC_WRAP;
				break;
			case "dot":
				kind = TokenKind.DOT_F32;
				break;
			case "mac":
				kind = TokenKind.MAC_F32;
				break;
			case "sat_add":
				kind = TokenKind.SAT_ADD;
				break;
			case "sat_sub":
				kind = TokenKind.SAT_SUB;
				break;
			case "widen_low":
				kind = TokenKind.WIDEN_LOW;
				break;
			case "widen_high":
				kind = TokenKind.WIDEN_HIGH;
				break;
			case "pack_wrap":
				kind = TokenKind.PACK_WRAP;
				break;
			case "pack_sat":
				kind = TokenKind.PACK_SAT;
				break;
			case "interleave_low":
				kind = TokenKind.INTERLEAVE_LOW;
				break;
			case "interleave_high":
				kind = TokenKind.INTERLEAVE_HIGH;
				break;
			case "slice":
				kind = TokenKind.SLICE;
				break;
			case "len":
				kind = TokenKind.LEN;
				break;
			case "splat":
				kind = TokenKind.SPLAT;
				break;
			case "insert":
				kind = TokenKind.INSERT;
				break;
			case "shuffle":
				kind = TokenKind.SHUFFLE;
				break;
			case "select":
				kind = TokenKind.SELECT;
				break;
			case "borrowed":
				kind = TokenKind.BORROWED;
				break;
			case "owned":
				kind = TokenKind.OWNED;
				break;
			case "const":
				kind = TokenKind.CONST;
				break;
			case "var":
				kind = TokenKind.VAR;
				break;
			case "move":
				kind = TokenKind.MOVE;
				break;
			case "release":
				kind = TokenKind.RELEASE;
				break;
			case "swap":
				kind = TokenKind.SWAP;
				break;
			case "continue":
				kind = TokenKind.CONTINUE;
				break;
			default:
				kind = TokenKind.IDENTIFIER;
				break;
			}
		} else if (digit (value)) {
			while (offset < source.length && digit (source.byte_at (offset))) {
				offset++;
			}
			kind = TokenKind.INTEGER;
			if (offset + 1 < source.length && source.byte_at (offset) == '.' && digit (source.byte_at (offset + 1))) {
				kind = TokenKind.FLOAT;
				offset += 2;
				while (offset < source.length && digit (source.byte_at (offset))) {
					offset++;
				}
			}
			if (offset < source.length && (source.byte_at (offset) == 'e' || source.byte_at (offset) == 'E')) {
				kind = TokenKind.FLOAT;
				offset++;
				if (offset < source.length && (source.byte_at (offset) == '+' || source.byte_at (offset) == '-')) {
					offset++;
				}
				int exponent_start = offset;
				while (offset < source.length && digit (source.byte_at (offset))) {
					offset++;
				}
				if (offset == exponent_start) {
					diagnostic = new Diagnostic (SourceSpan (source, start, offset), "floating literal exponent requires digits");
					return null;
				}
			}
			if (kind == TokenKind.FLOAT && offset < source.length) {
				uint8 suffix = source.byte_at (offset);
				if (suffix == 'f' || suffix == 'F' || suffix == 'd' || suffix == 'D') {
					offset++;
				}
			}
		} else {
			// Maximal munch. Tokens retain exact spans so a future type parser
			// can contextually split >> into two adjacent closing tokens.
			if ((value == '&' || value == '|' || value == '<' || value == '>') && offset < source.length && source.byte_at (offset) == value) {
				offset++;
				return new Token (value == '&' ? TokenKind.AMPERSAND_AMPERSAND : value == '|' ? TokenKind.PIPE_PIPE : value == '<' ? TokenKind.SHIFT_LEFT : TokenKind.SHIFT_RIGHT, SourceSpan (source, start, offset));
			}
			switch (value) {
			case ':':
				kind = TokenKind.COLON;
				break;
			case '(':
				kind = TokenKind.OPEN_PAREN;
				break;
			case ')':
				kind = TokenKind.CLOSE_PAREN;
				break;
			case '[':
				kind = TokenKind.OPEN_BRACKET;
				break;
			case ']':
				kind = TokenKind.CLOSE_BRACKET;
				break;
			case '{':
				kind = TokenKind.OPEN_BRACE;
				break;
			case '}':
				kind = TokenKind.CLOSE_BRACE;
				break;
			case '.':
				kind = TokenKind.DOT;
				break;
			case ',':
				kind = TokenKind.COMMA;
				break;
			case ';':
				kind = TokenKind.SEMICOLON;
				break;
			case '=':
				kind = match_equal () ? TokenKind.EQUAL_EQUAL : TokenKind.EQUAL;
				break;
			case '!':
				kind = match_equal () ? TokenKind.BANG_EQUAL : TokenKind.BANG;
				break;
			case '<':
				kind = match_equal () ? TokenKind.LESS_EQUAL : TokenKind.LESS;
				break;
			case '>':
				kind = match_equal () ? TokenKind.GREATER_EQUAL : TokenKind.GREATER;
				break;
			case '+':
				kind = TokenKind.PLUS;
				break;
			case '&':
				kind = TokenKind.AMPERSAND;
				break;
			case '|':
				kind = TokenKind.PIPE;
				break;
			case '^':
				kind = TokenKind.CARET;
				break;
			case '~':
				kind = TokenKind.TILDE;
				break;
			case '-':
				if (offset < source.length && source.byte_at (offset) == '>') {
					offset++;
					kind = TokenKind.ARROW;
				} else {
					kind = TokenKind.MINUS;
				}
				break;
			case '*':
				kind = TokenKind.STAR;
				break;
			case '/':
				kind = TokenKind.SLASH;
				break;
			case '%':
				kind = TokenKind.PERCENT;
				break;
			default:
				int width = value < 0x80 ? 1 : value < 0xe0 ? 2 : value < 0xf0 ? 3 : 4;
				var span = SourceSpan (source, start, start + width);
				string message = value >= 0x80 ? "non-ASCII character is not supported outside comments" : "unexpected character '%s'".printf (span.text ().escape ());
				diagnostic = new Diagnostic (span, message);
				return null;
			}
		}
		return new Token (kind, SourceSpan (source, start, offset));
	}

	private bool match_equal() {
		if (offset < source.length && source.byte_at (offset) == '=') {
			offset++;
			return true;
		}
		return false;
	}

}
}
