// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Built against the unchanged Vala source component. No Astra implementation here.
int main(string[] args) {
	if (args.length == 2 && (args[1] == "--cross-source-cover" || args[1] == "--reversed-cover")) {
		var source = new Astra.Source.SourceFile.from_text("same.astra", "abc");
		var other = new Astra.Source.SourceFile.from_text("same.astra", "abc");
		var first = Astra.Source.SourceSpan(source, 2, 3);
		var last = Astra.Source.SourceSpan(args[1] == "--cross-source-cover" ? other : source, 0, 1);
		Astra.Source.SourceSpan.cover(first, last);
		return 77;
	}
	if (args.length >= 2 && args[1] == "--paths") {
		try {
			foreach (var path in Astra.Source.SourceSet.canonical_paths(args[2:args.length])) {
				stdout.printf("%s\n", path);
			}
		} catch (Astra.Source.SourceSetError error) {
			stdout.printf("DUPLICATE\n");
		}
		return 0;
	}
	if (args.length == 2 && args[1] == "--spans") {
		var source = new Astra.Source.SourceFile.from_text("./same//file.astra", "a\r\nbc");
		var duplicate = new Astra.Source.SourceFile.from_text("./same//file.astra", "a\r\nbc");
		var alias = source;
		assert(source == alias && source != duplicate);
		var first = Astra.Source.SourceSpan(source, 0, 1);
		var last = Astra.Source.SourceSpan(alias, 3, 5);
		var covered = Astra.Source.SourceSpan.cover(first, last);
		assert(covered.start == 0 && covered.end == 5 && covered.text() == "a\r\nbc");
		assert(covered.file == source && covered.file.path == "same/file.astra");
		stdout.printf("SPAN_OK\n");
		return 0;
	}
	try {
		uint8[] bytes;
		FileUtils.get_data(args[1], out bytes);
		var source = new Astra.Source.SourceFile(args[2], (owned) bytes);
		var diagnostic = source.validate_encoding();
		int error = diagnostic == null ? -1 : diagnostic.span.start;
		stdout.printf("%s\n%d %d \n%s\n", source.path, source.length, error,
			diagnostic == null ? "" : diagnostic.message);
		for (int i = 0; i <= source.length; i++) {
			int line;
			int column;
			source.locate(i, out line, out column);
			stdout.printf("%d %d \n", line, column);
		}
		for (int i = 0; i < source.length; i++) {
			stdout.printf("%d ", source.byte_at(i));
		}
		stdout.printf("\n");
		var span = Astra.Source.SourceSpan(source, error < 0 ? source.length : error,
			error < 0 ? source.length : error + 1);
		stdout.printf("%s\n", new Astra.Source.Diagnostic(span, "example").format());
		return 0;
	} catch (Error error) {
		stderr.printf("%s\n", error.message);
		return 1;
	}
}
