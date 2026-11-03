// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
// Native parameter syntax only; CCode and VAPI keep their own grammars.
public class CallerInformationSyntax : SyntaxNode {
	public Token name { get; private set; }
	public Token? target { get; private set; }
	public CallerInformationSyntax (SourceSpan span, Token name, Token? target = null) {
		base (span);
		this.name = name;
		this.target = target;
	}

}
}
