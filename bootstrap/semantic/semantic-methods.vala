// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;

namespace Astra.Semantic {
// Inherits native callable contracts, while exact member identity is authoritative.
public class MethodSymbol : FunctionSymbol {
	public ClassMethodInstance? generic_method_instance { get; internal set; }
	private WeakRef application_scope_identity;
	public GenericFunctionSymbol? application_scope { owned get { return (GenericFunctionSymbol?) application_scope_identity.get (); } internal set { application_scope_identity = WeakRef (value); } }
	private WeakRef owner;
	public NativeInstanceSymbol? declaring_type { owned get { return (NativeInstanceSymbol?) owner.get (); } }
	public StructSymbol? declaring_struct { owned get { return declaring_type as StructSymbol; } }
	public ReceiverSymbol receiver { get; private set; }
	public int ordinal { get; private set; }
	public int member_ordinal { get; internal set; }

	internal MethodSymbol (SourceSpan span, SourceSpan name_span, NativeInstanceSymbol declaring_type, SemanticType return_type, GenericArray<ParameterSymbol> parameters, int ordinal, int member_ordinal, ResultOwnershipContract result_contract, CForeignCleanupContract? owned_cleanup, string? name = null) {
		base (span, name_span, return_type, parameters, result_contract, owned_cleanup, CallableDomain.METHOD, name);
		this.owner = WeakRef (declaring_type);
		this.receiver = new ReceiverSymbol (span, name_span, declaring_type.receiver_type);
		this.ordinal = ordinal;
		this.member_ordinal = member_ordinal;
	}

}

public class ReceiverSymbol : Symbol {
	public ReceiverType semantic_type { get; private set; }

	internal ReceiverSymbol (SourceSpan span, SourceSpan name_span, ReceiverType semantic_type) {
		base (span, name_span);
		this.semantic_type = semantic_type;
	}

}

public class CheckedMethod : CheckedFunction {
	public MethodSymbol method { get { return (MethodSymbol) symbol; } }

	internal CheckedMethod (MethodSymbol method, GenericArray<LocalSymbol> locals, CheckedBlockStatement body) {
		base (method, locals, body);
	}

}

public class CheckedThisExpression : CheckedExpression {
	public ReceiverSymbol receiver { get; private set; }

	internal CheckedThisExpression (SourceSpan span, ReceiverSymbol receiver) {
		base (span, receiver.semantic_type);
		this.receiver = receiver;
	}

}

// Uses the same address-taken local storage; this value cannot escape a call.
public class CheckedReceiverAddressExpression : CheckedExpression {
	public LocalSymbol? local { get; private set; }
	public CheckedPlace? receiver_place { get; private set; }
	internal CheckedReceiverAddressExpression.projection (SourceSpan span, CheckedPlace place, ReceiverType type) {
		base (span, type);
		this.receiver_place = place;
	}

	internal CheckedReceiverAddressExpression (SourceSpan span, LocalSymbol local, ReceiverType semantic_type) {
		base (span, semantic_type);
		this.local = local;
	}

}

public class CheckedReceiverFieldPlace : CheckedPlace {
	public CheckedExpression receiver { get; private set; }
	public StructFieldSymbol field { get; private set; }

	internal CheckedReceiverFieldPlace (SourceSpan span, CheckedExpression receiver, StructFieldSymbol field) {
		base (span, field.semantic_type);
		this.receiver = receiver;
		this.field = field;
	}

}
}
