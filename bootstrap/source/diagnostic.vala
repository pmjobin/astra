// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public class Diagnostic : Object {
	public SourceSpan span { get; private set; }
	public string message { get { return description; } }
	private string description;

	public Diagnostic (SourceSpan span, string message) {
		this.span = span;
		this.description = message;
	}

	public string format() {
		int line;
		int column;
		span.file.locate (span.start, out line, out column);
		return "%s:%d:%d: error: %s".printf (span.file.path, line, column, message);
	}
}
}
