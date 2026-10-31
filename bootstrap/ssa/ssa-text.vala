// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Ssa {
public class SsaUtf8FactoryInstruction : SsaInstruction {
	public SsaFunctionParameter input { get; private set; }
	public bool validates { get; private set; }
	internal SsaUtf8FactoryInstruction (SourceSpan span, SemanticType type, SsaFunctionParameter input, bool validates, int ordinal) {
		base (span, type, ordinal);
		this.input = input;
		this.validates = validates;
	}
}
internal class SsaUtf8FactoryAuthority : Object {
	private static void require(bool valid) throws SsaError {
		if (!valid) {
			throw new SsaError.INVALID_SSA ("UTF-8 factory lost exact validation dominance, byte group, copy or checked-error authority");
		}
	}
	private static void snapshot_constructor(SsaClass owner) throws SsaError {
		var ctor = owner.constructor;
		require (ctor != null && ctor.parameters.length == 1 && ctor.parameters[0].semantic_type is StringType && ctor.blocks.length == 1 && ctor.entry.instructions.length == 1);
		var init = ctor.entry.instructions[0] as SsaInitializeInstruction;
		var place = init == null ? null : init.target as SsaIndirectFieldPlace;
		require (place != null && place.field == owner.fields[0] && place.pointer == ctor.receiver && init.value == ctor.parameters[0]);
	}
	private static void snapshot_getter(SsaClass owner) throws SsaError {
		require (owner.properties.length == 1);
		var getter = owner.properties[0].getter;
		require (getter.blocks.length == 1 && getter.entry.instructions.length == 1);
		var load = getter.entry.instructions[0] as SsaLoadInstruction;
		var place = load == null ? null : load.source as SsaIndirectFieldPlace;
		var returned = getter.entry.terminator as SsaReturn;
		require (place != null && place.field == owner.fields[0] && returned != null && returned.value == load.result);
	}
	internal static HashTable<SsaUtf8FactoryInstruction, SsaFunction> authorize(SsaProgram program) throws SsaError {
		var allowed = new HashTable<SsaUtf8FactoryInstruction, SsaFunction> (direct_hash, direct_equal);
		int count = 0;
		foreach (var function in program.functions) {
			if (!function.utf8_factory) {
				continue;
			}
			require (++count == 1 && function.kind == CallableKind.FUNCTION && function.async_body == null && function.heap_result && function.owned_cleanup != null && function.owned_cleanup.is_heap_object && function.parameters.length == 1 && function.blocks.length == 3 && function.entry.instructions.length == 1);
			var input = function.parameters[0];
			var slice = input.semantic_type as SliceType;
			require (slice != null && slice.element_type.kind == TypeKind.U8 && input.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
			var test = function.entry.instructions[0] as SsaUtf8FactoryInstruction;
			var branch = function.entry.terminator as SsaConditionalBranch;
			require (test != null && test.validates && test.input == input && test.result != null && test.result.semantic_type.kind == TypeKind.BOOL && branch != null && branch.condition == test.result && branch.true_edge.target != null && branch.false_edge.target != null && function.blocks.find (branch.true_edge.target) && function.blocks.find (branch.false_edge.target) && branch.true_edge.target != branch.false_edge.target && branch.true_edge.target != function.entry && branch.false_edge.target != function.entry);
			var success_block = branch.true_edge.target;
			var failure_block = branch.false_edge.target;
			require (success_block.terminator is SsaReturn && !(success_block.terminator is SsaExceptionReturn) && failure_block.terminator is SsaExceptionReturn);
			require (success_block.instructions.length == 8 && failure_block.instructions.length == 10);
			SsaLifecycleCallInstruction? success = null;
			SsaLifecycleCallInstruction? failure = null;
			SsaUtf8FactoryInstruction? text = null;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					require (instruction is SsaStorageReceiverInstruction || instruction is SsaUtf8FactoryInstruction || instruction is SsaLifecycleCallInstruction || instruction is SsaObjectReferenceInstruction || instruction is SsaHeapOwnerEvent || instruction is SsaCleanupInstruction || instruction is SsaExceptionTransfer || instruction is SsaExceptionStamp || instruction is SsaClassUpcast);
					if (instruction is SsaUtf8FactoryInstruction && instruction != test) {
						require (text == null && block == success_block);
						text = (SsaUtf8FactoryInstruction) instruction;
					}
					if (instruction is SsaCallInstruction) {
						var call = instruction as SsaLifecycleCallInstruction;
						require (call != null && call.constructs);
						if (block == success_block) {
							require (success == null);
							success = call;
						} else {
							require (block == failure_block && failure == null);
							failure = call;
						}
					}
				}
			}
			require (success != null && failure != null && success.storage.heap_allocated && failure.storage.heap_allocated && success.storage.semantic_type == function.return_type && failure.storage.semantic_type == function.throws_type && success.arguments.length == 1 && failure.arguments.length == 0 && text != null && !text.validates && text.input == input && text.result != null && text.result.semantic_type is StringType && success.arguments[0] == text.result);
			var message = ((SsaConstructor) success.target).declaring_class;
			var error = ((SsaConstructor) failure.target).declaring_class;
			require (message != null && error != null && message.parent_class == null && message.fields.length == 1 && message.fields[0].text_snapshot && message.methods.length == 0 && message.properties.length == 1 && error.fields.length == 0 && error.parent_class != null && error.parent_class.exception_root && error.parent_class.fields.length == 1 && error.parent_class.fields[0].text_snapshot);
			snapshot_constructor (message);
			snapshot_constructor (error.parent_class);
			snapshot_getter (message);
			snapshot_getter (error.parent_class);
			var ctor = error.constructor;
			require (ctor.parameters.length == 0 && ctor.blocks.length == 1 && ctor.entry.instructions.length == 2);
			var call = ctor.entry.instructions[1] as SsaBaseLifecycleCall;
			var diagnostic = call == null || call.arguments.length != 1 ? null : call.arguments[0] as SsaTextConstant;
			require (call != null && call.target == error.parent_class.constructor && diagnostic != null && diagnostic.payload.hex () == "696e76616c6964205554462d38");
			allowed.insert (test, function);
			allowed.insert (text, function);
		}
		return allowed;
	}
}

