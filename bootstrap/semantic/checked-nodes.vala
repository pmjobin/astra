// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Foreign;

namespace Astra.Semantic {
public abstract class CheckedNode : Object {
	public SourceSpan span { get; private set; }

	protected CheckedNode (SourceSpan span) {
		this.span = span;
	}
}

// Attached foreign boundary only. The program owns the native target;
// this weak reference never creates a function/body ownership cycle.
public class CExportSymbol : CheckedNode {
	public DeclarationPolicyId declaration_policy { get { return DeclarationPolicyId.C_EXPORT; } }
	private WeakRef native_target;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) native_target.get (); } }
	private string external_identifier;
	public string external_symbol { get { return external_identifier; } }
	public SourceSpan name_span { get; private set; }
	public ForeignAbi abi { get; private set; }
	public int ordinal { get; private set; }
	public CRecordAbi record_abi { get; private set; }
	public CBoolAbi bool_abi { get; internal set; }
	private CBoolAbi admitted_bool_abi;
	public bool bool_policy_valid() {
		return bool_abi == admitted_bool_abi && bool_abi.valid ();
	}

	internal CExportSymbol (SourceSpan span, SourceSpan name_span, FunctionSymbol target, string external_symbol, ForeignAbi abi, int ordinal, CRecordAbi record_abi = CRecordAbi.NONE, CBoolAbi bool_abi = CBoolAbi.NONE) {
		base (span);
		this.bool_abi = admitted_bool_abi = bool_abi;
		this.name_span = name_span;
		this.native_target = WeakRef (target);
		this.external_identifier = external_symbol;
		this.abi = abi;
		this.ordinal = ordinal;
		this.record_abi = record_abi;
	}
}

public class CheckedProgram : CheckedNode {
	public GenericArray<ExactClassDefinitionIdentity> generic_classes { get; private set; default = new GenericArray<ExactClassDefinitionIdentity> (); }
	public GenericArray<EnumDefinition> enums { get; private set; default = new GenericArray<EnumDefinition> (); }
	public GenericArray<ConstantSymbol> constants { get; private set; default = new GenericArray<ConstantSymbol> (); }
	public GenericArray<CheckedGenericStruct> generic_structs { get; private set; default = new GenericArray<CheckedGenericStruct> (); }
	public GenericArray<CheckedGenericFunction> generic_functions { get; private set; default = new GenericArray<CheckedGenericFunction> (); }

	public GenericArray<CheckedFunction> all_definitions() {
		var result = new GenericArray<CheckedFunction> ();
		foreach (var function in functions) {
			result.add (function);
		}
		foreach (var function in generic_functions) {
			result.add (function);
		}
		return result;
	}
	public GenericArray<CheckedProperty> properties { get; private set; default = new GenericArray<CheckedProperty> (); }
	public GenericArray<ClassSymbol> classes { get; private set; default = new GenericArray<ClassSymbol> (); }
	public GenericArray<ClassSymbol> class_applications { get; private set; default = new GenericArray<ClassSymbol> (); }
	public GenericArray<MethodSymbol> method_applications { get; private set; default = new GenericArray<MethodSymbol> (); }

	public GenericArray<NativeInstanceSymbol> native_instances() {
		var result = new GenericArray<NativeInstanceSymbol> ();
		foreach (var instance in structs) {
			result.add (instance);
		}
		foreach (var instance in classes) {
			result.add (instance);
		}
		return result;
	}

	public GenericArray<HandleSymbol> handles { get; private set; }
	public GenericArray<StructSymbol> structs { get; private set; }
	public BuiltinTypes types { get; private set; }
	public GenericArray<CheckedFunction> functions { get; private set; }
	public GenericArray<CFunctionSymbol> c_functions { get; private set; }
	public GenericArray<CExportSymbol> c_exports { get; private set; }

	internal CheckedProgram (SourceSpan span, BuiltinTypes types, GenericArray<CheckedFunction> functions, GenericArray<CFunctionSymbol>? c_functions = null, GenericArray<CExportSymbol>? c_exports = null, GenericArray<StructSymbol>? structs = null, GenericArray<HandleSymbol>? handles = null) {
		base (span);
		this.handles = handles ?? new GenericArray<HandleSymbol> ();
		this.structs = structs ?? new GenericArray<StructSymbol> ();
		this.types = types;
		this.functions = functions;
		this.c_functions = c_functions ?? new GenericArray<CFunctionSymbol> ();
		this.c_exports = c_exports ?? new GenericArray<CExportSymbol> ();
	}
}

public class CheckedFunction : CheckedNode {
	// Source evidence only; every lower stage reconstructs its own proof.
	public RuntimeLifetimeSummary? runtime_lifetimes { get; internal set; }
	public NativeDeclarationSignature? native_declaration { get; private set; }
	internal void bind_native_declaration(NativeDeclarationSignature declaration) {
		native_declaration = declaration;
		locals = new GenericArray<LocalSymbol> ();
		body = new CheckedBlockStatement (body.span, new GenericArray<CheckedStatement> (), new LexicalRegion (null, 0));
	}
	public FunctionSymbol symbol { get; private set; }
	public GenericArray<LocalSymbol> locals { get; private set; }
	public CheckedBlockStatement body { get; private set; }

	internal CheckedFunction (FunctionSymbol symbol, GenericArray<LocalSymbol> locals, CheckedBlockStatement body) {
		base (symbol.span);
		this.symbol = symbol;
		this.locals = locals;
		this.body = body;
	}
}

public abstract class CheckedStatement : CheckedNode {
	protected CheckedStatement (SourceSpan span) {
		base (span);
	}
}

public class CheckedBlockStatement : CheckedStatement {
	public LexicalRegion region { get; private set; }
	public GenericArray<CheckedStatement> statements { get; private set; }

