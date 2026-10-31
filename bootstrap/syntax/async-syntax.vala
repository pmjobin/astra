// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class AsyncRuntimeSyntax : SyntaxNode {
	public Token? provider { get; private set; }
	public Token name { get; private set; }
	public TypeNameSyntax error { get; private set; }
	public TypeNameSyntax status { get; private set; }
	internal AsyncRuntimeSyntax (Token keyword, Token name, TypeNameSyntax error, TypeNameSyntax status, Token end, Token? provider = null) {
		base (SourceSpan.cover (keyword.span, end.span));
		this.provider = provider;
		this.name = name;
		this.error = error;
		this.status = status;
	}
}
public class AwaitExpressionSyntax : ExpressionSyntax {
	public Token keyword { get; private set; }
	public ExpressionSyntax operation { get; private set; }
	internal AwaitExpressionSyntax (Token keyword, ExpressionSyntax operation) {
		base (SourceSpan.cover (keyword.span, operation.span), operation.tree_depth + 1);
		this.keyword = keyword;
		this.operation = operation;
	}
}

public class AwaitStatementSyntax : StatementSyntax {
	public AwaitExpressionSyntax expression { get; private set; }
	internal AwaitStatementSyntax (AwaitExpressionSyntax expression, Token end) {
		base (SourceSpan.cover (expression.span, end.span));
		this.expression = expression;
	}
}
}
