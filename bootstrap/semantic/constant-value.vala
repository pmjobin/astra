// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;

namespace Astra.Semantic {
public class ConstantValue : Object {
	public SemanticType semantic_type { get; private set; }
	public AstraIntegerValue? integer { get; private set; }
	public BinaryFloatValue? floating { get; private set; }
	public Astra.Text.TextBytes? text { get; private set; }
	public ConstantValue.text_value (SemanticType type, Astra.Text.TextBytes value) {
		semantic_type = type;
		text = value;
	}
	public bool boolean { get; private set; }
	public ConstantValue.integer_value (AstraIntegerValue value) {
		semantic_type = value.integer_type;
		integer = value;
	}
	public ConstantValue.float_value (SemanticType type, BinaryFloatValue value) {
		assert (type is FloatingType && ((FloatingType) type).format == value.format);
		semantic_type = type;
		floating = value;
	}
	public ConstantValue.bool_value (SemanticType type, bool value) {
		assert (type.kind == TypeKind.BOOL);
		semantic_type = type;
		boolean = value;
	}
	public CheckedExpression expression(SourceSpan span) {
		if (text != null) {
			return new CheckedTextExpression (span, semantic_type, text);
		}
		if (integer != null) {
			return new CheckedIntegerExpression.typed (span, semantic_type, integer);
		}
		if (floating != null) {
			return new CheckedFloatExpression (span, semantic_type, floating);
		}
		return new CheckedBooleanExpression (span, semantic_type, boolean ? BooleanLiteral.TRUE : BooleanLiteral.FALSE);
	}
	public static bool supports(SemanticType type) {
		return type is StringType || type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType;
	}
}

internal class ConstantDependency : Object {
	internal int index;
	internal SourceSpan span;
	internal ConstantDependency (int index, SourceSpan span) {
		this.index = index;
		this.span = span;
	}
}
internal class ConstantEdges : Object {
	internal GenericArray<ConstantDependency> dependencies = new GenericArray<ConstantDependency> ();
}
internal class ConstantFrame : Object {
	internal int index;
	internal int next;
	internal ConstantFrame (int index) {
		this.index = index;
	}
}

public enum ConstantState {
	COLLECTED, VISITING, COMPLETE
}

public class ConstantSymbol : Symbol {
	public ConstantDeclarationSyntax declaration { get; private set; }
	// Null identifies the whole-program scope. No Place/storage ordinal.
	public LexicalRegion? region { get; private set; }
	public ConstantValue? value { get; internal set; }
	public ConstantState state { get; internal set; default = ConstantState.COLLECTED; }
	public SemanticType? semantic_type { get { return value == null ? null : value.semantic_type; } }
	internal ConstantSymbol (ConstantDeclarationSyntax declaration, LexicalRegion? region, string? name = null) {
		base (declaration.span, declaration.name.span, name);
		this.declaration = declaration;
		this.region = region;
	}
}

public class CheckedConstantDeclaration : CheckedStatement {
	public ConstantSymbol constant { get; private set; }
	internal CheckedConstantDeclaration (ConstantSymbol constant) {
		base (constant.span);
		this.constant = constant;
	}
}

public class CheckedConstantReference : CheckedExpression {
	public ConstantSymbol constant { get; private set; }
	internal CheckedConstantReference (SourceSpan span, ConstantSymbol constant) {
		base (span, constant.semantic_type);
		assert (constant.state == ConstantState.COMPLETE);
		this.constant = constant;
	}
}
}
