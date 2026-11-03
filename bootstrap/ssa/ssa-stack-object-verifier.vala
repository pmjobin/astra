// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
// Consumer-side reconstruction: follow definitions backwards, then solve
// allocation/construction/cleanup state on reachable control-flow edges.
// This checker does not call the producer's candidate or alias derivation.
internal class SsaStackObjectVerifier : Object {
	private SsaFunction function;
	private SsaObjectStorage root;
	private HashTable<SsaValue, SsaInstruction> definitions = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaValue, bool> origins = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
	private bool lazy;
	private bool exact;
	private const int DEAD = 1;
	private const int CONSTRUCTING = 2;
	private const int LIVE = 4;

	private SsaStackObjectVerifier (SsaFunction function, SsaObjectStorage root, bool exact = false) {
		this.function = function;
		this.root = root;
		this.exact = exact;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction.result != null) {
					definitions.insert (instruction.result, instruction);
				}
			}
		}
	}

	private static void require(bool condition, string reason) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("stack object checker: " + reason);
		}
	}

	private static bool scalar(SemanticType type) {
		return type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType || type is VectorType;
	}

	private static bool view(SemanticType? type) {
		var slice = type as SliceType;
		return slice != null && !(slice is ContextBytesType) && scalar (slice.element_type);
	}

	private void pair(SsaBufferPair pair) throws SsaError {
		require (view (pair.shape.slice_type) && pair.base_value.semantic_type == pair.shape.base_type &&
			pair.length_value.semantic_type == pair.shape.length_type && !rooted (pair.base_value), "buffer pair exposes a Class root");
	}

	private void buffer_place(SsaBufferPlace place) throws SsaError {
		require (place.field == null && place.record_projection == null && place.storage != null &&
			function.buffer_storage.find (place.storage) && place.storage.record_type == null &&
			view (place.cleanup.buffer_type), "buffer place is not separate numeric local storage");
	}

	private static bool no_capture(SsaFunction? target) {
		return target != null && target.effect_facts != null &&
			   (target.effect_facts.flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) != 0;
	}

	private bool rooted(SsaValue? value) throws SsaError {
		if (value == null) {
			return false;
		}
		if (origins.contains (value)) {
			return origins.lookup (value);
		}
		var pending = new GenericArray<SsaValue> ();
		pending.add (value);
		var seen = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		bool result = false;
		for (int index = 0; index < pending.length; index++) {
			var current = pending[index];
			if (seen.contains (current)) {
				continue;
			}
			seen.insert (current, true);
			var definition = definitions.lookup (current);
			if (definition is SsaObjectValidateInstruction) {
				pending.add (((SsaObjectValidateInstruction) definition).reference);
				continue;
			}
			if (definition is SsaClassUpcast) {
				pending.add (((SsaClassUpcast) definition).reference);
				continue;
			}
			if (exact && current is SsaBlockParameter) {
				foreach (var block in function.blocks) {
					foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
						for (int p = 0; p < edge.target.parameters.length; p++) {
							if (edge.target.parameters[p] == current) {
								pending.add (edge.arguments[p]);
							}
						}
					}
				}
				continue;
			}
			var receiver = definition as SsaStorageReceiverInstruction;
			var reference = definition as SsaObjectReferenceInstruction;
			result = receiver != null && receiver.storage == root || reference != null && reference.storage == root;
			if (result) {
				break;
			}
		}
		origins.insert (value, result);
		return result;
	}

	private SsaFunction? target(SsaCallInstruction call) {
		var declared = call.target;
		if (!exact || declared == null || declared.dispatch_kind == ClassDispatchKind.DIRECT) {
			return declared;
		}
		int slot = declared.virtual_slot;
		return slot >= 0 && slot < root.object_class.virtual_entries.length ? root.object_class.virtual_entries[slot] : null;
	}

	private bool local_place(SsaMemoryPlace place) throws SsaError {
		if (place is SsaLocalMemoryPlace) {
			return scalar (place.semantic_type);
		}
		var storage = place.root_storage ();
		if (storage != null) {
			return function.storage.find (storage) && scalar (place.semantic_type);
		}
		var element = place as SsaSliceElementPlace;
		if (element != null) {
			return view (element.slice.semantic_type) && !rooted (element.slice);
		}
		var array = place as SsaArrayElementPlace;
		if (array != null) {
			return scalar (array.array_type.element_type);
		}
		var direct = place as SsaObjectFieldPlace;
		if (direct != null) {
			return direct.storage == root;
		}
		var indirect = place as SsaIndirectFieldPlace;
		return indirect != null && rooted (indirect.pointer);
	}

	private void domain() throws SsaError {
		var owner = root.object_class;
		require (function.object_storage.find (root) && root.heap_allocated && !root.fallible && !root.result_candidate,
			"root is not a complete eligible lexical allocation");
		require (!function.span.file.native_interface && function.implicit_receiver == null && function.async_body == null &&
			function.enum_slots.length == 0,
			"unproved function domain");
		require (owner != null && owner.concurrency_policy == null && owner.allocation_policy == null &&
			(exact || !owner.polymorphic && owner.parent_class == null), "observable allocation or dynamic owner policy");
		require ((owner.constructor == null || no_capture (owner.constructor)) &&
			(owner.destructor == null || no_capture (owner.destructor)), "lifecycle may capture the allocation");
		// The checked lifecycle establishes a fresh root. Reverse definitions
		// and use obligations below must reject its publication/capture even
		// when this activation also receives independent reference arguments.
		foreach (var storage in function.buffer_storage) {
			require (storage.record_type == null && view (storage.cleanup.buffer_type), "unproved buffer storage domain");
		}
		foreach (var field in owner.fields) {
			require (scalar (field.semantic_type) && field.owned_cleanup == null && field.slots_cleanup == null,
				"field has unproved storage or cleanup");
		}
		for (var parent = owner.parent_class; parent != null; parent = parent.parent_class) {
			require (parent.concurrency_policy == null && parent.allocation_policy == null, "unproved inherited runtime policy");
			foreach (var field in parent.fields) {
				require (scalar (field.semantic_type) && field.owned_cleanup == null && field.slots_cleanup == null, "unproved inherited storage");
			}
			foreach (var property in parent.properties) {
				require (!property.is_lazy && scalar (property.semantic_type), "unproved inherited property state");
			}
		}
		foreach (var property in owner.properties) {
			if (!property.is_lazy) {
				continue;
			}
			lazy = true;
			require (property.getter != null && property.getter.effect_facts != null &&
				(property.getter.effect_facts.flags & FunctionEffectFacts.LAZY_READONLY_FACTORY) != 0,
				"lazy factory has unproved effects");
		}
		require (!lazy || owner.destructor == null && !exact, "observable lazy destruction or dispatch");
	}

	private void uses() throws SsaError {
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				require (scalar (parameter.semantic_type) || view (parameter.semantic_type) || exact && parameter.semantic_type is ClassType, "unproved block argument");
			}
			require (block.terminator is SsaBranch || block.terminator is SsaConditionalBranch ||
				block.terminator is SsaReturn || block.terminator is SsaFunctionEnd, "unproved control transfer");
			var returned = block.terminator as SsaReturn;
			require (returned == null || !rooted (returned.value), "returned allocation");
			foreach (var instruction in block.instructions) {
				if (exact && instruction is SsaClassUpcast) {
					continue;
				}
				var receiver = instruction as SsaStorageReceiverInstruction;
				if (receiver != null) {
					require (receiver.storage != root || receiver.allocation_context == null, "selected allocator context");
					continue;
				}
				if (instruction is SsaObjectReferenceInstruction || instruction is SsaObjectValidateInstruction) {
					continue;
				}
				var owner_event = instruction as SsaHeapOwnerEvent;
				if (owner_event != null) {
					require (!rooted (owner_event.value) || owner_event.action == SsaHeapOwnerAction.ACQUIRE ||
						owner_event.action == SsaHeapOwnerAction.READ || owner_event.action == SsaHeapOwnerAction.END,
						"transferred or published allocation");
					continue;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null) {
					require (!rooted (cleanup.value) || cleanup.cleanup.is_heap_object && cleanup.cleanup.object_class == root.object_class,
						"cleanup belongs to a different allocation kind");
					continue;
				}
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					var callee = target (call);
					bool receiver_use = rooted (call.receiver);
					if (receiver_use) {
						require (no_capture (callee) && (exact || callee.dispatch_kind == ClassDispatchKind.DIRECT) &&
							callee.async_body == null && callee.throws_type == null, "unproved receiver callee");
						require (call.result == null || scalar (call.result.semantic_type), "callee exposes a derived address");
					}
					for (int p = 0; p < call.arguments.length; p++) {
						if (!rooted (call.arguments[p])) {
							continue;
						}
						require (callee != null && callee.dispatch_kind == ClassDispatchKind.DIRECT && callee.async_body == null && callee.throws_type == null && callee.effect_facts != null && (callee.effect_facts.parameter (p) & 1) != 0, "unproved argument capture boundary");
						require (call.result == null || scalar (call.result.semantic_type), "argument callee exposes a derived address");
						require (!lazy || (callee.effect_facts.parameter (p) & 2) != 0, "argument callee can mutate lazy dependencies");
					}
					var construction = call as SsaLifecycleCallInstruction;
					if (construction != null && construction.storage == root) {
						require (receiver_use && construction.constructs && construction.target == root.object_class.constructor,
							"constructor/root correspondence");
					} else if (lazy && receiver_use) {
						require ((callee.effect_facts.flags & (FunctionEffectFacts.RECEIVER_READONLY |
							FunctionEffectFacts.LAZY_READONLY_FACTORY)) != 0, "mutable lazy receiver");
					}
					continue;
				}
				var foreign = instruction as SsaCCallInstruction;
				if (foreign != null) {
					foreach (var argument in foreign.arguments) {
						require (scalar (argument.semantic_type), "foreign pointer argument");
					}
					require (foreign.result == null || scalar (foreign.result.semantic_type), "foreign pointer result");
					continue;
				}
				var load = instruction as SsaLoadInstruction;
				if (instruction is SsaCallSuccess) {
					var success = (SsaCallSuccess) instruction;
					require (!rooted (success.call.receiver), "checked receiver effects are unproved");
					foreach (var argument in success.call.arguments) {
						require (!rooted (argument), "allocation crosses checked argument boundary");
					}
					continue;
				}
				var address = instruction as SsaAddressOfInstruction;
				if (address != null) {
					var storage = address.target;
					if (storage == null && address.receiver_place != null) {
						storage = address.receiver_place.root_storage ();
					}
					require (storage != null && function.storage.find (storage), "address is not separate function-local storage");
					continue;
				}
				var allocation = instruction as SsaBufferAllocateInstruction;
				if (allocation != null) {
					pair (allocation.pair);
					require (allocation.allocation_context == null && allocation.context_owner == null && allocation.failure == null,
						"unproved selected allocator or failure region");
					continue;
				}
				var buffer_read = instruction as SsaBufferReadInstruction;
				if (buffer_read != null) {
					buffer_place (buffer_read.place);
					pair (buffer_read.pair);
					continue;
				}
				var buffer_write = instruction as SsaBufferWriteInstruction;
				if (buffer_write != null) {
					buffer_place (buffer_write.place);
					pair (buffer_write.pair);
					continue;
				}
				var buffer_release = instruction as SsaBufferDeallocateInstruction;
				if (buffer_release != null) {
					pair (buffer_release.pair);
					require (view (buffer_release.cleanup.buffer_type), "unproved buffer cleanup");
					continue;
				}
				var buffer_borrow = instruction as SsaBufferBorrowInstruction;
				if (buffer_borrow != null) {
					pair (buffer_borrow.pair);
					require (view (buffer_borrow.result.semantic_type), "borrow is not numeric");
					continue;
				}
				var slice = instruction as SsaSliceConstructInstruction;
				if (slice != null) {
					require (function.storage.find (slice.storage) && scalar (slice.array_type.element_type) &&
						view (slice.result.semantic_type), "unproved array view origin");
					continue;
				}
				var length = instruction as SsaSliceLengthInstruction;
				if (length != null) {
					require (view (length.slice.semantic_type) && !rooted (length.slice), "unproved view length");
					continue;
				}
				var bounds = instruction as SsaSliceBoundsCheck;
				if (bounds != null) {
					require (view (bounds.slice.semantic_type) && !rooted (bounds.slice), "unproved view bounds");
					continue;
				}
				var vector_memory = instruction as SsaVectorMemoryInstruction;
				if (vector_memory != null) {
					require (view (vector_memory.view.semantic_type) && !rooted (vector_memory.view) &&
						(vector_memory.stored == null || scalar (vector_memory.stored.semantic_type)), "vector access can expose a root");
					continue;
				}
				var array = instruction as SsaArrayInitialize;
				if (array != null) {
					require (array.storage.semantic_type is ArrayType && scalar (((ArrayType) array.storage.semantic_type).element_type) &&
						array.record_root == null, "unproved array initialization");
					foreach (var element in array.elements) {
						require (scalar (element.semantic_type), "array exposes a root");
					}
					continue;
				}
				var array_bounds = instruction as SsaArrayBoundsCheck;
				if (array_bounds != null) {
					require (array_bounds.storage.semantic_type is ArrayType && scalar (((ArrayType) array_bounds.storage.semantic_type).element_type),
						"unproved array bounds");
					continue;
				}
				if (load != null) {
					require (!load.volatile_enabled && scalar (load.result.semantic_type) && local_place (load.source), "unproved load");
					continue;
				}
				var store = instruction as SsaStoreInstruction;
				if (store != null) {
					require (!store.volatile_enabled && scalar (store.value.semantic_type) && local_place (store.target) &&
						(!lazy || store.target is SsaLocalMemoryPlace), "unproved store");
					continue;
				}
				var initial = instruction as SsaInitializeInstruction;
				if (initial != null) {
					require (scalar (initial.target.semantic_type) && scalar (initial.value.semantic_type) &&
						(!lazy || initial.target is SsaLocalMemoryPlace), "unproved initializer");
					continue;
				}
				var binary = instruction as SsaBinaryInstruction;
				require (binary == null || !rooted (binary.left) && !rooted (binary.right), "identity observation");
				require (instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction ||
					instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction ||
					instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction ||
					instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction ||
					instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction ||
					instruction is SsaVectorReductionInstruction, "unknown instruction effect");
				require (instruction.result == null || scalar (instruction.result.semantic_type), "unproved scalar result");
			}
		}
	}

	private void lifetime() throws SsaError {
		var incoming = new HashTable<SsaBlock, int> (direct_hash, direct_equal);
		var pending = new GenericArray<SsaBlock> ();
		incoming.insert (function.entry, DEAD);
		pending.add (function.entry);
		for (int index = 0; index < pending.length; index++) {
			var block = pending[index];
			int state = incoming.lookup (block);
			foreach (var instruction in block.instructions) {
				var allocation = instruction as SsaStorageReceiverInstruction;
				if (allocation != null && allocation.storage == root) {
					require (state == DEAD, "allocation overlaps a prior live instance");
					state = root.object_class.constructor == null ? LIVE : CONSTRUCTING;
				}
				var construction = instruction as SsaLifecycleCallInstruction;
				if (construction != null && construction.storage == root) {
					require (state == CONSTRUCTING, "construction is not reached from allocation");
					state = LIVE;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null && rooted (cleanup.value)) {
					require (state == LIVE, "cleanup lacks exactly one constructed live allocation");
					state = DEAD;
				}
			}
			var successors = block.terminator.successors ();
			if (successors.length == 0) {
				require (state == DEAD, "exit bypasses constructed allocation cleanup");
			}
			foreach (var next in successors) {
				require (function.blocks.find (next), "foreign control-flow edge");
				int merged = incoming.lookup (next) | state;
				if (merged != incoming.lookup (next)) {
					incoming.insert (next, merged);
					pending.add (next);
				}
			}
		}
	}

	internal static void verify(SsaProgram program) throws SsaError {
		foreach (var function in program.functions) {
			var seen = new HashTable<SsaObjectStorage, bool> (direct_hash, direct_equal);
			foreach (var root in function.stack_objects) {
				require (!seen.contains (root), "duplicate allocation proof");
				seen.insert (root, true);
				var checker = new SsaStackObjectVerifier (function, root);
				checker.domain ();
				checker.uses ();
				checker.lifetime ();
			}
		}
	}

	internal static void verify_exact_root(SsaFunction function, SsaObjectStorage root) throws SsaError {
		var checker = new SsaStackObjectVerifier (function, root, true);
		checker.domain ();
		checker.uses ();
		checker.lifetime ();
	}

}
}
