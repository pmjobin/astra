// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class SwapStatementSyntax : StatementSyntax {
	public ExpressionSyntax left { get; private set; }
	public ExpressionSyntax right { get; private set; }
	public SwapStatementSyntax (Token keyword, ExpressionSyntax left, ExpressionSyntax right, Token semicolon) {
		base (SourceSpan.cover (keyword.span, semicolon.span));
		this.left = left;
		this.right = right;
	}

}

public class BufferAllocationSyntax : ExpressionSyntax {
	public ExpressionSyntax? allocation_context { get; private set; }
	public TypeNameSyntax element_type { get; private set; }
	public ExpressionSyntax count { get; private set; }
	public ExpressionSyntax? failure_call { get; private set; }
	public BufferAllocationSyntax (Token keyword, TypeNameSyntax element_type, ExpressionSyntax count, Token close, ExpressionSyntax? failure_call = null, ExpressionSyntax? allocation_context = null) {
		base (SourceSpan.cover (keyword.span, failure_call == null ? close.span : failure_call.span), int.max (allocation_context == null ? 0 : allocation_context.tree_depth, int.max (count.tree_depth, failure_call == null ? 0 : failure_call.tree_depth)) + 1);
		this.element_type = element_type;
		this.count = count;
		this.failure_call = failure_call;
		this.allocation_context = allocation_context;
	}

}
}

namespace Astra.Syntax {
public class OwnerSlotsTypeSyntax : TypeNameSyntax {
	public TypeNameSyntax element { get; private set; }
	public Token marker { get; private set; }
	public Token close { get; private set; }
	public OwnerSlotsTypeSyntax (TypeNameSyntax element, Token marker, Token close) {
		base.shaped (SourceSpan.cover (element.span, close.span), element.identifier);
		this.element = element;
		this.marker = marker;
		this.close = close;
	}

	public override string spelling() {
		return element.spelling () + "[slots]";
	}

}
}
