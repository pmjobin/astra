// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Ssa {
internal class SsaReceiverOrigins : Object {
	internal bool unknown;
	internal GenericArray<SsaObjectStorage> roots = new GenericArray<SsaObjectStorage> ();
	internal bool include(SsaReceiverOrigins other) {
		bool changed = !unknown && other.unknown;
		unknown |= other.unknown;
		foreach (var root in other.roots) {
			if (!roots.find (root)) {
				roots.add (root);
				changed = true;
			}
		}
		return changed;
	}

}
public class SsaExactCalls : Object {
	private static SsaReceiverOrigins value(HashTable<SsaValue, SsaReceiverOrigins> origins, SsaValue? value) {
		var found = value == null ? null : origins.lookup (value);
		if (found != null) {
			return found;
		}
		var unknown = new SsaReceiverOrigins ();
		unknown.unknown = true;
		return unknown;
	}

	// Producer: propagate finite sets of lexical allocation identities forward.
	// A merge keeps exact type authority only if every origin has that class.
	private static HashTable<SsaValue, SsaReceiverOrigins> derive(SsaFunction function) {
		var origins = new HashTable<SsaValue, SsaReceiverOrigins> (direct_hash, direct_equal);
		foreach (var parameter in function.parameters) {
			var input = new SsaReceiverOrigins ();
			input.unknown = true;
			origins.insert (parameter, input);
		}
		if (function.implicit_receiver != null) {
			var input = new SsaReceiverOrigins ();
			input.unknown = true;
			origins.insert (function.implicit_receiver, input);
		}
		foreach (var block in function.blocks) {
			foreach (var parameter in block.parameters) {
				origins.insert (parameter, new SsaReceiverOrigins ());
			}
			foreach (var instruction in block.instructions) {
				if (instruction.result == null) {
					continue;
				}
				var result = new SsaReceiverOrigins ();
				var reference = instruction as SsaObjectReferenceInstruction;
				var receiver = instruction as SsaStorageReceiverInstruction;
				if (reference != null) {
					result.roots.add (reference.storage);
				} else if (receiver != null) {
					result.roots.add (receiver.storage);
				} else if (!(instruction is SsaObjectValidateInstruction || instruction is SsaClassUpcast)) {
					result.unknown = true;
				}
				origins.insert (instruction.result, result);
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var validation = instruction as SsaObjectValidateInstruction;
					var upcast = instruction as SsaClassUpcast;
					if (validation != null) {
						changed |= origins.lookup (validation.result).include (value (origins, validation.reference));
					} else if (upcast != null) {
						changed |= origins.lookup (upcast.result).include (value (origins, upcast.reference));
					}
				}
				foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
					for (int p = 0; p < edge.arguments.length; p++) {
						changed |= origins.lookup (edge.target.parameters[p]).include (value (origins, edge.arguments[p]));
					}
				}
			}
		} while (changed);
		return origins;
	}

	public static void annotate(SsaProgram program) {
		foreach (var function in program.functions) {
			if (function.object_storage.length == 0) {
				continue;
			}
			bool needed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					needed |= call != null && call.target != null && call.target.dispatch_kind != ClassDispatchKind.DIRECT;
				}
			}
			if (!needed) {
				continue;
			}
			var origins = derive (function);
			var eligible = new HashTable<SsaObjectStorage, bool> (direct_hash, direct_equal);
			foreach (var root in function.object_storage) {
				eligible.insert (root, SsaStackObjects.exact_root (function, root));
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call == null || call.target == null || call.target.dispatch_kind == ClassDispatchKind.DIRECT) {
						continue;
					}
					var receiver = value (origins, call.receiver);
					if (receiver.unknown || receiver.roots.length == 0) {
						continue;
					}
					var owner = receiver.roots[0].object_class;
					if (owner == null || owner.span.file.native_interface) {
						continue;
					}
					bool complete = true;
					foreach (var root in receiver.roots) {
						complete &= eligible.lookup (root) && root.object_class == owner;
					}
					if (complete) {
						call.exact_target = SsaStackObjects.exact_target (owner, call);
					}
				}
			}
		}
	}

	private static void require(bool condition, string message) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("exact receiver consumer: " + message);
		}
	}

	private static SsaFunction? implementation(SsaClass owner, int slot) throws SsaError {
		var seen = new HashTable<SsaClass, bool> (direct_hash, direct_equal);
		for (SsaClass? current = owner; current != null; current = current.parent_class) {
			require (!seen.contains (current), "cyclic nominal ancestry");
			seen.insert (current, true);
			SsaFunction? selected = null;
			foreach (var method in current.methods) {
				if (method.dispatch_kind == ClassDispatchKind.DIRECT || method.virtual_slot != slot) {
					continue;
				}
				require (selected == null && method.declaring_type == current, "slot has ambiguous or foreign method authority");
				selected = method;
			}
			foreach (var property in current.properties) {
				var getter = property.getter;
				if (getter == null || getter.dispatch_kind == ClassDispatchKind.DIRECT || getter.virtual_slot != slot) {
					continue;
				}
				require (selected == null && property.declaring_type == current && getter.property_member == property,
					"slot has ambiguous or foreign property authority");
				selected = getter;
			}
			if (selected != null) {
				return selected;
			}
		}
		return null;
	}

	// Consumer: start at the actual receiver and traverse definitions and
	// incoming CFG arguments backwards. No producer origin set is consulted.
	private static GenericArray<SsaObjectStorage> roots(SsaFunction function, SsaValue receiver,
		HashTable<SsaValue, SsaInstruction> definitions, HashTable<SsaValue, GenericArray<SsaValue>> incoming) throws SsaError {
		var result = new GenericArray<SsaObjectStorage> ();
		var pending = new GenericArray<SsaValue> ();
		pending.add (receiver);
		var seen = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
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
			var arguments = incoming.lookup (current);
			if (current is SsaBlockParameter && arguments != null) {
				foreach (var argument in arguments) {
					pending.add (argument);
				}
				continue;
			}
			var reference = definition as SsaObjectReferenceInstruction;
			var storage = definition as SsaStorageReceiverInstruction;
			var root = reference != null ? reference.storage : storage != null ? storage.storage : null;
			require (root != null && function.object_storage.find (root), "receiver has an unknown, foreign or nonlocal origin");
			if (!result.find (root)) {
				result.add (root);
			}
		}
		require (result.length != 0, "receiver cycle has no concrete allocation origin");
		return result;
	}

	public static void verify(SsaProgram program) throws SsaError {
		foreach (var function in program.functions) {
			bool needed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					needed |= call != null && call.exact_target != null;
				}
			}
			if (!needed) {
				continue;
			}
			var definitions = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
			var incoming = new HashTable<SsaValue, GenericArray<SsaValue>> (direct_hash, direct_equal);
			var checked_roots = new HashTable<SsaObjectStorage, bool> (direct_hash, direct_equal);
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction.result != null) {
						definitions.insert (instruction.result, instruction);
					}
				}
				foreach (var edge in SsaHeapOwnerFlow.pointer_edges (block)) {
					require (edge.target != null && function.blocks.find (edge.target) && edge.arguments.length == edge.target.parameters.length, "invalid receiver control edge");
					for (int p = 0; p < edge.arguments.length; p++) {
						var parameter = edge.target.parameters[p];
						var arguments = incoming.lookup (parameter);
						if (arguments == null) {
							arguments = new GenericArray<SsaValue> ();
							incoming.insert (parameter, arguments);
						}
						arguments.add (edge.arguments[p]);
					}
				}
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call == null || call.exact_target == null) {
						continue;
					}
					require (call.receiver != null && call.target != null && call.target.dispatch_kind != ClassDispatchKind.DIRECT, "claim is not a virtual receiver call");
					var allocations = roots (function, call.receiver, definitions, incoming);
					var owner = allocations[0].object_class;
					require (owner != null && program.classes.find (owner) && !owner.span.file.native_interface, "nominal descriptor lacks a checked local definition");
					foreach (var root in allocations) {
						require (root.object_class == owner, "receiver merge has different dynamic classes");
						if (!checked_roots.contains (root)) {
							SsaStackObjectVerifier.verify_exact_root (function, root);
							checked_roots.insert (root, true);
						}
					}
					int slot = call.target.virtual_slot;
					var declared = call.target.implicit_receiver == null ? null : call.target.implicit_receiver.contract.instance_type as ClassType;
					require (declared != null && ((ClassType) owner.semantic_type).derives_from (declared) && slot >= 0 && slot < owner.virtual_entries.length &&
						call.exact_target == implementation (owner, slot) && call.exact_target == owner.virtual_entries[slot] && program.functions.find (call.exact_target),
						"target disagrees with nominal declarations, ancestry or virtual slot");
					require (call.exact_target.return_type == call.target.return_type && call.exact_target.result_contract == call.target.result_contract &&
						call.exact_target.parameters.length == call.target.parameters.length, "implementation changes the declared result or parameter grouping");
					for (int p = 0; p < call.target.parameters.length; p++) {
						require (call.exact_target.parameters[p].semantic_type == call.target.parameters[p].semantic_type &&
							call.exact_target.parameters[p].pointer_contract == call.target.parameters[p].pointer_contract, "implementation changes a declared input contract");
					}
				}
			}
		}
	}

}
}
