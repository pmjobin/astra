// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaClosureBind : SsaInstruction {
	public ActorBindingSpec? actor_binding { get; private set; }
	public SsaValue environment { get; private set; }
	private WeakRef code;
	public SsaFunction? target { owned get { return (SsaFunction?) code.get (); } }
	public SsaCleanupContract cleanup { get; private set; }
	internal SsaClosureBind (SourceSpan span, ClosureHandleType type, SsaValue environment, SsaFunction target, SsaCleanupContract cleanup, int ordinal, ActorBindingSpec? actor_binding = null) {
		base (span, type, ordinal);
		this.environment = environment;
		code = WeakRef (target);
		this.cleanup = cleanup;
		this.actor_binding = actor_binding == null ? null : actor_binding.copy ();
	}

}
public class SsaClosureCall : SsaInstruction, SsaCallableInvocation {
	public SsaStructCallResults? struct_result { get; internal set; }
	public SsaCleanupContract? owned_cleanup { get; private set; }
	public SsaCleanupContract? result_cleanup() {
		return owned_cleanup;
	}

	private WeakRef success_identity;
	public SsaClosureCallSuccess? owned_success { owned get { return (SsaClosureCallSuccess?) success_identity.get (); } internal set { success_identity = WeakRef (value); } }
	public SsaValue? owned_result_value() {
		return ((ClosureHandleType) callee.semantic_type).throws_type == null ? result : owned_success == null ? null : owned_success.result;
	}

	private GenericArray<SsaStructBoundaryMove> record_transfers = new GenericArray<SsaStructBoundaryMove> ();
	public GenericArray<SsaStructBoundaryMove> record_moves { get { return record_transfers; } }
	private GenericArray<SsaCallableOwnedArgument> argument_transfers = new GenericArray<SsaCallableOwnedArgument> ();
	public GenericArray<SsaCallableOwnedArgument> owned_arguments { get { return argument_transfers; } }
	private GenericArray<SsaOwnedArgumentReservation> argument_reservations = new GenericArray<SsaOwnedArgumentReservation> ();
	public GenericArray<SsaOwnedArgumentReservation> reservations { get { return argument_reservations; } }
	public GenericArray<StructBoundaryGroup> struct_arguments { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	private GenericArray<SsaCallableBorrowArgument> argument_loans = new GenericArray<SsaCallableBorrowArgument> ();
	public GenericArray<SsaCallableBorrowArgument> borrowed_arguments { get { return argument_loans; } }
	public SsaHeapOwner? source_owner { get; private set; }
	public SsaValue callee { get; private set; }
	private GenericArray<SsaValue> call_arguments;
	public GenericArray<SsaValue> arguments { get { return call_arguments; } }
	internal SsaClosureCall (SourceSpan span, ClosureHandleType type, SsaValue callee, GenericArray<SsaValue> arguments, int ordinal, SsaHeapOwner? source_owner = null, ClassType? exception_root = null, SsaCleanupContract? owned_cleanup = null) {
		base (span, type.throws_type == null ? (type.result_type.kind == TypeKind.VOID || type.result_type.is_struct_storage () ? null : type.result_type) : exception_root, ordinal);
		this.callee = callee;
		this.call_arguments = arguments;
		this.source_owner = source_owner;
		this.owned_cleanup = owned_cleanup;
	}

}
public class SsaClosureCallSuccess : SsaInstruction {
	public SsaStructCallResults? struct_result { get; internal set; }
	public SsaClosureCall call { get; private set; }
	internal SsaClosureCallSuccess (SourceSpan span, SsaClosureCall call, int ordinal) {
		base (span, ((ClosureHandleType) call.callee.semantic_type).result_type.kind == TypeKind.VOID || ((ClosureHandleType) call.callee.semantic_type).result_type.is_struct_storage () ? null : ((ClosureHandleType) call.callee.semantic_type).result_type, ordinal);
		this.call = call;
		call.owned_success = this;
	}

}

}
namespace Astra.Ssa {
public class SsaActorSend : SsaInstruction {
	public ActorAction action { get; private set; }
	public SsaValue sender { get; private set; }
	public SsaValue? message { get; private set; }
	public ClassType error_type { get; private set; }
	public SsaHeapOwner? sender_owner { get; private set; }
	public SsaHeapOwner? message_owner { get; private set; }
	internal SsaActorSend (SourceSpan span, ActorAction action, SsaValue sender, SsaValue? message, ClassType error_type, int ordinal, SsaHeapOwner? sender_owner, SsaHeapOwner? message_owner) {
		base (span, error_type, ordinal);
		this.action = action;
		this.sender = sender;
		this.message = message;
		this.error_type = error_type;
		this.sender_owner = sender_owner;
		this.message_owner = message_owner;
	}

}
}