public class SsaTextLoan : Object {
	public int local_ordinal { get; private set; }
	public TextLoanExtent extent { get; private set; }
	internal SsaTextLoan (int local_ordinal, TextLoanExtent extent) {
		this.local_ordinal = local_ordinal;
		this.extent = extent;
	}
}
public class SsaTextLoanBind : SsaInstruction {
	public SsaTextLoan loan { get; private set; }
	public SsaValue value { get; private set; }
	public TextLoanIntent intent { get; private set; }
	internal SsaTextLoanBind (SourceSpan span, SsaTextLoan loan, SsaValue value, TextLoanIntent intent) {
		base (span, null, -1);
		this.loan = loan;
		this.value = value;
		this.intent = intent;
	}
}
public class SsaTextLoanEnd : SsaInstruction {
	public TextLoanIntent exit_authority { get; private set; }
	public SsaTextLoan loan { get; private set; }
	internal SsaTextLoanEnd (SourceSpan span, SsaTextLoan loan, TextLoanIntent exit_authority) {
		base (span, null, -1);
		this.loan = loan;
		this.exit_authority = exit_authority;
	}
}
public class SsaTextLoanUse : SsaInstruction {
	public SsaTextLoan loan { get; private set; }
	public SsaValue value { get; private set; }
	internal SsaTextLoanUse (SourceSpan span, SsaTextLoan loan, SsaValue value) {
		base (span, null, -1);
		this.loan = loan;
		this.value = value;
	}
}

public class SsaTextSnapshotDestroy : SsaInstruction {
	public SsaIndirectFieldPlace field { get; private set; }
	internal SsaTextSnapshotDestroy (SourceSpan span, SsaIndirectFieldPlace field) {
		base (span, null, -1);
		this.field = field;
	}
}

// StringType is an indivisible bounded text group. There is no operation
// projecting a source-visible base, nor any generic aggregate SSA value.
public class SsaTextConstant : SsaValue {
	public TextBytes payload { get; private set; }
	internal SsaTextConstant (SourceSpan span, SemanticType type, TextBytes payload) {
		base (span, type);
		this.payload = payload;
	}
}
public class SsaTextLengthInstruction : SsaInstruction {
	public SsaValue receiver { get; private set; }
	internal SsaTextLengthInstruction (SourceSpan span, SemanticType type, SsaValue receiver, int ordinal) {
		base (span, type, ordinal);
		this.receiver = receiver;
	}
}
}
