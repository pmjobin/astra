// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Source {
public struct SourceSpan {
	public SourceFile file { get; private set; }
	public int start { get; private set; }
	public int end { get; private set; }

	public SourceSpan (SourceFile file, int start, int end) {
		assert (start >= 0 && start <= end && end <= file.length);
		this.file = file;
		this.start = start;
		this.end = end;
	}

	public static SourceSpan cover(SourceSpan first, SourceSpan last) {
		assert (first.file == last.file && first.start <= last.end);
		return SourceSpan (first.file, first.start, last.end);
	}

	public string text() {
		return file.slice (start, end);
	}
}
}