	internal CheckedBlockStatement (SourceSpan span, GenericArray<CheckedStatement> statements, LexicalRegion region) {
		base (span);
		this.statements = statements;
		this.region = region;
	}
}

public class CheckedWithContract : CheckedNode {
	public LocalSymbol source { get; private set; }
	public CheckedWithContract (SourceSpan span, LocalSymbol source) {
		base (span);
		this.source = source;
	}
}
public class CheckedWithScope : CheckedBlockStatement {
	public CheckedWithContract contract { get; internal set; }
	public LocalSymbol source { get; private set; }
	public CheckedWithScope (SourceSpan span, CheckedWithContract contract, CheckedBlockStatement body) {
		base (span, body.statements, body.region);
		this.contract = contract;
		this.source = contract.source;
	}
}
public class CheckedWithReference : CheckedExpression {
	public CheckedWithContract contract { get; internal set; }
	public CheckedWithReference (SourceSpan span, CheckedWithContract contract) {
		base (span, contract.source.semantic_type);
		this.contract = contract;
	}
}

public class CheckedIf : CheckedStatement {
	public CheckedExpression condition { get; private set; }
	public CheckedBlockStatement then_body { get; private set; }
	public CheckedBlockStatement? else_body { get; private set; }

	internal CheckedIf (SourceSpan span, CheckedExpression condition, CheckedBlockStatement then_body, CheckedBlockStatement? else_body) {
		base (span);
		this.condition = condition;
		this.then_body = then_body;
		this.else_body = else_body;
	}
}

// Identity is the object, not its function-local display ordinal. The while
// owns it; transfers never retain a loop, body, or target strongly.
public class CheckedLoopTarget : CheckedNode {
	public int ordinal { get; private set; }

	internal CheckedLoopTarget (SourceSpan span, int ordinal) {
		base (span);
		this.ordinal = ordinal;
	}
}

public class CheckedWhile : CheckedStatement {
	public CheckedSequenceIteration? sequence { get; internal set; }
	public bool has_sequence { get; private set; }
	public CheckedIterationContract? iteration { get; internal set; }
	public bool has_iteration { get; private set; }
	public CheckedLoopTarget target { get; private set; }
	public CheckedExpression condition { get; private set; }
	public CheckedBlockStatement body { get; private set; }
	public bool has_step { get; private set; }
	public CheckedBlockStatement? step { get; internal set; }

	internal CheckedWhile (SourceSpan span, CheckedLoopTarget target, CheckedExpression condition, CheckedBlockStatement body, CheckedBlockStatement? step = null, CheckedIterationContract? iteration = null, CheckedSequenceIteration? sequence = null) {
		base (span);
		this.target = target;
		this.condition = condition;
		this.body = body;
		this.step = step;
		this.has_step = step != null;
		this.iteration = iteration;
		this.has_iteration = iteration != null;
		this.sequence = sequence;
		this.has_sequence = sequence != null;
	}
}

public class CheckedSequenceIteration : CheckedNode {
	public bool is_iterator { get; private set; }
	private WeakRef advance_method;
	private WeakRef current_method;
	public MethodSymbol? advance { owned get { return (MethodSymbol?) advance_method.get (); } }
	public MethodSymbol? current { owned get { return (MethodSymbol?) current_method.get (); } }
	public CheckedLoopTarget target { get; private set; }
	public CheckedExpression source { get; private set; }
	public LocalSymbol? index { get; private set; }
	public LocalSymbol binding { get; private set; }
	internal CheckedSequenceIteration (SourceSpan span, CheckedLoopTarget target, CheckedExpression source, LocalSymbol index, LocalSymbol binding) {
		base (span);
		this.target = target;
		this.source = source;
		this.index = index;
		this.binding = binding;
	}
	internal CheckedSequenceIteration.iterator (SourceSpan span, CheckedLoopTarget target, CheckedExpression source, LocalSymbol binding, MethodSymbol advance, MethodSymbol current) {
		base (span);
		this.is_iterator = true;
		this.target = target;
		this.source = source;
		this.binding = binding;
		this.advance_method = WeakRef (advance);
		this.current_method = WeakRef (current);
	}
}

public class CheckedIterationContract : CheckedNode {
	public LocalSymbol? binding { get; private set; }
	public CheckedLoopTarget target { get; private set; }
	public CheckedObjectFieldPlace store { get; private set; }
	public LocalSymbol index { get; private set; }
	internal CheckedIterationContract (SourceSpan span, CheckedLoopTarget target, CheckedObjectFieldPlace store, LocalSymbol index, LocalSymbol? binding = null) {
		base (span);
		this.target = target;
		this.store = store;
		this.index = index;
		this.binding = binding;
	}
}

public class CheckedBreak : CheckedStatement {
	private WeakRef loop_target;
	public CheckedLoopTarget? target { owned get { return (CheckedLoopTarget?) loop_target.get (); } }

	internal CheckedBreak (SourceSpan span, CheckedLoopTarget target) {
		base (span);
		this.loop_target = WeakRef (target);
	}
}

public class CheckedContinue : CheckedStatement {
	private WeakRef loop_target;
	public CheckedLoopTarget? target { owned get { return (CheckedLoopTarget?) loop_target.get (); } }

	internal CheckedContinue (SourceSpan span, CheckedLoopTarget target) {
		base (span);
		this.loop_target = WeakRef (target);
	}
}

