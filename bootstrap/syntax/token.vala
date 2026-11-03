// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public enum TokenKind {
	EOF,
	IDENTIFIER,
	SLICE,
	LEN,
	ALL,
	ANY,
	AS,
	DOT_WRAP,
	MAC_WRAP,
	DOT_F32,
	MAC_F32,
	SAT_ADD,
	SAT_SUB,
	WIDEN_LOW,
	WIDEN_HIGH,
	PACK_WRAP,
	PACK_SAT,
	INTERLEAVE_LOW,
	INTERLEAVE_HIGH,
	SPLAT,
	INSERT,
	SHUFFLE,
	SELECT,
	BORROWED,
	INTEGER,
	FLOAT,
	TEXT,
	ENUM,
	MATCH,
	CASE,
	STRUCT,
	CLASS,
	THIS,
	OWNED,
	VAR,
	CONST,
	MOVE,
	RELEASE,
	SWAP,
	DOT,
	EXTERN,
	EXPORT,
	RETURN,
	ASYNC,
	AWAIT,
	THROWS,
	THROW,
	TRY,
	CATCH,
	TRUE,
	FALSE,
	NULL,
	IF,
	ELSE,
	WHILE,
	FOR,
	FOREACH,
	WITH,
	NONNULL,
	BREAK,
	CONTINUE,
	OPEN_PAREN,
	CLOSE_PAREN,
	OPEN_BRACKET,
	CLOSE_BRACKET,
	OPEN_BRACE,
	CLOSE_BRACE,
	COMMA,
	COLON,
	SEMICOLON,
	EQUAL,
	EQUAL_EQUAL,
	BANG,
	BANG_EQUAL,
	AMPERSAND,
	PIPE,
	CARET,
	TILDE,
	SHIFT_LEFT,
	SHIFT_RIGHT,
	ARROW,
	AMPERSAND_AMPERSAND,
	PIPE_PIPE,
	LESS,
	LESS_EQUAL,
	GREATER,
	GREATER_EQUAL,
	PLUS,
	MINUS,
	STAR,
	SLASH,
	PERCENT
}

public class Token : Object {
	private string? generated_spelling;
	public Astra.Text.TextBytes? text_payload { get; internal set; }
	public TokenKind kind { get; private set; }
	public SourceSpan span { get; private set; }

	public Token (TokenKind kind, SourceSpan span) {
		this.kind = kind;
		this.span = span;
	}

	// Compiler-created names retain the user's source location for diagnostics.
	internal Token.generated (TokenKind kind, SourceSpan span, string spelling) {
		this.kind = kind;
		this.span = span;
		this.generated_spelling = spelling;
	}

	public string spelling() {
		return generated_spelling ?? span.text ();
	}

}
}
