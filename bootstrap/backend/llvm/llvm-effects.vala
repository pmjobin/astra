// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Source;

namespace Astra.Backend.LLVM {
internal class LlvmUniqueReceiverBinding : Object {
	internal CApi.ValueRef call;
	private CApi.ValueRef root;
	private CApi.ValueRef target;
	internal LlvmUniqueReceiverBinding (LlvmModuleArtifact artifact, CApi.ValueRef call, CApi.ValueRef root) {
		this.call = call;
		this.root = root;
		target = CApi.called_value (call);
		CApi.add_call_attribute (call, 1, CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("noalias", 7), 0));
	}
	internal void verify() throws LlvmError {
		var attribute = CApi.call_enum_attribute (call, 1, CApi.enum_attribute_kind ("noalias", 7));
		if ((void*) CApi.instruction_parent (call) == null || (void*) CApi.instruction_parent (root) == null || CApi.opcode (root) != CApi.Opcode.ALLOCA || (void*) CApi.block_parent (CApi.instruction_parent (root)) != (void*) CApi.block_parent (CApi.instruction_parent (call)) || (void*) CApi.operand (call, 0) != (void*) root || (void*) CApi.called_value (call) != (void*) target || (void*) attribute == null || CApi.enum_attribute_value (attribute) != 0) {
			throw new LlvmError.VERIFICATION ("unique receiver call lost its exact activation-local allocation and callee authority");
		}
	}
}

internal class LlvmSemanticOptimizations : Object {
	internal static bool enabled(bool optimized) throws LlvmError {
		string? setting = Environment.get_variable ("ASTRA_TEST_OPTIMIZATIONS");
		if (setting == null) {
			return optimized;
		}
		if (setting != "on" && setting != "off") {
			throw new LlvmError.INVALID_INPUT ("ASTRA_TEST_OPTIMIZATIONS must be on or off");
		}
		return setting == "on";
	}
}

// Detached artifact authority: upstream graphs may be released. These are
// source-lowering checks; LLVM's independently optimized clone is separate.
internal class LlvmEffectBinding : Object {
	internal CApi.ValueRef function;
	private uint flags;
	private bool snapshot;
	private uint[] parameter_flags = {};
	private bool receiver;
	private GenericArray<LlvmFloatingStep> steps = new GenericArray<LlvmFloatingStep> ();
	private GenericArray<void*> order = new GenericArray<void*> ();
	internal LlvmEffectBinding (LlvmModuleArtifact artifact, CApi.ValueRef function, uint flags, bool preserve_body = false, FunctionEffectFacts? facts = null, bool receiver = false) {
		this.function = function;
		this.flags = flags;
		snapshot = flags != 0 || preserve_body;
		this.receiver = receiver;
		if (facts != null) {
			for (int p = 0; p < facts.parameter_count; p++) {
				parameter_flags += facts.parameter (p);
				if (facts.parameter (p) != 0) {
					snapshot = true;
				}
			}
		}
		if ((flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) != 0) {
			add (artifact.context, 1, "captures", 0);
		}
		if ((flags & FunctionEffectFacts.RECEIVER_READONLY) != 0) {
			add (artifact.context, 1, "readonly", 0);
		}
		if ((flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) != 0) {
			add (artifact.context, uint.MAX, "memory", 0);
		}
		for (int p = 0; p < parameter_flags.length; p++) {
			uint index = (uint) p + 1 + (receiver ? 1U : 0U);
			if ((parameter_flags[p] & 1) != 0) {
				add (artifact.context, index, "captures", 0);
			}
			if ((parameter_flags[p] & 2) != 0) {
				add (artifact.context, index, "readonly", 0);
			}
		}
		if (!snapshot) {
			return;
		}
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			order.add ((void*) block);
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				order.add ((void*) instruction);
				steps.add (new LlvmFloatingStep (instruction));
			}
		}
	}
	private void add(CApi.ContextRef context, uint index, string name, uint64 value) {
		CApi.add_attribute (function, index, CApi.create_enum_attribute (context, CApi.enum_attribute_kind (name, name.length), value));
	}
	private void attribute(uint index, string name, bool expected) throws LlvmError {
		var attribute = CApi.enum_attribute (function, index, CApi.enum_attribute_kind (name, name.length));
		if (((void*) attribute != null) != expected || (expected && CApi.enum_attribute_value (attribute) != 0)) {
			throw new LlvmError.VERIFICATION ("derived effect attribute lost its exact verified source authority");
		}
	}
	internal void verify() throws LlvmError {
		attribute (uint.MAX, "memory", (flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) != 0);
		for (uint i = 0; i <= CApi.count_params (function); i++) {
			int p = (int) i - 1 - (receiver ? 1 : 0);
			uint formal = p >= 0 && p < parameter_flags.length ? parameter_flags[p] : 0;
			bool receiver_capture = receiver && i == 1 && (flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) != 0;
			bool receiver_readonly = receiver && i == 1 && (flags & FunctionEffectFacts.RECEIVER_READONLY) != 0;
			attribute (i, "captures", receiver_capture || (formal & 1) != 0);
			attribute (i, "readonly", receiver_readonly || (formal & 2) != 0);
			attribute (i, "writeonly", false);
			attribute (i, "noalias", false);
		}
		if (!snapshot) {
			return;
		}
		int at = 0;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			if (at >= order.length || order[at++] != (void*) block) {
				throw new LlvmError.VERIFICATION ("derived effects lost original body blocks");
			}
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (at >= order.length || order[at++] != (void*) instruction) {
					throw new LlvmError.VERIFICATION ("derived effects lost original instruction order");
				}
			}
		}
		if (at != order.length) {
			throw new LlvmError.VERIFICATION ("derived effects lost original body extent");
		}
		foreach (var step in steps) {
			step.verify ();
		}
	}
}
}