public class CheckedOwnershipReturn : CheckedStatement {
	public CheckedOwnershipMove? transfer { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public CForeignCleanupContract? cleanup { get; private set; }
	public ClassSymbol? object_owner { get; private set; }
	public CheckedExpression? producer { get; private set; }
	public ObjectResultProvenance provenance { get { return object_owner == null ? ObjectResultProvenance.NONE : transfer != null ? transfer.source.object_provenance : (producer is CheckedOwnedObjectResultConstruction) ? ObjectResultProvenance.RESULT_STORAGE : producer != null ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : ObjectResultProvenance.NULL; } }

	internal CheckedOwnershipReturn (SourceSpan span, SemanticType semantic_type, CForeignCleanupContract? cleanup, CheckedOwnershipMove? transfer, ClassSymbol? object_owner = null, CheckedExpression? producer = null) {
		base (span);
		this.semantic_type = semantic_type;
		this.cleanup = cleanup;
		this.transfer = transfer;
		this.object_owner = object_owner;
		this.producer = producer;
	}
}

public class CheckedOwnedArgument : CheckedExpression {
	public bool heap_object {
		get {
			bool symbolic_storage = parameter.semantic_type is TypeParameterType || parameter.semantic_type is ClassType;
			return symbolic_storage && transfer != null ? transfer.source.heap_object : parameter.heap_object;
		}
	}
	public CheckedExpression? producer { get; private set; }
	public ClassSymbol? object_owner { get; private set; }
	public CheckedOwnershipMove? transfer { get; private set; }
	public ParameterSymbol parameter { get; private set; }
	public CForeignCleanupContract? cleanup { get; private set; }

	internal CheckedOwnedArgument (SourceSpan span, ParameterSymbol parameter, CForeignCleanupContract? cleanup, CheckedOwnershipMove? transfer, ClassSymbol? object_owner = null, SemanticType? substituted_type = null, CheckedExpression? producer = null) {
		base (span, substituted_type ?? parameter.semantic_type);
		this.producer = producer;
		this.parameter = parameter;
		this.object_owner = object_owner;
		this.cleanup = cleanup;
		this.transfer = transfer;
	}
}

public enum OwnedProducerKind {
	FOREIGN_OWNED_CALL,
	NATIVE_OWNED_CALL
}

public interface CheckedInvocation : Object {
	public abstract OwnedValueProducer? result_producer();
}

public class OwnedValueProducer : Object {
	public ClassSymbol? object_owner { get; private set; }
	public OwnedProducerKind kind { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public CForeignCleanupContract? cleanup { get; private set; }

	internal OwnedValueProducer (OwnedProducerKind kind, SemanticType semantic_type, CForeignCleanupContract? cleanup, ClassSymbol? object_owner = null) {
		this.kind = kind;
		this.object_owner = object_owner;
		this.semantic_type = semantic_type;
		this.cleanup = cleanup;
	}
}

public class CheckedForeignReturn : CheckedStatement {
	public ForeignImportBinding binding { get; private set; }
	public FunctionSymbol factory { get; private set; }
	internal CheckedForeignReturn (SourceSpan span, ForeignImportBinding binding, FunctionSymbol factory) {
		base (span);
		this.binding = binding;
		this.factory = factory;
	}
}
public class CheckedForeignSignalReturn : CheckedStatement {
	public ForeignSignalBinding binding { get; private set; }
	internal CheckedForeignSignalReturn (SourceSpan span, ForeignSignalBinding binding) {
		base (span);
		this.binding = binding;
	}
}
public class CheckedReturnStatement : CheckedStatement {
	public CheckedExpression? expression { get; private set; }

	internal CheckedReturnStatement (SourceSpan span, CheckedExpression? expression) {
		base (span);
		this.expression = expression;
	}
}

// Dedicated storage copy context, never an expression or ownership transfer.
public class CheckedStructCopy : CheckedStatement {
	public CheckedPlace destination { get; private set; }
	public CheckedPlace source { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public Copyability copyability { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CheckedStructCopy (SourceSpan span, CheckedPlace destination, CheckedPlace source, SemanticType semantic_type, Copyability copyability, bool initializes_destination = false) {
		base (span);
		this.destination = destination;
		this.source = source;
		this.semantic_type = semantic_type;
		this.copyability = copyability;
		this.initializes_destination = initializes_destination;
	}
}

// Initializer syntax targets exact storage; it is never an expression Value.
public class CheckedStructInitializer : CheckedNode {
	public SemanticType semantic_type { get; private set; }
	public GenericArray<CheckedFieldInitializer> fields { get; private set; }
	internal CheckedStructInitializer (SourceSpan span, SemanticType semantic_type, GenericArray<CheckedFieldInitializer> fields) {
		base (span);
		this.semantic_type = semantic_type;
		this.fields = fields;
	}
}

public class CheckedFieldInitializer : CheckedNode {
	public FieldSymbol field { get; private set; }
	public CheckedExpression expression { get; private set; }
	public CheckedStructProducer? producer { get; private set; }
	internal CheckedFieldInitializer.from_producer (SourceSpan span, FieldSymbol field, CheckedStructProducer producer) {
		base (span);
		this.field = field;
		this.producer = producer;
	}

	public CheckedStructInitializer? initializer { get; private set; }
	internal CheckedFieldInitializer.nested (SourceSpan span, FieldSymbol field, CheckedStructInitializer initializer) {
		base (span);
		this.field = field;
		this.initializer = initializer;
	}

	internal CheckedFieldInitializer (SourceSpan span, FieldSymbol field, CheckedExpression expression) {
		base (span);
		this.field = field;
		this.expression = expression;
	}
}

public class CheckedStructMove : CheckedStatement {
	public LocalSymbol source { get; private set; }
	public LocalSymbol destination { get; private set; }
	internal CheckedStructMove (SourceSpan span, LocalSymbol source, LocalSymbol destination) {
		base (span);
		this.source = source;
		this.destination = destination;
	}
}
public class CheckedRecordTake : CheckedStatement {
	public LocalSymbol source { get; private set; }
	public CheckedFieldPlace field { get; private set; }
	public LocalSymbol destination { get; private set; }
	internal CheckedRecordTake (SourceSpan span, LocalSymbol source, CheckedFieldPlace field, LocalSymbol destination) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
	}
}
public class CheckedRecordReplace : CheckedStatement {
	public LocalSymbol owner { get; private set; }
	public CheckedFieldPlace field { get; private set; }
	public CheckedExpression incoming { get; private set; }
	internal CheckedRecordReplace (SourceSpan span, LocalSymbol owner, CheckedFieldPlace field, CheckedExpression incoming) {
		base (span);
		this.owner = owner;
		this.field = field;
		this.incoming = incoming;
	}
}

public class CheckedStructLocalDeclaration : CheckedStatement {
	public LocalSymbol local { get; private set; }
	// Written initializer order, independent of field declaration ordinals.
	public GenericArray<CheckedFieldInitializer> initializers { get; private set; }

