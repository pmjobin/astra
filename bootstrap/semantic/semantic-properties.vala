// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class PropertySymbol : Symbol {
	public MethodSymbol? factory { get; internal set; }
	internal bool is_owned_foreign { get; set; }
	public bool is_owned_lazy { get; internal set; }
	public bool is_borrowed { get; internal set; }
	public bool is_lazy { get; internal set; }
	private WeakRef owner;
	public NativeInstanceSymbol? declaring_type { owned get { return (NativeInstanceSymbol?) owner.get (); } }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int member_ordinal { get; internal set; }
	public PropertyGetterSymbol getter { get; internal set; }
	public PropertySetterSymbol? setter { get; internal set; }

	internal PropertySymbol (SourceSpan span, SourceSpan name_span, NativeInstanceSymbol owner, SemanticType semantic_type, int ordinal, int member_ordinal) {
		base (span, name_span);
		this.owner = WeakRef (owner);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.member_ordinal = member_ordinal;
	}
}

// Siblings of methods, sharing the existing native callable implementation.
public abstract class PropertyAccessorSymbol : FunctionSymbol {
	private WeakRef parent;
	public PropertySymbol? property_symbol { owned get { return (PropertySymbol?) parent.get (); } }
	public ReceiverSymbol receiver { get; private set; }

	protected PropertyAccessorSymbol (SourceSpan span, SourceSpan name_span, PropertySymbol property_symbol, SemanticType return_type, GenericArray<ParameterSymbol> parameters, CallableDomain domain) {
		base (span, name_span, return_type, parameters, property_symbol.is_owned_foreign && return_type == property_symbol.semantic_type ? ResultOwnershipContract.OWNED_TRANSFER : property_symbol.is_borrowed && return_type == property_symbol.semantic_type ? ResultOwnershipContract.RECEIVER_BORROW : (return_type is StringType) ? ResultOwnershipContract.RECEIVER_TEXT : ResultOwnershipContract.UNMANAGED, null, domain);
		this.parent = WeakRef (property_symbol);
		this.receiver = new ReceiverSymbol (span, name_span, property_symbol.declaring_type.receiver_type);
	}
}

public class PropertyGetterSymbol : PropertyAccessorSymbol {
	internal PropertyGetterSymbol (SourceSpan span, SourceSpan name_span, PropertySymbol property_symbol) {
		base (span, name_span, property_symbol, property_symbol.semantic_type, new GenericArray<ParameterSymbol> (), CallableDomain.PROPERTY_GETTER);
	}
}

public class PropertySetterSymbol : PropertyAccessorSymbol {
	internal PropertySetterSymbol (SourceSpan span, SourceSpan name_span, PropertySymbol property_symbol, SemanticType void_type, ParameterSymbol parameter) {
		base (span, name_span, property_symbol, void_type, new GenericArray<ParameterSymbol> (), CallableDomain.PROPERTY_SETTER);
		parameters.add (parameter);
	}
}

public class CheckedProperty : CheckedNode {
	public PropertySymbol symbol { get; private set; }
	public CheckedPropertyAccessor getter { get; private set; }
	public CheckedPropertyAccessor? setter { get; private set; }
	internal CheckedProperty (PropertySymbol symbol, CheckedPropertyAccessor getter, CheckedPropertyAccessor? setter) {
		base (symbol.span);
		this.symbol = symbol;
		this.getter = getter;
		this.setter = setter;
	}
}

public class CheckedPropertyAccessor : CheckedFunction {
	public PropertyAccessorSymbol accessor { get { return (PropertyAccessorSymbol) symbol; } }
	internal CheckedPropertyAccessor (PropertyAccessorSymbol accessor, GenericArray<LocalSymbol> locals, CheckedBlockStatement body) {
		base (accessor, locals, body);
	}
}

// The public observation channel has receiver provenance. Its separate
// compiler-generated method is checked under the ordinary owned result rules.
public class CheckedLazyObserve : CheckedExpression {
	public PropertySymbol property_symbol { get; private set; }
	internal CheckedLazyObserve (SourceSpan span, PropertySymbol property_symbol) {
		base (span, property_symbol.semantic_type);
		this.property_symbol = property_symbol;
	}
}

public class CheckedPropertyGetExpression : CheckedCallExpression {
	public PropertyGetterSymbol getter { owned get { return (PropertyGetterSymbol) target; } }
	public PropertySymbol? property_symbol { owned get { return getter.property_symbol; } }
	internal CheckedPropertyGetExpression (SourceSpan span, PropertySymbol property_symbol, CheckedExpression receiver) {
		base (span, property_symbol.getter, new GenericArray<CheckedExpression> (), receiver);
	}
}

public class CheckedPropertySetStatement : CheckedCallStatement {
	public PropertySetterSymbol setter { owned get { return (PropertySetterSymbol) target; } }
	public PropertySymbol? property_symbol { owned get { return setter.property_symbol; } }
	internal CheckedPropertySetStatement (SourceSpan span, PropertySymbol property_symbol, CheckedExpression receiver, CheckedExpression value) {
		base (span, property_symbol.setter, new GenericArray<CheckedExpression> (), receiver);
		arguments.add (value);
	}
}
}
