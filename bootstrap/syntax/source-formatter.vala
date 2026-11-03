// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Syntax {
// Edits are selected by the actual parser. No brace counting or pattern
// substitution establishes declaration or control-body authority.
internal class SourceFormatEdit : Object {
	public int start;
	public int end;
	public string replacement;
	public SourceFormatEdit (int start, int end, string replacement) {
		this.start = start;
		this.end = end;
		this.replacement = replacement;
	}

}

public class SourceFormatter : Object {
	public const int VERSION = 2;

	private static bool simple(StatementSyntax statement) {
		return statement is ReturnStatementSyntax || statement is BreakStatementSyntax || statement is ContinueStatementSyntax || statement is AssignmentStatementSyntax || statement is FieldAssignmentStatementSyntax || statement is IndexedAssignmentSyntax || statement is DereferenceAssignmentSyntax || statement is CallStatementSyntax;
	}

	private static bool single_line(SourceFile source, int start, int end) {
		for (int i = start; i < end; i++) {
			if (source.byte_at (i) == '\r' || source.byte_at (i) == '\n')
				return false;
		}
		return true;
	}

	private static void expand(SourceFile source, BlockStatementSyntax body, GenericArray<CommentTrivia> comments, GenericArray<SourceFormatEdit> edits) {
		if (body.open_brace.span.start == body.open_brace.span.end || body.statements.length == 0 || !single_line (source, body.span.start, body.span.end))
			return;
		foreach (var comment in comments) {
			if (comment.span.start < body.span.end && comment.span.end > body.span.start)
				return;
		}
		int start = body.open_brace.span.end;
		foreach (var statement in body.statements) {
			edits.add (new SourceFormatEdit (start, statement.span.start, "\n"));
			start = statement.span.end;
		}
		edits.add (new SourceFormatEdit (start, body.close_brace.span.start, "\n"));
	}

	private static void compact(SourceFile source, StatementSyntax control, BlockStatementSyntax body, GenericArray<CommentTrivia> comments, GenericArray<SourceFormatEdit> edits, HashTable<int, bool> removed) {
		if (body.open_brace.span.start == body.open_brace.span.end)
			return;
		if (body.statements.length != 1 || !simple (body.statements[0]) || !single_line (source, control.span.start, body.span.end)) {
			expand (source, body, comments, edits);
			return;
		}
		foreach (var comment in comments) {
			if (comment.span.start < body.span.end && comment.span.end > control.span.start)
				return;
		}
		var statement = body.statements[0];
		int before = body.open_brace.span.start - 1;
		string gap = before >= 0 && (source.byte_at (before) == ' ' || source.byte_at (before) == '\t') ? "" : " ";
		edits.add (new SourceFormatEdit (body.open_brace.span.start, statement.span.start, gap));
		edits.add (new SourceFormatEdit (statement.span.end, body.close_brace.span.end, ""));
		removed.insert (body.open_brace.span.start, true);
		removed.insert (body.close_brace.span.start, true);
	}

	private static void walk(SourceFile source, BlockStatementSyntax body, GenericArray<CommentTrivia> comments, GenericArray<SourceFormatEdit> edits, HashTable<int, bool> removed) {
		foreach (var statement in body.statements) {
			if (statement is IfStatementSyntax) {
				var branch = (IfStatementSyntax) statement;
				// Keep every explicit else boundary attached and braced.
				if (branch.else_body == null)
					compact (source, branch, branch.then_body, comments, edits, removed);
				else {
					expand (source, branch.then_body, comments, edits);
					expand (source, branch.else_body, comments, edits);
				}
				walk (source, branch.then_body, comments, edits, removed);
				if (branch.else_body != null)
					walk (source, branch.else_body, comments, edits, removed);
			} else if (statement is WhileStatementSyntax) {
				var loop = (WhileStatementSyntax) statement;
				compact (source, loop, loop.body, comments, edits, removed);
				walk (source, loop.body, comments, edits, removed);
			} else if (statement is ForStatementSyntax) {
				var loop = (ForStatementSyntax) statement;
				compact (source, loop, loop.body, comments, edits, removed);
				walk (source, loop.body, comments, edits, removed);
			} else if (statement is BlockStatementSyntax) {
				walk (source, (BlockStatementSyntax) statement, comments, edits, removed);
			} else if (statement is ForeachStatementSyntax) {
				walk (source, ((ForeachStatementSyntax) statement).body, comments, edits, removed);
			} else if (statement is WithStatementSyntax) {
				walk (source, ((WithStatementSyntax) statement).body, comments, edits, removed);
			} else if (statement is TryStatementSyntax) {
				var attempt = (TryStatementSyntax) statement;
				walk (source, attempt.body, comments, edits, removed);
				foreach (var handler in attempt.catches)
					walk (source, handler.body, comments, edits, removed);
			} else if (statement is MatchStatementSyntax) {
				foreach (var arm in ((MatchStatementSyntax) statement).arms)
					walk (source, arm.body, comments, edits, removed);
			}
		}
	}

	private static void separate(SourceFile source, SyntaxNode previous, SyntaxNode next, GenericArray<SourceFormatEdit> edits) {
		if (previous.span.end > next.span.start)
			return;
		int start = previous.span.end, end = start;
		while (end < next.span.start && (source.byte_at (end) == ' ' || source.byte_at (end) == '\t' || source.byte_at (end) == '\n' || source.byte_at (end) == '\r'))
			end++;
		// A line comment after the closing brace belongs to that line. Retain
		// its attachment, and insert separation after its newline instead.
		if (end + 1 < next.span.start && source.byte_at (end) == '/' && source.byte_at (end + 1) == '/' && single_line (source, start, end)) {
			while (end < next.span.start && source.byte_at (end) != '\n')
				end++;
			if (end == next.span.start)
				return;
			start = end++;
			while (end < next.span.start && (source.byte_at (end) == ' ' || source.byte_at (end) == '\t' || source.byte_at (end) == '\n' || source.byte_at (end) == '\r'))
				end++;
		}
		edits.add (new SourceFormatEdit (start, end, "\n\n"));
	}

