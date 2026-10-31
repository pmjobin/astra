// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Vapi {
public enum VapiTokenKind {
	EOF,
	IDENTIFIER,
	BORROWED,
	OWNED,
	HANDLE,
	STRING,
	OPEN_BRACKET,
	CLOSE_BRACKET,
	EQUAL,
	OPEN_PAREN,
	CLOSE_PAREN,
	COMMA,
	STAR,
	SEMICOLON
}

public class VapiToken : Object {
	public VapiTokenKind kind { get; private set; }
	public SourceSpan span { get; private set; }
	private string? decoded_string;
	public string? string_value { get { return decoded_string; } }

	internal VapiToken (VapiTokenKind kind, SourceSpan span, string? string_value = null) {
		this.kind = kind;
		this.span = span;
		this.decoded_string = string_value;
	}

	public string spelling() {
		return span.text ();
	}
}
}