	internal CheckedStructLocalDeclaration (SourceSpan span, LocalSymbol local, GenericArray<CheckedFieldInitializer> initializers) {
		base (span);
		this.local = local;
		this.initializers = initializers;
	}
}

public class CheckedFieldAssignment : CheckedStatement {
	public LocalSymbol local { get; private set; }
	public StructFieldSymbol field { get; private set; }
	public CheckedExpression expression { get; private set; }

	internal CheckedFieldAssignment (SourceSpan span, LocalSymbol local, StructFieldSymbol field, CheckedExpression expression) {
		base (span);
		this.local = local;
		this.field = field;
		this.expression = expression;
	}
}

public class CheckedLocalDeclaration : CheckedStatement {
	public LocalSymbol local { get; private set; }
	public CheckedExpression initializer { get; private set; }

	internal CheckedLocalDeclaration (SourceSpan span, LocalSymbol local, CheckedExpression initializer) {
		base (span);
		this.local = local;
		this.initializer = initializer;
		assert (local.is_buffer_owner || local.object_owner != null || local.semantic_type.is_text_slice () || !local.semantic_type.is_lexically_borrowed_value () || BorrowProvenance.for_expression (initializer).outlives (local.lexical_region));
	}
}

public class CheckedOwnedLocalDeclaration : CheckedLocalDeclaration {
	public CheckedExpression owned_initializer { get { return initializer; } }
	public CForeignCleanupContract cleanup { get { return local.cleanup; } }
	public LexicalRegion lexical_region { get { return local.lexical_region; } }

	internal CheckedOwnedLocalDeclaration (SourceSpan span, LocalSymbol local, CheckedExpression initializer) {
		base (span, local, initializer);
		var invocation = initializer as CheckedInvocation;
		var producer = invocation == null ? null : invocation.result_producer ();
		bool generic_producer = local.generic_owned_local && local.is_generic_owner && local.generic_owner_source == null
		    && initializer.semantic_type == local.semantic_type && producer != null && producer.semantic_type == local.semantic_type
		    && producer.kind == OwnedProducerKind.NATIVE_OWNED_CALL && initializer.ownership_kind == OwnershipKind.OWNED;
		assert (generic_producer || (local.heap_object && initializer is CheckedSharedOperation && local.semantic_type is ClassType && ((ClassType) local.semantic_type).intrinsically_shared && initializer.semantic_type == local.semantic_type) || (initializer is CheckedSlotsTake && local.heap_object && local.object_owner == ((CheckedSlotsTake) initializer).element && local.semantic_type == initializer.semantic_type) || (local.generic_owner_source != null && local.is_generic_owner && initializer is CheckedOwnershipMove && ((CheckedOwnershipMove) initializer).source == local.generic_owner_source && initializer.semantic_type == local.semantic_type) || (local.heap_object && initializer is CheckedOwnershipMove && ((CheckedOwnershipMove) initializer).source.heap_object && ((CheckedOwnershipMove) initializer).object_owner == local.object_owner && initializer.semantic_type == local.semantic_type) || (local.is_buffer_owner && initializer.owns_buffer && initializer.semantic_type == local.semantic_type) || (local.object_owner != null && initializer is CheckedInvocation && ((CheckedInvocation) initializer).result_producer () != null && ((CheckedInvocation) initializer).result_producer ().object_owner == local.object_owner) || (local.semantic_type.is_ownable_handle_type () && local.cleanup != null && local.cleanup == initializer.owned_cleanup && (initializer is CheckedInvocation || initializer is CheckedOwnershipMove || initializer is CheckedSharedOperation || initializer is CheckedClosureBind || initializer is CheckedScopedAllocator || initializer is CheckedSlotsTake)));
	}
}

// Exact temporary argument adaptation, never an ordinary owned-local read.
public class CheckedOwnedBorrowValue : CheckedExpression {
	public LocalSymbol source { get; private set; }
	public ParameterSymbol parameter { get; private set; }

	internal CheckedOwnedBorrowValue (SourceSpan span, LocalSymbol source, ParameterSymbol parameter) {
		base (span, CallbackType.borrowed_type (source.semantic_type, parameter.semantic_type));
		this.source = source;
		this.parameter = parameter;
	}
}

// Assignment into an existing lexical slot, never a read or a fresh local.
public class CheckedOwnershipRearmAssignment : CheckedStatement {
	public LocalSymbol owner { get; private set; }
	public CheckedExpression incoming { get; private set; }
	public CheckedCallExpression? producer { get { return incoming as CheckedCallExpression; } }
	public CForeignCleanupContract cleanup { get { return owner.cleanup; } }

	internal CheckedOwnershipRearmAssignment (SourceSpan span, LocalSymbol owner, CheckedExpression producer) {
		base (span);
		this.owner = owner;
		this.incoming = producer;
		assert (owner.semantic_type.is_ownable_handle_type () && owner.cleanup != null && producer.owned_cleanup == owner.cleanup && producer.semantic_type == owner.semantic_type);
	}
}

public class CheckedOwnershipRelease : CheckedStatement {
	public LocalSymbol owner { get; private set; }
	public CForeignCleanupContract cleanup { get { return owner.cleanup; } }

