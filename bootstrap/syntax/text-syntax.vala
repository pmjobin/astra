// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Text;

namespace Astra.Syntax {
// Compiler-authored only: no expression spelling can create this boundary.
public class Utf8FactoryExpressionSyntax : ExpressionSyntax {
	public bool validates { get; private set; }
	public Token input { get; private set; }
	internal Utf8FactoryExpressionSyntax (SourceSpan span, Token input, bool validates) {
		base (span, 1);
		this.input = input;
		this.validates = validates;
	}
}
internal class Utf8FactorySyntax : Object {
	internal static BlockStatementSyntax body(string namespace_prefix = "") {
		// Ordinary construction, throwing and owned-result syntax exercise the
		// same checker as authored source. Only the two certified operations
		// below are privileged; their template call names have no authority.
		var parsed = Parser.parse (new SourceFile.from_text ("<Utf8MessageFactory>",
			"int generated(){if(valid(bytes)){var message=new " + namespace_prefix +
			"Utf8Message(text(bytes));return move message;}throw new " + namespace_prefix + "InvalidUtf8();}"));
		assert (parsed.diagnostic == null);
		var body = parsed.unit.functions[0].body;
		var branch = (IfStatementSyntax) body.statements[0];
		var input = ((NameExpressionSyntax) ((CallExpressionSyntax) branch.condition).arguments[0]).identifier;
		body.statements[0] = new IfStatementSyntax (branch.keyword, branch.open_paren, new Utf8FactoryExpressionSyntax (branch.condition.span, input, true), branch.close_paren, branch.then_body, null, null);
		var construction = (HeapObjectConstructionSyntax) ((InferredLocalDeclarationSyntax) branch.then_body.statements[0]).initializer;
		construction.arguments[0] = new Utf8FactoryExpressionSyntax (construction.arguments[0].span, input, false);
		return body;
	}
}
public class TextLiteralExpressionSyntax : ExpressionSyntax {
	public Token token { get; private set; }
	public TextBytes payload { get { return token.text_payload; } }
	public TextLiteralExpressionSyntax (Token token) {
		base (token.span, 1);
		this.token = token;
	}
}
// Existing named fields keep their grammar. This bounded postfix permits
// byte_length on a literal, parenthesized expression or native result.
public class TextMemberExpressionSyntax : ExpressionSyntax {
	public ExpressionSyntax receiver { get; private set; }
	public Token member { get; private set; }
	public TextMemberExpressionSyntax (ExpressionSyntax receiver, Token member) {
		base (SourceSpan.cover (receiver.span, member.span), receiver.tree_depth + 1);
		this.receiver = receiver;
		this.member = member;
	}
}
public class TextLiteralDecoder : Object {
	public Diagnostic? diagnostic { get; private set; }
	private bool fail(SourceFile file, int start, int end, string message) {
		diagnostic = new Diagnostic (SourceSpan (file, start, end), message);
		return false;
	}
	private bool append(ByteArray bytes, uint8 value, SourceFile file, int start, int end) {
		if (bytes.len >= int32.MAX) {
			return fail (file, start, end, "string byte length exceeds signed I32 limit");
		}
		bytes.append ({value});
		return true;
	}
	public TextBytes? decode(SourceFile file, int start, ref int offset) {
		var bytes = new ByteArray ();
		while (offset < file.length) {
			uint8 value = file.byte_at (offset++);
			if (value == '"') {
				var result = new TextBytes (bytes.data);
				if (!result.valid ()) {
					fail (file, start, offset, "invalid UTF-8 string payload");
					return null;
				}
				return result;
			}
			if (value == '\n' || value == '\r' || value == 0) {
				fail (file, start, offset, "physical newline or NUL in string literal");
				return null;
			}
			if (value != '\\') {
				if (!append (bytes, value, file, start, offset)) {
					return null;
				}
				continue;
			}
			if (offset == file.length) {
				break;
			}
			uint8 escape = file.byte_at (offset++);
			switch (escape) {
			case '"': value = '"';
				break;
			case '\\': value = '\\';
				break;
			case 'n':
				value = '\n';
				break;
			case 'r':
				value = '\r';
				break;
			case 't':
				value = '\t';
				break;
			case '0':
				value = 0;
				break;
			case 'u':
			case 'U':
				int digits = escape == 'u' ? 4 : 8;
				uint32 scalar = 0;
				for (int n = 0; n < digits; n++) {
					if (offset == file.length) {
						fail (file, start, offset, "incomplete Unicode escape");
						return null;
					}
					uint8 digit = file.byte_at (offset++);
					int hex = -1;
					if (digit >= '0' && digit <= '9') {
						hex = (int) digit - '0';
					} else if (digit >= 'a' && digit <= 'f') {
						hex = (int) digit - 'a' + 10;
					} else if (digit >= 'A' && digit <= 'F') {
						hex = (int) digit - 'A' + 10;
					}
					if (hex < 0) {
						fail (file, offset - 1, offset, "Unicode escape requires exactly hexadecimal digits");
						return null;
					}
					scalar = (scalar << 4) | (uint32) hex;
				}
				if (!TextBytes.scalar (scalar)) {
					fail (file, start, offset, "Unicode escape must denote one Unicode scalar; surrogates and values above U+10FFFF are invalid");
					return null;
				}
				uint8[] encoded;
				if (scalar < 0x80) {
					encoded = {
						(uint8) scalar
					};
				} else if (scalar < 0x800) {
					encoded = {
						(uint8) (0xc0 | (scalar >> 6)), (uint8) (0x80 | (scalar & 63))
					};
				} else if (scalar < 0x10000) {
					encoded = {
						(uint8) (0xe0 | (scalar >> 12)), (uint8) (0x80 | ((scalar >> 6) & 63)), (uint8) (0x80 | (scalar & 63))
					};
				} else {
					encoded = {
						(uint8) (0xf0 | (scalar >> 18)), (uint8) (0x80 | ((scalar >> 12) & 63)), (uint8) (0x80 | ((scalar >> 6) & 63)), (uint8) (0x80 | (scalar & 63))
					};
				}
				foreach (uint8 byte in encoded) {
					if (!append (bytes, byte, file, start, offset)) {
						return null;
					}
				}
				continue;
			default:
				fail (file, offset - 2, offset, "unknown string escape");
				return null;
			}
			if (!append (bytes, value, file, start, offset)) {
				return null;
			}
		}
		fail (file, start, offset, "unterminated string literal");
		return null;
	}
}
}
