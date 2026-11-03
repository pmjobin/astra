// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
// Shared declaration grammar; only the containing unit/block determines scope.
public class ConstantDeclarationSyntax : StatementSyntax {
	public TypeNameSyntax? type_name { get; private set; }
	public Token name { get; private set; }
	public ExpressionSyntax initializer { get; private set; }

	public ConstantDeclarationSyntax (Token keyword, TypeNameSyntax? type_name, Token name, ExpressionSyntax initializer, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.type_name = type_name;
		this.name = name;
		this.initializer = initializer;
	}

}
}