	private static bool authored(SyntaxNode node) {
		if (!(node is FunctionDeclarationSyntax))
			return true;
		var function = (FunctionDeclarationSyntax) node;
		// Interfaces synthesize a default constructor and dummy method bodies.
		// Generated names/bodies have no source declaration boundary to edit.
		return function.name.spelling () == function.name.span.text () || (function.body != null && function.body.open_brace.span.text () == "{" && function.body.close_brace.span.text () == "}");
	}

	private static string? structure(SourceFile source, CompilationUnitSyntax unit, GenericArray<Token> tokens, GenericArray<CommentTrivia> comments, out Diagnostic? diagnostic) {
		var edits = new GenericArray<SourceFormatEdit> ();
		var removed = new HashTable<int, bool> (direct_hash, direct_equal);
		var declarations = new GenericArray<SyntaxNode> ();
		foreach (var value in unit.constants)
			declarations.add (value);
		foreach (var value in unit.enums)
			declarations.add (value);
		foreach (var value in unit.functions) {
			if (!authored (value))
				continue;
			declarations.add (value);
			if (value.body != null)
				walk (source, value.body, comments, edits, removed);
		}
		foreach (var value in unit.native_instances ()) {
			declarations.add (value);
			SyntaxNode? previous = null;
			foreach (var member in value.members) {
				if (!authored (member))
					continue;
				if (previous != null && (previous is FunctionDeclarationSyntax || member is FunctionDeclarationSyntax || previous is PropertyDeclarationSyntax || member is PropertyDeclarationSyntax))
					separate (source, previous, member, edits);
				if (member is FunctionDeclarationSyntax && ((FunctionDeclarationSyntax) member).body != null)
					walk (source, ((FunctionDeclarationSyntax) member).body, comments, edits, removed);
				if (member is PropertyDeclarationSyntax) {
					var property = (PropertyDeclarationSyntax) member;
					walk (source, property.getter.body, comments, edits, removed);
					if (property.setter != null)
						walk (source, property.setter.body, comments, edits, removed);
				}
				previous = member;
			}
		}
		var ordered_declarations = new GLib.List<SyntaxNode> ();
		foreach (var declaration in declarations)
			ordered_declarations.append (declaration);
		ordered_declarations.sort ((a, b) => a.span.start - b.span.start);
		declarations = new GenericArray<SyntaxNode> ();
		foreach (var declaration in ordered_declarations)
			declarations.add (declaration);
		for (int i = 1; i < declarations.length; i++) {
			var previous = declarations[i - 1];
			if (!(previous is ConstantDeclarationSyntax))
				separate (source, previous, declarations[i], edits);
		}
		var ordered_edits = new GLib.List<SourceFormatEdit> ();
		foreach (var edit in edits)
			ordered_edits.append (edit);
		ordered_edits.sort ((a, b) => a.start - b.start);
		var output = new StringBuilder ();
		int offset = 0;
		foreach (var edit in ordered_edits) {
			if (edit.start < offset) {
				diagnostic = new Diagnostic (SourceSpan (source, edit.start, edit.end), "overlapping syntax-aware formatter edits");
				return null;
			}
			output.append (source.slice (offset, edit.start));
			output.append (edit.replacement);
			offset = edit.end;
		}
		output.append (source.slice (offset, source.length));
		var after_source = new SourceFile.from_text (source.path, output.str);
		var after_parse = Parser.parse (after_source);
		diagnostic = after_parse.diagnostic;
		if (diagnostic != null)
			return null;
		GenericArray<CommentTrivia> after_comments;
		var after = tokenize (after_source, out after_comments, out diagnostic);
		if (after == null)
			return null;
		bool same = comments.length == after_comments.length && SyntaxDump.format (unit) == SyntaxDump.format (after_parse.unit);
		int index = 0;
		foreach (var token in tokens) {
			if (removed.contains (token.span.start))
				continue;
			if (index >= after.length || token.kind != after[index].kind || token.spelling () != after[index].spelling ()) {
				same = false;
				break;
			}
			index++;
		}
		same = same && index == after.length;
		for (int i = 0; same && i < comments.length; i++)
			same = comments[i].span.text () == after_comments[i].span.text ();
		if (!same) {
			diagnostic = new Diagnostic (SourceSpan (source, 0, 0), "formatter changed normalized AST or unapproved tokens/comments");
			return null;
		}
		return output.str;
	}

	public static string? format(SourceFile source, out Diagnostic? diagnostic) {
		var parsed = Parser.parse (source);
		diagnostic = parsed.diagnostic;
		if (diagnostic != null)
			return null;
		GenericArray<CommentTrivia> comments;
		var tokens = tokenize (source, out comments, out diagnostic);
		if (tokens == null)
			return null;
		var text = structure (source, parsed.unit, tokens, comments, out diagnostic);
		if (text == null)
			return null;
		return indent (new SourceFile.from_text (source.path, text), out diagnostic);
	}

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

	private static string? indent(SourceFile source, out Diagnostic? diagnostic) {
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
