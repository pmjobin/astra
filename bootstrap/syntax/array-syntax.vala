// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
// Expected element type comes from the containing declaration. This node is
// only an array entry; it does not admit a general struct expression.
public class ArrayStructInitializerSyntax : ExpressionSyntax {
	public StructInitializerSyntax initializer { get; private set; }
	public ArrayStructInitializerSyntax (StructInitializerSyntax initializer) {
		base (initializer.span, 1);
		this.initializer = initializer;
	}

}

public class ArrayTypeSyntax : TypeNameSyntax {
	public TypeNameSyntax element_type { get; private set; }
	public ExpressionSyntax extent { get; private set; }

	public ArrayTypeSyntax (TypeNameSyntax element_type, Token length, Token close) {
		base.shaped (SourceSpan.cover (element_type.span, close.span), element_type.identifier);
		this.element_type = element_type;
		this.extent = new IntegerLiteralExpressionSyntax (length);
	}

	public ArrayTypeSyntax.expression (TypeNameSyntax element_type, ExpressionSyntax extent, Token close) {
		base.shaped (SourceSpan.cover (element_type.span, close.span), element_type.identifier);
		this.element_type = element_type;
		this.extent = extent;
	}

	public override string spelling() {
		return element_type.spelling () + "[" + extent.span.text () + "]";
	}

}

// Declaration-only positional syntax; it never becomes an array Value.
public class ArrayInitializerSyntax : ExpressionSyntax {
	public GenericArray<ExpressionSyntax> elements { get; private set; }

	public ArrayInitializerSyntax (VectorInitializerSyntax positional) {
		base (positional.span, positional.tree_depth);
		this.elements = positional.lanes;
	}

}

// Brackets are syntax only. Checking selects array Place or vector Value.
public class IndexExpressionSyntax : ExpressionSyntax {
	public ExpressionSyntax container { get; private set; }
	public ExpressionSyntax subscript { get; private set; }
	public Token close { get; private set; }

	public IndexExpressionSyntax (ExpressionSyntax container, ExpressionSyntax subscript, Token close) {
		base (SourceSpan.cover (container.span, close.span), int.max (container.tree_depth, subscript.tree_depth) + 1);
		this.container = container;
		this.subscript = subscript;
		this.close = close;
	}

}

public class IndexedAssignmentSyntax : StatementSyntax {
	public IndexExpressionSyntax target { get; private set; }
	public ExpressionSyntax expression { get; private set; }

	public IndexedAssignmentSyntax (IndexExpressionSyntax target, ExpressionSyntax expression, Token? semicolon) {
		base (SourceSpan.cover (target.span, semicolon == null ? expression.span : semicolon.span));
		this.target = target;
		this.expression = expression;
	}

}
}
