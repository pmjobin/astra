// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class CheckedBaseLifecycleCall : CheckedCallStatement {
	internal CheckedBaseLifecycleCall (SourceSpan span, LifecycleSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression receiver) {
		base (span, target, arguments, receiver);
	}

}

// Sibling of MethodSymbol: lifecycle identities never enter method lookup.
public abstract class LifecycleSymbol : FunctionSymbol {
	private WeakRef owner;
	public ClassSymbol? declaring_class { owned get { return (ClassSymbol?) owner.get (); } }
	public ReceiverSymbol receiver { get; private set; }
	public int ordinal { get { return declaring_class.ordinal; } }
	public int member_ordinal { get; internal set; }
	protected LifecycleSymbol (SourceSpan span, SourceSpan name_span, ClassSymbol owner, SemanticType void_type, GenericArray<ParameterSymbol> parameters, CallableDomain kind, int member_ordinal) {
		base (span, name_span, void_type, parameters, ResultOwnershipContract.UNMANAGED, null, kind);
		this.owner = WeakRef (owner);
		this.member_ordinal = member_ordinal;
		this.receiver = new ReceiverSymbol (span, name_span, kind == CallableDomain.CONSTRUCTOR ? new ReceiverType (owner.semantic_type, ReceiverMode.INITIALIZING) : owner.receiver_type);
	}

}

public class ConstructorSymbol : LifecycleSymbol {
	internal ConstructorSymbol (SourceSpan span, SourceSpan name_span, ClassSymbol owner, SemanticType void_type, GenericArray<ParameterSymbol> parameters, int member_ordinal) {
		base (span, name_span, owner, void_type, parameters, CallableDomain.CONSTRUCTOR, member_ordinal);
	}

}

public class DestructorSymbol : LifecycleSymbol {
	internal DestructorSymbol (SourceSpan span, SourceSpan name_span, ClassSymbol owner, SemanticType void_type, int member_ordinal) {
		base (span, name_span, owner, void_type, new GenericArray<ParameterSymbol> (), CallableDomain.DESTRUCTOR, member_ordinal);
	}

}

public class CheckedConstructor : CheckedFunction {
	public ConstructorSymbol constructor { get { return (ConstructorSymbol) symbol; } }
	public FieldInitializationState initialization { get; private set; }
	internal CheckedConstructor (ConstructorSymbol symbol, GenericArray<LocalSymbol> locals, CheckedBlockStatement body, FieldInitializationState initialization) {
		base (symbol, locals, body);
		this.initialization = initialization.copy ();
	}

}

public class CheckedDestructor : CheckedFunction {
	public DestructorSymbol destructor { get { return (DestructorSymbol) symbol; } }
	internal CheckedDestructor (DestructorSymbol symbol, GenericArray<LocalSymbol> locals, CheckedBlockStatement body) {
		base (symbol, locals, body);
	}

}

public class CheckedConstructorObjectInitialization : CheckedObjectConstruction {
	public CheckedExpression? allocation_context { get; private set; }
	public ConstructorSymbol constructor { get; private set; }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedConstructorObjectInitialization (SourceSpan span, LexicalObjectStorageSymbol storage, LocalSymbol local, ConstructorSymbol constructor, GenericArray<CheckedExpression> arguments, CheckedExpression? allocation_context = null) {
		base (span, storage, local, new GenericArray<CheckedFieldInitializer> ());
		this.constructor = constructor;
		this.arguments = arguments;
		this.allocation_context = allocation_context;
	}

}

public class CheckedFieldInitialize : CheckedStatement {
	public CheckedReceiverFieldPlace target { get; private set; }
	public CheckedExpression value { get; private set; }
	internal CheckedFieldInitialize (SourceSpan span, CheckedReceiverFieldPlace target, CheckedExpression value) {
		base (span);
		this.target = target;
		this.value = value;
	}

}
}
