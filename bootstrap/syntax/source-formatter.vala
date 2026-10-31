// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Syntax {
// Version 1 deliberately preserves intra-line layout and line count. Only
// leading layout outside literals/comments is normalized to hard TABs.
public class SourceFormatter : Object {
	public const int VERSION = 1;

	private static GenericArray<Token>? tokenize(SourceFile source, out GenericArray<CommentTrivia> comments, out Diagnostic? diagnostic) {
		var lexer = new Lexer (source);
		var tokens = new GenericArray<Token> ();
		while (true) {
			var token = lexer.next_token ();
			if (token == null) {
				comments = lexer.comments;
				diagnostic = lexer.diagnostic;
				return null;
			}
			if (token.kind == TokenKind.EOF) {
				break;
			}
			tokens.add (token);
		}
		comments = lexer.comments;
		diagnostic = null;
		return tokens;
	}

	private static bool protected_start(int start, GenericArray<Token> tokens, int token_index, GenericArray<CommentTrivia> comments, ref int comment_index) {
		if (token_index > 0 && tokens[token_index - 1].span.end > start) {
			return true;
		}
		while (comment_index < comments.length && comments[comment_index].span.end <= start) {
			comment_index++;
		}
		return comment_index < comments.length && comments[comment_index].span.start < start;
	}

	public static string? format(SourceFile source, out Diagnostic? diagnostic) {
		var parsed = Parser.parse (source);
		diagnostic = parsed.diagnostic;
		if (diagnostic != null) {
			return null;
		}
		GenericArray<CommentTrivia> comments;
		var tokens = tokenize (source, out comments, out diagnostic);
		if (tokens == null) {
			return null;
		}
		var output = new StringBuilder ();
		int start = 0, token_index = 0, comment_index = 0;
		int braces = 0, parens = 0, brackets = 0;
		while (start < source.length) {
			int end = start;
			while (end < source.length && source.byte_at (end) != '\n' && source.byte_at (end) != '\r') {
				end++;
			}
			int next = end;
			if (next < source.length) {
				if (source.byte_at (next++) == '\r' && next < source.length && source.byte_at (next) == '\n') {
					next++;
				}
			}
			int content = start;
			while (content < end && (source.byte_at (content) == ' ' || source.byte_at (content) == '\t')) {
				content++;
			}
			bool preserve = protected_start (start, tokens, token_index, comments, ref comment_index);
			if (preserve) {
				output.append (source.slice (start, end));
			} else if (content < end) {
				int indentation = braces;
				var first = token_index < tokens.length && tokens[token_index].span.start == content ? tokens[token_index] : null;
				if (first != null && first.kind == TokenKind.CLOSE_BRACE) {
					indentation--;
				}
				if ((parens > 0 || brackets > 0) && (first == null || (first.kind != TokenKind.CLOSE_PAREN && first.kind != TokenKind.CLOSE_BRACKET))) {
					indentation++;
				}
				output.append (string.nfill (int.max (0, indentation), '\t'));
				output.append (source.slice (content, end));
			}
			output.append (next == end ? "\n" : source.slice (end, next));
			while (token_index < tokens.length && tokens[token_index].span.start < end) {
				switch (tokens[token_index++].kind) {
				case TokenKind.OPEN_BRACE: braces++;
					break;
				case TokenKind.CLOSE_BRACE: braces--;
					break;
				case TokenKind.OPEN_PAREN: parens++;
					break;
				case TokenKind.CLOSE_PAREN:
					parens--;
					break;
				case TokenKind.OPEN_BRACKET:
					brackets++;
					break;
				case TokenKind.CLOSE_BRACKET:
					brackets--;
					break;
				default:
					break;
				}
			}
			start = next;
		}
		// A separate lex/parse pass proves exact tokens and comments survived.
		// The original parser remains the only grammar and span authority.
		var formatted = new SourceFile.from_text (source.path, output.str);
		GenericArray<CommentTrivia> after_comments;
		var after = tokenize (formatted, out after_comments, out diagnostic);
		bool same = after != null && tokens.length == after.length && comments.length == after_comments.length;
		if (same) {
			for (int i = 0; i < tokens.length; i++) {
				if (tokens[i].kind != after[i].kind || tokens[i].spelling () != after[i].spelling ()) {
					same = false;
					break;
				}
			}
		}
		if (same) {
			for (int i = 0; i < comments.length; i++) {
				if (comments[i].span.text () != after_comments[i].span.text ()) {
					same = false;
					break;
				}
			}
		}
		if (!same) {
			diagnostic = new Diagnostic (SourceSpan (source, 0, 0), "formatter could not preserve exact source tokens/comments");
			return null;
		}
		diagnostic = Parser.parse (formatted).diagnostic;
		return diagnostic == null ? output.str : null;
	}
}
}