	internal CheckedOwnershipRelease (SourceSpan span, LocalSymbol owner) {
		base (span);
		this.owner = owner;
		assert (owner.heap_object || owner.is_buffer_owner || (owner.cleanup != null && owner.semantic_type.is_ownable_handle_type ()));
	}
}

public class CheckedOwnershipMove : CheckedExpression {
	public ClassSymbol? object_owner { get { return source.object_owner; } }
	public LexicalObjectStorageSymbol? object_storage { get { return source.object_storage; } }
	public LocalSymbol source { get; private set; }
	public CForeignCleanupContract? cleanup { get { return source.cleanup; } }

	internal CheckedOwnershipMove (SourceSpan span, LocalSymbol source) {
		base (span, source.semantic_type);
		this.source = source;
		assert (source.is_owned && (source.semantic_type.is_ownable_handle_type () || source.object_owner != null || source.is_generic_owner || source.is_buffer_owner));
	}
}

// CheckedProgram owns native functions/symbols and imported C symbols. Calls never own
// callees; expired references are rejected at the Core construction boundary.
public class CheckedValueStatement : CheckedStatement {
	public CheckedExpression value { get; private set; }
	internal CheckedValueStatement (SourceSpan span, CheckedExpression value) {
		base (span);
		this.value = value;
	}
}

public class CheckedCallStatement : CheckedStatement {
	public bool discard_owned_success { get; internal set; }
	public CheckedExpression? receiver { get; private set; }
	private WeakRef callee;
	public DirectCallableSymbol? target { owned get { return (DirectCallableSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }

	internal CheckedCallStatement (SourceSpan span, DirectCallableSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver = null) {
		base (span);
		this.receiver = receiver;
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}
}

public class CheckedAssignment : CheckedStatement {
	public LocalSymbol target { get; private set; }
	public CheckedExpression expression { get; private set; }

	internal CheckedAssignment (SourceSpan span, LocalSymbol target, CheckedExpression expression) {
		base (span);
		this.target = target;
		this.expression = expression;
		assert (target.semantic_type.is_text_slice () || !target.semantic_type.is_lexically_borrowed_value () || BorrowProvenance.for_expression (expression).outlives (target.lexical_region));
	}
}

public abstract class CheckedExpression : CheckedNode {
	public Astra.Text.TextLoanIntent? text_loan_intent { get; internal set; }
	public bool owns_buffer {
		get {
			var move = this as CheckedOwnershipMove;
			var call = this as CheckedCallExpression;
			var awaited = this as CheckedTaskAwait;
			return this is CheckedOwnedBufferAllocate || (move != null && move.source.is_buffer_owner) || (call != null && call.semantic_type is SliceType && call.owned_producer != null) || (awaited != null && !awaited.discard && awaited.semantic_type is SliceType && ((TaskType) awaited.child.semantic_type).success_mode == ResultOwnershipContract.OWNED_TRANSFER);
		}
	}
	public CForeignCleanupContract? owned_cleanup {
		owned get {
			if (this is CheckedScopedAllocator) {
				return ((CheckedScopedAllocator) this).cleanup;
			}
			if (this is CheckedSlotsTake) {
				return ((CheckedSlotsTake) this).resource_cleanup;
			}
			if (this is CheckedClosureBind) {
				return ((CheckedClosureBind) this).cleanup;
			}
			if (this is CheckedSharedOperation) {
				return ((CheckedSharedOperation) this).cleanup;
			}
			var move = this as CheckedOwnershipMove;
			if (move != null) {
				return move.cleanup;
			}
			var invocation = this as CheckedInvocation;
			if (invocation != null) {
				var producer = invocation.result_producer ();
				return producer == null ? null : producer.cleanup;
			}
			var local = this as CheckedLocalReferenceExpression;
			return local == null ? null : local.local.cleanup;
		}
	}
	public OwnershipKind ownership_kind {
		get {
			if (owns_buffer) {
				return OwnershipKind.OWNED;
			}
			var move = this as CheckedOwnershipMove;
			var local = this as CheckedLocalReferenceExpression;
			var argument = this as CheckedOwnedArgument;
			var invocation = this as CheckedInvocation;
			var producer = invocation == null ? null : invocation.result_producer ();
			if ((move != null && move.source.is_generic_owner) || (argument != null && argument.semantic_type is TypeParameterType) || (producer != null && semantic_type is TypeParameterType)) {
				return OwnershipKind.OWNED;
			}
			if ((this is CheckedSlotsTake && ((CheckedSlotsTake) this).element != null) || this is CheckedOwnedObjectResultConstruction || (producer != null && producer.object_owner != null)) {
				return OwnershipKind.TRANSFERABLE_OBJECT_OWNER;
			}
			if ((move != null && move.object_owner != null) || (local != null && local.local.object_owner != null) || (argument != null && argument.object_owner != null)) {
				return OwnershipKind.TRANSFERABLE_OBJECT_OWNER;
			}
			return owned_cleanup == null ? OwnershipKind.UNMANAGED : OwnershipKind.OWNED;
		}
	}
	public SemanticType semantic_type { get; private set; }

	protected CheckedExpression (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

public class CheckedCallExpression : CheckedExpression, CheckedInvocation {
	public OwnedValueProducer? result_producer() {
		return owned_producer;
	}
	public LexicalObjectStorageSymbol? candidate_storage { get; internal set; }
	public ResultObjectStorageSymbol? result_storage { get; internal set; }
	public CheckedExpression? receiver { get; private set; }
	public OwnedValueProducer? owned_producer { get; internal set; }
	public CForeignOwnedResultContract? owned_result { get; private set; }
	private WeakRef callee;
	public DirectCallableSymbol? target { owned get { return (DirectCallableSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }

	internal CheckedCallExpression (SourceSpan span, DirectCallableSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver = null, SemanticType? substituted_result = null) {
		base (span, substituted_result ?? target.return_type);
		this.receiver = receiver;
		assert (target.return_type.kind != TypeKind.VOID);
		var imported = target as CFunctionSymbol;
		var native = target as FunctionSymbol;
		if (imported != null && imported.metadata.owned_result != null) {
			this.owned_producer = new OwnedValueProducer (OwnedProducerKind.FOREIGN_OWNED_CALL, target.return_type, imported.metadata.owned_result.cleanup);
		} else if (native != null && native.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			this.owned_producer = new OwnedValueProducer (OwnedProducerKind.NATIVE_OWNED_CALL, target.return_type, native.owned_cleanup, native.result_class);
		}
		this.owned_result = imported == null ? null : imported.metadata.owned_result;
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}
}

public class CheckedNullPointerExpression : CheckedExpression {
	internal CheckedNullPointerExpression (SourceSpan span, SemanticType semantic_type) {
		base (span, semantic_type);
	}
}

public class CheckedBooleanExpression : CheckedExpression {
	public BooleanLiteral literal { get; private set; }

	internal CheckedBooleanExpression (SourceSpan span, SemanticType semantic_type, BooleanLiteral literal) {
		base (span, semantic_type);
		this.literal = literal;
	}
}

public class CheckedVectorDotExpression : CheckedExpression {
	public VectorDotKind dot_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CheckedExpression? accumulator { get; private set; }
	public CheckedExpression first { get; private set; }
	public CheckedExpression second { get; private set; }

	internal CheckedVectorDotExpression (SourceSpan span, VectorDotKind dot_kind, SemanticType source_type, SemanticType destination_type, CheckedExpression? accumulator, CheckedExpression first, CheckedExpression second) {
		base (span, destination_type);
		this.dot_kind = dot_kind;
		this.source_type = source_type;
		this.accumulator = accumulator;
		this.first = first;
		this.second = second;
	}
}

public class CheckedDspExpression : CheckedExpression {
	public DspPrimitiveKind primitive_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public IntegerType? destination_element { get; private set; }
	public CheckedExpression first { get; private set; }
	public CheckedExpression? second { get; private set; }

	internal CheckedDspExpression (SourceSpan span, DspPrimitiveKind primitive_kind, SemanticType source_type, SemanticType destination_type, CheckedExpression first, CheckedExpression? second, IntegerType? destination_element = null) {
		base (span, destination_type);
		this.primitive_kind = primitive_kind;
		this.source_type = source_type;
		this.destination_element = destination_element;
		this.first = first;
		this.second = second;
	}
}

// Direction owns the invalid-count trap contract; width and count type
// derive from exact retained values, with no independently mutable copy.
public class CheckedIntegerShiftExpression : CheckedExpression {
	public IntegerShiftKind shift_kind { get; private set; }
	public CheckedExpression operand { get; private set; }
	public CheckedExpression count { get; private set; }
	public uint element_bit_width { get { return IntegerShiftKind.element_type (semantic_type).bit_width; } }

	internal CheckedIntegerShiftExpression (SourceSpan span, SemanticType semantic_type, IntegerShiftKind shift_kind, CheckedExpression operand, CheckedExpression count) {
		base (span, semantic_type);
		this.shift_kind = shift_kind;
		this.operand = operand;
		this.count = count;
	}
}

public class CheckedNumericConversionExpression : CheckedExpression {
	public NumericConversionPolicy policy { get; private set; }
	public NumericConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CheckedExpression operand { get; private set; }

	internal CheckedNumericConversionExpression (SourceSpan span, SemanticType source_type, SemanticType destination_type, NumericConversionKind conversion_kind, CheckedExpression operand, NumericConversionPolicy policy) {
		base (span, destination_type);
		this.policy = policy;
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class CheckedFloatConversionExpression : CheckedExpression {
	public FloatConversionKind conversion_kind { get; private set; }
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CheckedExpression operand { get; private set; }

	internal CheckedFloatConversionExpression (SourceSpan span, SemanticType source_type, SemanticType destination_type, FloatConversionKind conversion_kind, CheckedExpression operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.conversion_kind = conversion_kind;
		this.operand = operand;
	}
}

public class CheckedIntegerConversionExpression : CheckedExpression {
	public SemanticType source_type { get; private set; }
	public SemanticType destination_type { get { return semantic_type; } }
	public CheckedExpression operand { get; private set; }

	internal CheckedIntegerConversionExpression (SourceSpan span, SemanticType source_type, SemanticType destination_type, CheckedExpression operand) {
		base (span, destination_type);
		this.source_type = source_type;
		this.operand = operand;
	}
}

public class CheckedVectorSplatExpression : CheckedExpression {
	public CheckedExpression operand { get; private set; }
	public int lane_count { get; private set; }
	public SourceSpan lane_count_span { get; private set; }

	internal CheckedVectorSplatExpression (SourceSpan span, SemanticType semantic_type, CheckedExpression operand, int lane_count, SourceSpan lane_count_span) {
		base (span, semantic_type);
		this.operand = operand;
		this.lane_count = lane_count;
		this.lane_count_span = lane_count_span;
	}
}

public class CheckedVectorExtractExpression : CheckedExpression {
	public CheckedExpression vector { get; private set; }
	public VectorLaneIndex index { get; private set; }

	internal CheckedVectorExtractExpression (SourceSpan span, SemanticType semantic_type, CheckedExpression vector, VectorLaneIndex index) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
	}
}

public class CheckedVectorInsertExpression : CheckedExpression {
	public CheckedExpression vector { get; private set; }
	public VectorLaneIndex index { get; private set; }
	public CheckedExpression replacement { get; private set; }

	internal CheckedVectorInsertExpression (SourceSpan span, SemanticType semantic_type, CheckedExpression vector, VectorLaneIndex index, CheckedExpression replacement) {
		base (span, semantic_type);
		this.vector = vector;
		this.index = index.copy ();
		this.replacement = replacement;
	}
}

public class CheckedVectorShuffleExpression : CheckedExpression {
	public CheckedExpression vector { get; private set; }
	public VectorLaneSelectors selectors { get; private set; }

	internal CheckedVectorShuffleExpression (SourceSpan span, SemanticType semantic_type, CheckedExpression vector, VectorLaneSelectors selectors) {
		base (span, semantic_type);
		this.vector = vector;
		this.selectors = selectors.copy ();
	}
}

public class CheckedVectorMemoryExpression : CheckedExpression {
	public VectorMemoryContract contract { get; private set; }
	public CheckedExpression view { get; private set; }
	public CheckedExpression offset { get; private set; }
	public CheckedExpression? stored { get; private set; }
	internal CheckedVectorMemoryExpression (SourceSpan span, VectorMemoryContract contract, CheckedExpression view, CheckedExpression offset, CheckedExpression? stored) {
		base (span, contract.vector_type);
		this.contract = contract.copy ();
		this.view = view;
		this.offset = offset;
		this.stored = stored;
	}
}

public class CheckedVectorMemoryStatement : CheckedStatement {
	public CheckedVectorMemoryExpression operation { get; private set; }
	internal CheckedVectorMemoryStatement (SourceSpan span, CheckedVectorMemoryExpression operation) {
		base (span);
		this.operation = operation;
	}
}

public class CheckedVectorSelectExpression : CheckedExpression {
	public CheckedExpression mask { get; private set; }
	public CheckedExpression true_value { get; private set; }
	public CheckedExpression false_value { get; private set; }

	internal CheckedVectorSelectExpression (SourceSpan span, SemanticType semantic_type, CheckedExpression mask, CheckedExpression true_value, CheckedExpression false_value) {
		base (span, semantic_type);
		this.mask = mask;
		this.true_value = true_value;
		this.false_value = false_value;
	}
}

public class CheckedVectorConstructExpression : CheckedExpression {
	public GenericArray<CheckedExpression> lanes { get; private set; }

	internal CheckedVectorConstructExpression (SourceSpan span, SemanticType semantic_type, GenericArray<CheckedExpression> lanes) {
		base (span, semantic_type);
		this.lanes = lanes;
	}
}

public class CheckedVectorReductionExpression : CheckedExpression {
	public VectorReductionOperator operator_kind { get; private set; }
	public CheckedExpression operand { get; private set; }

	internal CheckedVectorReductionExpression (SourceSpan span, SemanticType semantic_type, VectorReductionOperator operator_kind, CheckedExpression operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

public class CheckedFloatExpression : CheckedExpression {
	public BinaryFloatValue value { get; private set; }

	internal CheckedFloatExpression (SourceSpan span, SemanticType semantic_type, BinaryFloatValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class CheckedIntegerExpression : CheckedExpression {
	public AstraIntegerValue value { get; private set; }

	internal CheckedIntegerExpression (SourceSpan span, SemanticType semantic_type, AstraIntValue value) {
		base (span, semantic_type);
		this.value = value.in_type (semantic_type as IntegerType);
	}

	internal CheckedIntegerExpression.typed (SourceSpan span, SemanticType semantic_type, AstraIntegerValue value) {
		base (span, semantic_type);
		this.value = value;
	}
}

public class CheckedParameterReferenceExpression : CheckedExpression {
	public ParameterSymbol parameter { get; private set; }

	internal CheckedParameterReferenceExpression (SourceSpan span, ParameterSymbol parameter) {
		base (span, parameter.semantic_type);
		this.parameter = parameter;
	}
}

public class CheckedFieldReferenceExpression : CheckedExpression {
	public LocalSymbol local { get; private set; }
	public StructFieldSymbol field { get; private set; }

	internal CheckedFieldReferenceExpression (SourceSpan span, LocalSymbol local, StructFieldSymbol field) {
		base (span, field.semantic_type);
		this.local = local;
		this.field = field;
	}
}

public class CheckedLocalReferenceExpression : CheckedExpression {
	public LocalSymbol local { get; private set; }

	internal CheckedLocalReferenceExpression (SourceSpan span, LocalSymbol local) {
		base (span, local.semantic_type);
		this.local = local;
	}
}

public class CheckedPrefixExpression : CheckedExpression {
	public PrefixOperator operator_kind { get; private set; }
	public CheckedExpression operand { get; private set; }

	internal CheckedPrefixExpression (SourceSpan span, SemanticType semantic_type, PrefixOperator operator_kind, CheckedExpression operand) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.operand = operand;
	}
}

// Evaluates left first and right only on the required path.
public class CheckedShortCircuitExpression : CheckedExpression {
	public ShortCircuitOperator operator_kind { get; private set; }
	public CheckedExpression left { get; private set; }
	public CheckedExpression right { get; private set; }

	internal CheckedShortCircuitExpression (SourceSpan span, SemanticType semantic_type, ShortCircuitOperator operator_kind, CheckedExpression left, CheckedExpression right) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}
}

public class CheckedComparisonChain : CheckedExpression {
	public GenericArray<CheckedExpression> operands { get; private set; }
	public GenericArray<BinaryOperator> operators { get; private set; }
	public int operand_count { get; private set; }
	internal CheckedComparisonChain (SourceSpan span, SemanticType result, GenericArray<CheckedExpression> operands, GenericArray<BinaryOperator> operators) {
		base (span, result);
		this.operands = operands;
		this.operators = operators;
		this.operand_count = operands.length;
	}
}

public class CheckedBinaryExpression : CheckedExpression {
	public BinaryOperator operator_kind { get; private set; }
	public CheckedExpression left { get; private set; }
	public CheckedExpression right { get; private set; }

	internal CheckedBinaryExpression (SourceSpan span, SemanticType semantic_type, BinaryOperator operator_kind, CheckedExpression left, CheckedExpression right) {
		base (span, semantic_type);
		this.operator_kind = operator_kind;
		this.left = left;
		this.right = right;
	}
}

// Dereference denotes storage independently of its load/store context.
public abstract class CheckedPlace : CheckedNode {
	public SemanticType semantic_type { get; private set; }

	protected CheckedPlace (SourceSpan span, SemanticType semantic_type) {
		base (span);
		this.semantic_type = semantic_type;
	}
}

public class CheckedLocalPlace : CheckedPlace {
	public LocalSymbol local { get; private set; }
	internal CheckedLocalPlace (SourceSpan span, LocalSymbol local) {
		base (span, local.semantic_type);
		this.local = local;
	}
}

// One recursive projection; exact base and field identities define storage.
public class CheckedFieldPlace : CheckedPlace {
	public CheckedPlace aggregate { get; private set; }
	public StructFieldSymbol field { get; private set; }
	internal CheckedFieldPlace (SourceSpan span, CheckedPlace aggregate, StructFieldSymbol field) {
		base (span, field.semantic_type);
		this.aggregate = aggregate;
		this.field = field;
	}
	public StructLeafPath storage_path() {
		var fields = new GenericArray<CheckedFieldPlace> ();
		CheckedPlace place = this;
		while (place is CheckedFieldPlace) {
			fields.insert (0, (CheckedFieldPlace) place);
			place = ((CheckedFieldPlace) place).aggregate;
		}
		int count = fields.length;
		if (count <= 0) {
			error ("invalid checked field projection count");
		}
		int[] ordinals = new int[count];
		for (int i = 0; i < count; i++) {
			ordinals[i] = fields[i].field.ordinal;
		}
		return new StructLeafPath (ordinals, semantic_type);
	}
}

public class CheckedDereferencePlace : CheckedPlace {
	public CheckedExpression pointer { get; private set; }
	public BorrowProvenance provenance { get; private set; }

	internal CheckedDereferencePlace (SourceSpan span, CheckedExpression pointer) {
		base (span, ((TypedPointerType) pointer.semantic_type).pointee);
		assert (semantic_type.is_typed_data_pointee ());
		this.pointer = pointer;
		this.provenance = BorrowProvenance.for_expression (pointer);
	}
}

public class CheckedLoadExpression : CheckedExpression {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CheckedPlace source { get; private set; }

	internal CheckedLoadExpression (SourceSpan span, CheckedPlace source, VolatileAccessContract? access = null) {
		base (span, source.semantic_type);
		volatile_access = access;
		volatile_enabled = access != null;
		this.source = source;
	}
}

public class CheckedStore : CheckedStatement {
	public VolatileAccessContract? volatile_access { get; private set; }
	public bool volatile_enabled { get; internal set; }
	public CheckedPlace target { get; private set; }
	public CheckedExpression value { get; private set; }

	internal CheckedStore (SourceSpan span, CheckedPlace target, CheckedExpression value, VolatileAccessContract? access = null) {
		base (span);
		volatile_access = access;
		volatile_enabled = access != null;
		this.target = target;
		this.value = value;
	}
}

public class CheckedAddressOfExpression : CheckedExpression {
	public LocalSymbol local { get; private set; }

	internal CheckedAddressOfExpression (SourceSpan span, LocalSymbol local, TypedPointerType semantic_type) {
		base (span, semantic_type);
		this.local = local;
	}
}

public class CheckedIndirectFieldReference : CheckedExpression {
	// Exactly a checked parameter/local value reference, not pointee storage.
	public CheckedExpression pointer { get; private set; }
	public StructFieldSymbol field { get; private set; }

	internal CheckedIndirectFieldReference (SourceSpan span, CheckedExpression pointer, StructFieldSymbol field) {
		base (span, field.semantic_type);
		this.pointer = pointer;
		this.field = field;
	}
}

public class CheckedIndirectFieldAssignment : CheckedStatement {
	public CheckedExpression pointer { get; private set; }
	public StructFieldSymbol field { get; private set; }
	public CheckedExpression expression { get; private set; }

	internal CheckedIndirectFieldAssignment (SourceSpan span, CheckedExpression pointer, StructFieldSymbol field, CheckedExpression expression) {
		base (span);
		this.pointer = pointer;
		this.field = field;
		this.expression = expression;
	}
}
}

namespace Astra.Semantic {
public class CheckedFunctionAddress : CheckedExpression {
	private WeakRef callee;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) callee.get (); } }
	internal CheckedFunctionAddress (SourceSpan span, FunctionValueType type, FunctionSymbol target) {
		base (span, type);
		callee = WeakRef (target);
	}
}
public class CheckedFunctionValueCall : CheckedExpression, CheckedInvocation {
	public OwnedValueProducer? owned_producer { get; internal set; }
	public OwnedValueProducer? result_producer() {
		return owned_producer;
	}
	// Call-owned channel declarations; these are never function inputs or bodies.
	public GenericArray<ParameterSymbol> channel_parameters { get; private set; default = new GenericArray<ParameterSymbol> (); }
	public CheckedExpression callee { get; private set; }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedFunctionValueCall (SourceSpan span, FunctionValueType type, CheckedExpression callee, GenericArray<CheckedExpression> arguments) {
		base (span, type.result_type);
		this.callee = callee;
		this.arguments = arguments;
	}
}
}
