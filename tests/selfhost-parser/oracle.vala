// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
string hex(string text) {
	var result = new StringBuilder();
	foreach (uint8 value in text.data) {
		result.append_printf("%02x", value);
	}
	return result.str;
}
void observe(SourceSet sources) {
	var parsed = SyntaxProgram.parse(sources);
	if (parsed.diagnostic != null) {
		var diagnostic = parsed.diagnostic;
		stdout.printf("ERROR %d %d %s\n%s\nEND\n", diagnostic.span.start, diagnostic.span.end, hex(diagnostic.message), diagnostic.format());
		return;
	}
	stdout.printf("OK\n%sAST\n%sEND\n", SyntaxDump.format_program(parsed.program), new AstOracle().format(parsed.program));
}
int main(string[] args) {
	try {
		if (args.length > 1 && args[1] == "--program") {
			var files = new GenericArray<SourceFile>();
			for (int i = 2; i < args.length; i++) {
				uint8[] bytes;
				FileUtils.get_data(args[i], out bytes);
				files.add(new SourceFile(args[i], (owned)bytes));
			}
			observe(new SourceSet(files));
			return 0;
		}
		bool native_interface = args.length > 1 && args[1] == "--native-interface";
		for (int i = native_interface ? 2 : 1; i < args.length; i++) {
			uint8[] bytes;
			FileUtils.get_data(args[i], out bytes);
			var files = new GenericArray<SourceFile>();
			files.add(new SourceFile("input", (owned)bytes, native_interface));
			observe(new SourceSet(files));
		}
		return 0;
	} catch (Error error) {
		stderr.printf("%s\n", error.message);
		return 2;
	}
}
