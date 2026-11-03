// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
// A finite, call-local proof. The owner and every pointer derived from it
// must remain in this activation; all original cleanup stays ordered in SSA.
public class SsaStackObjects : Object {
	private static bool scalar(SemanticType type) {
		return type.kind == TypeKind.BOOL || type is IntegerType || type is FloatingType || type is VectorType;
	}

	private static bool numeric_view(SemanticType? type) {
		return type is SliceType && !(type is ContextBytesType) && scalar (((SliceType) type).element_type);
	}

	private static bool local_buffer(SsaFunction function, SsaBufferPlace place) {
		return place.storage != null && function.buffer_storage.find (place.storage) && place.field == null && place.record_projection == null &&
		       place.storage.record_type == null && numeric_view (place.cleanup.buffer_type);
	}

	private static bool numeric_pair(SsaBufferPair pair) {
		return numeric_view (pair.shape.slice_type);
	}

	private static bool nocapture(SsaFunction? target) {
		return target != null && target.effect_facts != null && (target.effect_facts.flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) != 0;
	}

	internal static bool exact_root(SsaFunction function, SsaObjectStorage root) {
		return derive_root (function, root, true) != null;
	}

	private static SsaObjectStorage? derive_root(SsaFunction function, SsaObjectStorage root, bool exact_dispatch = false) {
		if (function.span.file.native_interface || function.implicit_receiver != null || function.async_body != null || function.enum_slots.length != 0) {
			return null;
		}
		// Incoming references predate this fresh allocation. They cannot alias
		// it unless one of its derived pointers is published; account for every
		// such use below instead of rejecting unrelated reference formals.
		foreach (var storage in function.buffer_storage) {
			if (storage.record_type != null || !numeric_view (storage.cleanup.buffer_type)) {
				return null;
			}
		}
		var owner = root.object_class;
		if (!root.heap_allocated || root.fallible || root.result_candidate || owner == null || owner.concurrency_policy != null || owner.allocation_policy != null || (!exact_dispatch && (owner.polymorphic || owner.parent_class != null)) || (owner.constructor != null && !nocapture (owner.constructor)) || (owner.destructor != null && !nocapture (owner.destructor))) {
			return null;
		}
		for (var parent = owner.parent_class; parent != null; parent = parent.parent_class) {
			if (parent.concurrency_policy != null || parent.allocation_policy != null) {
				return null;
			}
			foreach (var field in parent.fields) {
				if (!scalar (field.semantic_type) || field.owned_cleanup != null || field.slots_cleanup != null) {
					return null;
				}
			}
			foreach (var property in parent.properties) {
				if (property.is_lazy || !scalar (property.semantic_type)) {
					return null;
				}
			}
		}
		foreach (var field in owner.fields) {
			if (!scalar (field.semantic_type) || field.owned_cleanup != null || field.slots_cleanup != null) {
				return null;
			}
		}
		bool lazy = false;
		foreach (var property in owner.properties) {
			if (!property.is_lazy) {
				continue;
			}
			lazy = true;
			if (property.getter == null || property.getter.effect_facts == null || (property.getter.effect_facts.flags & FunctionEffectFacts.LAZY_READONLY_FACTORY) == 0) {
				return null;
			}
		}
		if (lazy && (owner.destructor != null || exact_dispatch)) {
			return null;
		}
		var aliases = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var receiver = instruction as SsaStorageReceiverInstruction;
				if (receiver != null && receiver.storage == root) {
					// Selected contexts have observable provider and exhaustion effects.
					if (receiver.allocation_context != null) {
						return null;
					}
					aliases.insert (instruction.result, true);
				}
				if (instruction is SsaObjectReferenceInstruction && ((SsaObjectReferenceInstruction) instruction).storage == root) {
					aliases.insert (instruction.result, true);
				}
			}
		}
		bool changed = false;
		do {
			uint before = aliases.size ();
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var validation = instruction as SsaObjectValidateInstruction;
					if (validation != null && aliases.contains (validation.reference)) {
						aliases.insert (validation.result, true);
					}
					var upcast = instruction as SsaClassUpcast;
					if (exact_dispatch && upcast != null && aliases.contains (upcast.reference)) {
						aliases.insert (upcast.result, true);
					}
				}
				if (exact_dispatch) {
					foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
						for (int p = 0; p < edge.arguments.length; p++) {
							if (aliases.contains (edge.arguments[p])) {
								aliases.insert (edge.target.parameters[p], true);
							}
						}
					}
				}
			}
			changed = aliases.size () != before;
		} while (changed);
		bool constructed = false;
		bool cleaned = false;
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				if (!scalar (parameter.semantic_type) && !numeric_view (parameter.semantic_type) && !(exact_dispatch && parameter.semantic_type is ClassType)) {
					return null;
				}
			}
			if (!(block.terminator is SsaBranch || block.terminator is SsaConditionalBranch || block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
				return null;
			}
			var returned = block.terminator as SsaReturn;
			if (returned != null && returned.value != null && aliases.contains (returned.value)) {
				return null;
			}
			foreach (var instruction in block.instructions) {
				if (exact_dispatch && instruction is SsaClassUpcast) {
					continue;
				}
				if (instruction is SsaStorageReceiverInstruction || instruction is SsaObjectReferenceInstruction || instruction is SsaObjectValidateInstruction) {
					continue;
				}
				var event = instruction as SsaHeapOwnerEvent;
				if (event != null) {
					if (aliases.contains (event.value) && event.action != SsaHeapOwnerAction.ACQUIRE && event.action != SsaHeapOwnerAction.END && event.action != SsaHeapOwnerAction.READ) {
						return null;
					}
					continue;
				}
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null) {
					if (aliases.contains (cleanup.value)) {
						if (!cleanup.cleanup.is_heap_object || cleanup.cleanup.object_class != owner) {
							return null;
						}
						cleaned = true;
					}
					continue;
				}
				var call = instruction as SsaCallInstruction;
				if (call != null) {
					var target = exact_dispatch ? exact_target (owner, call) : call.target;
					bool candidate_receiver = call.receiver != null && aliases.contains (call.receiver);
					if (candidate_receiver && (target == null || (!exact_dispatch && target.dispatch_kind != ClassDispatchKind.DIRECT) || target.async_body != null || target.throws_type != null || !nocapture (target))) {
						return null;
					}
					for (int p = 0; p < call.arguments.length; p++) {
						if (!aliases.contains (call.arguments[p])) {
							continue;
						}
						if (target == null || target.dispatch_kind != ClassDispatchKind.DIRECT || target.async_body != null || target.throws_type != null || target.effect_facts == null || (target.effect_facts.parameter (p) & 1) == 0 || call.result != null && !scalar (call.result.semantic_type) || lazy && (target.effect_facts.parameter (p) & 2) == 0) {
							return null;
						}
					}
					if (candidate_receiver && call.result != null && !scalar (call.result.semantic_type)) {
						return null;
					}
					var lifecycle = call as SsaLifecycleCallInstruction;
					if (lifecycle != null && lifecycle.storage == root) {
						if (!lifecycle.constructs || !candidate_receiver) {
							return null;
						}
						constructed = true;
					} else if (lazy && candidate_receiver && (call.target.effect_facts.flags & (FunctionEffectFacts.RECEIVER_READONLY | FunctionEffectFacts.LAZY_READONLY_FACTORY)) == 0) {
						return null;
					}
					continue;
				}
				var foreign = instruction as SsaCCallInstruction;
				if (foreign != null) {
					foreach (var argument in foreign.arguments) {
						if (!scalar (argument.semantic_type)) {
							return null;
						}
					}
					if (foreign.result != null && !scalar (foreign.result.semantic_type)) {
						return null;
					}
					continue;
				}
				// Checked result extraction carries no pointer from this allocation:
				// its call's receiver/arguments were independently accounted above.
				if (instruction is SsaCallSuccess) {
					continue;
				}
				var address = instruction as SsaAddressOfInstruction;
				if (address != null) {
					var local = address.target ?? (address.receiver_place == null ? null : address.receiver_place.root_storage ());
					if (local == null || !function.storage.find (local)) {
						return null;
					}
					continue;
				}
				// Numeric views and separate numeric buffer owners cannot contain
				// this fresh Class allocation. They may overlap each other: no
				// view alias, bounds, allocation, trap or ordering fact is changed.
				var allocation = instruction as SsaBufferAllocateInstruction;
				if (allocation != null) {
					if (!numeric_pair (allocation.pair) || allocation.allocation_context != null || allocation.failure != null) {
						return null;
					}
					continue;
				}
				var read_buffer = instruction as SsaBufferReadInstruction;
				if (read_buffer != null) {
					if (!local_buffer (function, read_buffer.place) || !numeric_pair (read_buffer.pair)) {
						return null;
					}
					continue;
				}
				var write_buffer = instruction as SsaBufferWriteInstruction;
				if (write_buffer != null) {
					if (!local_buffer (function, write_buffer.place) || !numeric_pair (write_buffer.pair)) {
						return null;
					}
					continue;
				}
				var release_buffer = instruction as SsaBufferDeallocateInstruction;
				if (release_buffer != null) {
					if (!numeric_pair (release_buffer.pair) || !numeric_view (release_buffer.cleanup.buffer_type)) {
						return null;
					}
					continue;
				}
				var borrow_buffer = instruction as SsaBufferBorrowInstruction;
				if (borrow_buffer != null) {
					if (!numeric_pair (borrow_buffer.pair) || !numeric_view (borrow_buffer.result.semantic_type)) {
						return null;
					}
					continue;
				}
				var slice = instruction as SsaSliceConstructInstruction;
				if (slice != null) {
					if (!scalar (slice.array_type.element_type) || !numeric_view (slice.result.semantic_type)) {
						return null;
					}
					continue;
				}
				var length = instruction as SsaSliceLengthInstruction;
				if (length != null) {
					if (!numeric_view (length.slice.semantic_type)) {
						return null;
					}
					continue;
				}
				var bounds = instruction as SsaSliceBoundsCheck;
				if (bounds != null) {
					if (!numeric_view (bounds.slice.semantic_type)) {
						return null;
					}
					continue;
				}
				var vector_memory = instruction as SsaVectorMemoryInstruction;
				if (vector_memory != null) {
					if (!numeric_view (vector_memory.view.semantic_type)) {
						return null;
					}
					continue;
				}
				var array = instruction as SsaArrayInitialize;
				if (array != null) {
					if (!(array.storage.semantic_type is ArrayType) || !scalar (((ArrayType) array.storage.semantic_type).element_type) || array.record_root != null) {
						return null;
					}
					foreach (var element in array.elements) {
						if (!scalar (element.semantic_type)) {
							return null;
						}
					}
					continue;
				}
				var array_bounds = instruction as SsaArrayBoundsCheck;
				if (array_bounds != null) {
					if (!(array_bounds.storage.semantic_type is ArrayType) || !scalar (((ArrayType) array_bounds.storage.semantic_type).element_type)) {
						return null;
					}
					continue;
				}
				var load = instruction as SsaLoadInstruction;
				if (load != null) {
					if (load.volatile_enabled || !scalar (load.result.semantic_type) || !place (load.source, root, aliases)) {
						return null;
					}
					continue;
				}
				var store = instruction as SsaStoreInstruction;
				if (store != null) {
					if (store.volatile_enabled || !scalar (store.value.semantic_type) || !place (store.target, root, aliases) || (lazy && !(store.target is SsaLocalMemoryPlace))) {
						return null;
					}
					continue;
				}
				var binary = instruction as SsaBinaryInstruction;
				if (binary != null && (aliases.contains (binary.left) || aliases.contains (binary.right))) {
					return null;
				}
				if (instruction is SsaInitializeInstruction) {
					var target = ((SsaInitializeInstruction) instruction).target;
					if (!scalar (target.semantic_type) || (lazy && !(target is SsaLocalMemoryPlace))) {
						return null;
					}
					continue;
				}
				if (!(instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorDotInstruction || instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction || instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction || instruction is SsaVectorReductionInstruction)) {
					return null;
				}
				if (instruction.result != null && !scalar (instruction.result.semantic_type)) {
					return null;
				}
			}
		}
		return (owner.constructor == null || constructed) && cleaned ? root : null;
	}

	public static SsaFunction? exact_target(SsaClass owner, SsaCallInstruction call) {
		var target = call.target;
		if (target == null || target.dispatch_kind == ClassDispatchKind.DIRECT) {
			return target;
		}
		return target.virtual_slot >= 0 && target.virtual_slot < owner.virtual_entries.length ? owner.virtual_entries[target.virtual_slot] : null;
	}

	private static bool place(SsaMemoryPlace place, SsaObjectStorage root, HashTable<SsaValue, bool> aliases) {
		if (place is SsaLocalMemoryPlace) {
			return scalar (place.semantic_type);
		}
		if (place.root_storage () != null) {
			return scalar (place.semantic_type);
		}
		var slice = place as SsaSliceElementPlace;
		if (slice != null) {
			return numeric_view (slice.slice.semantic_type) && !aliases.contains (slice.slice);
		}
		var array = place as SsaArrayElementPlace;
		if (array != null) {
			return scalar (array.array_type.element_type);
		}
		var field = place as SsaIndirectFieldPlace;
		if (field != null) {
			return aliases.contains (field.pointer);
		}
		var direct = place as SsaObjectFieldPlace;
		return direct != null && direct.storage == root;
	}

	public static void annotate(SsaProgram program) {
		foreach (var function in program.functions) {
			foreach (var root in function.object_storage) {
				if (derive_root (function, root) != null) {
					function.stack_objects.add (root);
				}
			}
		}
	}

	public static void verify(SsaProgram program) throws SsaError {
		SsaStackObjectVerifier.verify (program);
	}

}
}
