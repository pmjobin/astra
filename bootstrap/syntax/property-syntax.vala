// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class PropertyDeclarationSyntax : SyntaxNode {
	public Token? owned_keyword { get; internal set; }
	public FunctionDeclarationSyntax? factory_syntax { get; internal set; }
	public bool is_borrowed { get; internal set; }
	public Token? lazy_keyword { get; internal set; }
	public bool is_lazy { get { return lazy_keyword != null; } }
	public TypeNameSyntax? throws_class { get; internal set; }
	public MemberDispatchSyntax dispatch { get; internal set; default = MemberDispatchSyntax.DIRECT; }
	public Token keyword { get; private set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	public PropertyAccessorSyntax getter { get; private set; }
	public PropertyAccessorSyntax? setter { get; private set; }

	public PropertyDeclarationSyntax (Token keyword, TypeNameSyntax type_name, Token name, PropertyAccessorSyntax getter, PropertyAccessorSyntax? setter, Token close) {
		base (SourceSpan.cover (keyword.span, close.span));
		this.keyword = keyword;
		this.type_name = type_name;
		this.name = name;
		this.getter = getter;
		this.setter = setter;
	}

}

public class PropertyAccessorSyntax : SyntaxNode {
	public Token keyword { get; private set; }
	public ParameterSyntax? parameter { get; private set; }
	public BlockStatementSyntax body { get; private set; }

	public PropertyAccessorSyntax (Token keyword, ParameterSyntax? parameter, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.keyword = keyword;
		this.parameter = parameter;
		this.body = body;
	}

}
}
