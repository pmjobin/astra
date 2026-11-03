// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public enum MemberDispatchSyntax {
	DIRECT, VIRTUAL, OVERRIDE
}

public class HeapObjectConstructionSyntax : ExpressionSyntax {
	public ExpressionSyntax? allocation_context { get; private set; }
	public bool fallible { get; private set; }
	private static int arguments_depth(GenericArray<ExpressionSyntax> arguments) {
		int depth = 0;
		foreach (var argument in arguments) {
			depth = int.max (depth, argument.tree_depth);
		}
		return depth + 1;
	}

	public TypeNameSyntax class_name { get; private set; }
	public GenericArray<ExpressionSyntax> arguments { get; private set; }
	internal HeapObjectConstructionSyntax (Token keyword, TypeNameSyntax class_name, GenericArray<ExpressionSyntax> arguments, Token close, ExpressionSyntax? allocation_context = null) {
		base (SourceSpan.cover (keyword.span, close.span), int.max (arguments_depth (arguments), allocation_context == null ? 0 : allocation_context.tree_depth + 1));
		this.allocation_context = allocation_context;
		this.class_name = class_name;
		this.arguments = arguments;
		this.fallible = keyword.spelling () == "try_new";
	}

}

public class ThrowStatementSyntax : StatementSyntax {
	public ExpressionSyntax? expression { get; private set; }
	public bool is_rethrow { get { return expression == null; } }
	internal ThrowStatementSyntax (Token keyword, ExpressionSyntax? expression, Token end) {
		base (SourceSpan.cover (keyword.span, end.span));
		this.expression = expression;
	}

}

public class CatchClauseSyntax : SyntaxNode {
	public TypeNameSyntax class_name { get; private set; }
	public Token binding { get; private set; }
	public BlockStatementSyntax body { get; private set; }
	internal CatchClauseSyntax (Token keyword, TypeNameSyntax class_name, Token binding, BlockStatementSyntax body) {
		base (SourceSpan.cover (keyword.span, body.span));
		this.class_name = class_name;
		this.binding = binding;
		this.body = body;
	}

}

public class TryStatementSyntax : StatementSyntax {
	public BlockStatementSyntax body { get; private set; }
	public GenericArray<CatchClauseSyntax> catches { get; private set; }
	internal TryStatementSyntax (Token keyword, BlockStatementSyntax body, GenericArray<CatchClauseSyntax> catches) {
		base (SourceSpan.cover (keyword.span, catches[catches.length - 1].span));
		this.body = body;
		this.catches = catches;
	}

}
}
