// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class EnumPayloadSyntax : SyntaxNode {
	public Token? owned_keyword { get; internal set; }
	public TypeNameSyntax type_name { get; private set; }
	public Token name { get; private set; }
	internal EnumPayloadSyntax (TypeNameSyntax type_name, Token name) {
		base (SourceSpan.cover (type_name.span, name.span));
		this.type_name = type_name;
		this.name = name;
	}
}

public class EnumVariantSyntax : SyntaxNode {
	public Token name { get; private set; }
	public GenericArray<EnumPayloadSyntax> fields { get; private set; }
	internal EnumVariantSyntax (Token name, GenericArray<EnumPayloadSyntax> fields, SourceSpan end) {
		base (SourceSpan.cover (name.span, end));
		this.name = name;
		this.fields = fields;
	}
}

public class EnumDeclarationSyntax : SyntaxNode {
	public GenericArray<Token> type_parameters { get; internal set; default = new GenericArray<Token> (); }
	public Token name { get; private set; }
	public GenericArray<EnumVariantSyntax> variants { get; private set; }
	internal EnumDeclarationSyntax (Token keyword, Token name, GenericArray<EnumVariantSyntax> variants, Token close) {
		base (SourceSpan.cover (keyword.span, close.span));
		this.name = name;
		this.variants = variants;
	}
}

public class EnumBindingSyntax : SyntaxNode {
	public Token? field { get; private set; }
	public Token binding { get; private set; }
	internal EnumBindingSyntax (Token binding, Token? field = null) {
		base (SourceSpan.cover (field == null ? binding.span : field.span, binding.span));
		this.field = field;
		this.binding = binding;
	}
}

public class EnumArmSyntax : SyntaxNode {
	public GenericArray<TypeNameSyntax> type_arguments { get; internal set; default = new GenericArray<TypeNameSyntax> (); }
	public Token? qualifier { get; private set; }
	public Token? variant { get; private set; }
	public GenericArray<EnumBindingSyntax> bindings { get; private set; }
	public BlockStatementSyntax body { get; private set; }
	internal EnumArmSyntax (Token keyword, Token? qualifier, Token? variant, GenericArray<EnumBindingSyntax> bindings, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.qualifier = qualifier;
		this.variant = variant;
		this.bindings = bindings;
		this.body = body;
	}
}

public class MatchStatementSyntax : StatementSyntax {
	public ExpressionSyntax scrutinee { get; private set; }
	public GenericArray<EnumArmSyntax> arms { get; private set; }
	internal MatchStatementSyntax (Token keyword, ExpressionSyntax scrutinee, GenericArray<EnumArmSyntax> arms, Token close) {
		base (SourceSpan.cover (keyword.span, close.span));
		this.scrutinee = scrutinee;
		this.arms = arms;
	}
}
}
