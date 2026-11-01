// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
string hex(string text) {
	var result = new StringBuilder();
	foreach (uint8 b in text.data) {
		result.append_printf("%02x", b);
	}
	return result.str;
}
void dump(Lexer lexer) {
	while (true) {
		var token = lexer.next_token();
		if (token == null) {
			break;
		}
		stdout.printf("%s %d %d %s %s \n", token.kind.to_string().substring("ASTRA_SYNTAX_TOKEN_KIND_".length), token.span.start, token.span.end, hex(token.spelling()), token.text_payload == null ? "" : token.text_payload.hex());
		if (token.kind == TokenKind.EOF) {
			assert(lexer.next_token().kind == TokenKind.EOF);
			break;
		}
	}
	if (lexer.diagnostic != null) {
		var d = lexer.diagnostic;
		stdout.printf("ERROR %d %d %s \n", d.span.start, d.span.end, hex(d.message));
		assert(lexer.next_token() == null);
	}
	foreach (var comment in lexer.comments) {
		stdout.printf("COMMENT %d %d \n", comment.span.start, comment.span.end);
	}
}
int main(string[] args) {
	try {
		for (int i = 1; i < args.length; i++) {
			uint8[] bytes;
			FileUtils.get_data(args[i], out bytes);
			var source = new SourceFile("input", (owned) bytes);
			dump(new Lexer(source));
			stdout.printf("END\n");
			var original = new Lexer(source);
			original.next_token();
			var fork = original.fork();
			assert(fork.comments.length == 0);
			dump(fork);
			stdout.printf("FORK\n");
		}
		return 0;
	} catch (Error e) {
		stderr.printf("%s\n", e.message);
		return 1;
	}
}
