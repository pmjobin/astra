// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Cfg {
internal class CfgEnumVerifier : Object {
	private HashTable<EnumType, EnumDefinition> definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private CfgFunction function;
	private CfgProgram program;
	private unowned CopyabilityFields records;
	private int[] writes;
	private HashTable<CfgPlace, CfgEnumSlot> views = new HashTable<CfgPlace, CfgEnumSlot> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgEnumSlot> captured_views = new HashTable<CfgValue, CfgEnumSlot> (direct_hash, direct_equal);
	private CfgEnumVerifier (CopyabilityFields records, CfgProgram program) {
		this.records = records;
		this.program = program;
	}

	internal static void verify(CfgProgram program, CopyabilityFields records) throws CfgError {
		if (program.enums.length == 0) {
			foreach (var function in program.functions) {
				if (function.enum_slots.length != 0 || function.return_type is EnumType) {
					throw new CfgError.INVALID_CFG ("enum carriers require a registered nominal definition");
				}
				foreach (var parameter in function.parameters) {
					if (parameter.semantic_type is EnumType) {
						throw new CfgError.INVALID_CFG ("enum parameters require a registered nominal definition");
					}
				}
			}
			foreach (var function in program.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						if (instruction is CfgAsyncRunStatus || instruction is CfgEnumConstruct || instruction is CfgEnumCopy || instruction is CfgEnumAcquire || instruction is CfgEnumExtractSum || instruction is CfgEnumExtractRecord || instruction is CfgEnumExtractScalar || instruction is CfgEnumExtractBuffer || instruction is CfgEnumScalarCapture || instruction is CfgEnumScalarAbort || instruction is CfgEnumBufferCapture || instruction is CfgEnumBufferAbort || instruction is CfgEnumFinishArm || instruction is CfgEnumEndInspection || instruction is CfgEnumDrop || instruction is CfgEnumCommit) {
							throw new CfgError.INVALID_CFG ("enum operations require a registered nominal definition and owned carrier");
						}
					}
					if (block.is_complete && (block.terminator is CfgEnumDispatch || block.terminator is CfgEnumInvalidTag || block.terminator is CfgEnumReturn)) {
						throw new CfgError.INVALID_CFG ("enum control requires a registered nominal definition and owned carrier");
					}
				}
			}
			foreach (var function in program.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as CfgCallInstruction;
						if (call == null) {
							continue;
						}
						if (call.enum_result != null) {
							throw new CfgError.INVALID_CFG ("enum call result requires a registered nominal definition and owned carrier");
						}
						foreach (var argument in call.arguments) {
							if (argument.semantic_type is EnumType) {
								throw new CfgError.INVALID_CFG ("enum call argument requires a registered nominal definition and owned carrier");
							}
						}
					}
				}
			}
			return;
		}
		var proof = new CfgEnumVerifier (records, program);
		foreach (var definition in program.enums) {
			if (proof.definitions.contains (definition.semantic_type)) {
				throw new CfgError.INVALID_CFG ("duplicate enum definition");
			}
			proof.definitions.insert (definition.semantic_type, definition);
		}
		try {
			foreach (var definition in program.enums) {
				EnumValueAuthority.verify (definition, proof.definition, records, null, null, proof.valid_scalar_owner);
			}
			foreach (var function in program.functions) {
				proof.verify_function (function);
			}
		} catch (EnumContractError error) {
			throw new CfgError.INVALID_CFG ("invalid enum contract: %s", error.message);
		}
	}

	private bool valid_scalar_owner(EnumField field) {
		if (field.owns_child) {
			foreach (var owner in program.classes) {
				if (owner.semantic_type == field.semantic_type) {
					return !owner.polymorphic && !((ClassType) owner.semantic_type).is_interface;
				}
			}
			return false;
		}
		foreach (var handle in program.handles) {
			if (handle.semantic_type == field.semantic_type) {
				return field.owned_cleanup != null && handle.cleanup.external_symbol == field.owned_cleanup.external_symbol;
			}
		}
		return false;
	}

	private EnumDefinition? definition(EnumType type) {
		return definitions.lookup (type);
	}

	private void slot(CfgEnumSlot slot) throws EnumContractError {
		if (slot.ordinal < 0 || slot.ordinal >= function.enum_slots.length || function.enum_slots[slot.ordinal] != slot || definitions.lookup (slot.definition.semantic_type) != slot.definition) {
			throw new EnumContractError.INVALID_GRAPH ("enum slot lost its exact function, nominal definition or instance");
		}
	}

	private void write(CfgEnumSlot destination, EnumFlowStep step) throws EnumContractError {
		slot (destination);
		writes[destination.ordinal]++;
		if ((destination.local == null || (destination.local.incoming_parameter != null && !owning (destination))) && writes[destination.ordinal] > 1) {
			throw new EnumContractError.INVALID_GRAPH ("enum scratch slot has multiple producers");
		}
		step.writes.add (destination.ordinal);
	}

	private bool owning(CfgEnumSlot source) {
		return EnumValueAuthority.owns (source.definition, definition);
	}

	private void consume(CfgEnumSlot source, EnumFlowStep step) throws EnumContractError {
		read (source, step);
		if (owning (source)) {
			if (source.inspection_root != null) {
				throw new EnumContractError.INVALID_GRAPH ("enum inspection view cannot transfer ownership");
			}
			step.transfers.add (source.ordinal);
			step.kills.add (source.ordinal);
		}
	}

	private void read(CfgEnumSlot source, EnumFlowStep step) throws EnumContractError {
		slot (source);
		step.reads.add (source.ordinal);
		if (source.inspection_root != null) {
			slot (source.inspection_root);
			step.reads.add (source.inspection_root.ordinal);
		}
	}

	private void selected_variant(CfgEnumSlot source, EnumVariant variant, CfgBlock block) throws EnumContractError {
		bool selected = false;
		foreach (var predecessor in function.blocks) {
			foreach (var successor in predecessor.terminator.successors ()) {
				if (successor != block) {
					continue;
				}
				var dispatch = predecessor.terminator as CfgEnumDispatch;
				if (dispatch == null || dispatch.source != source || dispatch.invalid_target == block) {
					throw new EnumContractError.INVALID_GRAPH ("payload projection lacks a dominating exact active-variant dispatch");
				}
				foreach (var branch in dispatch.cases) {
					if (branch.target == block) {
						if (branch.variant != variant) {
							throw new EnumContractError.INVALID_GRAPH ("inactive payload projection");
						}
						selected = true;
					}
				}
			}
		}
		if (!selected) {
			throw new EnumContractError.INVALID_GRAPH ("payload projection has no selected predecessor");
		}
	}

	// The mask-to-binding check below also needs its converse: an extracted
	// owner cannot silently become a full active-case disposal.
	private void binding_disposition(CfgEnumSlot source, EnumField field, CfgInstruction extraction, CfgBlock block) throws EnumContractError {
		bool after = false;
		int dispositions = 0;
		foreach (var instruction in block.instructions) {
			if (instruction == extraction) {
				after = true;
				continue;
			}
			if (!after) {
				continue;
			}
			var finish = instruction as CfgEnumFinishArm;
			if (finish == null || finish.source != source) {
				continue;
			}
			int retained = 0;
			for (uint f = 0; f < finish.retained_count; f++) {
				if (finish.field (f) == field) {
					retained++;
				}
			}
			if (retained != 1) {
				throw new EnumContractError.INVALID_GRAPH ("bound owning field cannot also be disposed at arm entry");
			}
			dispositions++;
		}
		if (dispositions != 1) {
			throw new EnumContractError.INVALID_GRAPH ("consuming field binding requires its exact later retained disposition");
		}
	}

	private void projection(CfgEnumSlot source, EnumField field, StructLeafPath? path, SemanticType result, CfgBlock block) throws EnumContractError {
		slot (source);
		if (source.local != null) {
			throw new EnumContractError.INVALID_GRAPH ("match projection requires an independent frozen snapshot");
		}
		var ordinal = field.identity.variant.ordinal;
		if (ordinal < 0 || ordinal >= source.definition.variant_count) {
			throw new EnumContractError.INVALID_GRAPH ("projection variant is outside its enum");
		}
		var variant = source.definition.variant (ordinal);
		if (field.identity.ordinal < 0 || field.identity.ordinal >= variant.field_count || variant.field (field.identity.ordinal) != field) {
			throw new EnumContractError.INVALID_GRAPH ("projection lost the complete selected field identity");
		}
		selected_variant (source, variant, block);
		if (field.owns_record && path == null && result == field.semantic_type) {
			return;
		}
		if (field.semantic_type.is_struct_storage ()) {
			GenericArray<StructLeafPath> leaves;
			try {
				leaves = StructLeafOrder.enumerate (field.semantic_type, records);
			} catch (StructLeafError error) {
				throw new EnumContractError.INVALID_GRAPH (error.message);
			}
			bool exact = false;
			foreach (var leaf in leaves) {
				if (path != null && leaf.spelling () == path.spelling () && leaf.semantic_type == result && path.semantic_type == result) {
					exact = true;
				}
			}
			if (!exact) {
				throw new EnumContractError.INVALID_GRAPH ("enum record projection path/type correspondence mismatch");
			}
		} else if (path != null || result != field.semantic_type) {
			throw new EnumContractError.INVALID_GRAPH ("enum payload projection exact type mismatch");
		}
	}

	private void binding(CfgEnumPayloadValue payload, CfgBlock block) throws EnumContractError {
		int uses = 0;
		for (int i = 0; i < block.instructions.length; i++) {
			var evaluation = block.instructions[i] as CfgEvaluateInstruction;
			if (evaluation == null || evaluation.value != payload) {
				continue;
			}
			uses++;
			var initialization = i + 1 >= block.instructions.length ? null : block.instructions[i + 1] as CfgInitialize;
			if (initialization == null || initialization.value != evaluation.result) {
				throw new EnumContractError.INVALID_GRAPH ("enum binding requires its exact adjacent captured payload initialization");
			}
			CfgPlace place = initialization.target;
			if (payload.record_path != null) {
				for (int d = payload.record_path.depth - 1; d >= 0; d--) {
					var field = place as CfgFieldPlace;
					if (field == null || field.field.ordinal != payload.record_path.field_ordinal (d)) {
						throw new EnumContractError.INVALID_GRAPH ("enum record binding projection path mismatch");
					}
					place = field.aggregate;
				}
			}
			var local = place as CfgLocalPlace;
			if (local == null || local.ordinal != payload.binding.local_ordinal || local.semantic_type != payload.field.semantic_type) {
				throw new EnumContractError.INVALID_GRAPH ("enum payload was coherently bound to a different same-typed destination");
			}
		}
		if (uses != 1) {
			throw new EnumContractError.INVALID_GRAPH ("enum payload projection must initialize exactly its selected binding");
		}
	}

	private void inspect_place(CfgPlace place, EnumFlowStep step, CfgBlock block) throws EnumContractError {
		if (place is CfgFieldPlace) {
			inspect_place (((CfgFieldPlace) place).aggregate, step, block);
		}
		if (place is CfgIndirectFieldPlace) {
			inspect_value (((CfgIndirectFieldPlace) place).pointer, step, block);
		}
		if (place is CfgDereferencePlace) {
			inspect_value (((CfgDereferencePlace) place).pointer, step, block);
		}
		if (place is CfgArrayElementPlace) {
			inspect_value (((CfgArrayElementPlace) place).index, step, block);
		}
		if (place is CfgSliceElementPlace) {
			inspect_value (((CfgSliceElementPlace) place).slice, step, block, false, true);
			inspect_value (((CfgSliceElementPlace) place).index, step, block);
		}
	}

	private void inspect_value(CfgValue value, EnumFlowStep step, CfgBlock block, bool argument = false, bool view_use = false) throws EnumContractError {
		var view = captured_views.lookup (value);
		if (value is CfgLoadValue) {
			view = views.lookup (((CfgLoadValue) value).source);
		}
		if (view != null) {
			if (!view_use) {
				throw new EnumContractError.INVALID_GRAPH ("enum inspection array view cannot escape or enter mutable transport");
			}
			read (view, step);
		}
		if (value is CfgEnumArgument) {
			if (!argument) {
				throw new EnumContractError.INVALID_GRAPH ("enum carrier is not an ordinary value");
			}
			consume (((CfgEnumArgument) value).source, step);
			return;
		}
		if (value is CfgEnumTag) {
			if (value.semantic_type != ((CfgEnumTag) value).source.definition.tag_type) {
				throw new EnumContractError.INVALID_GRAPH ("enum tag requires internal i32 type");
			}
			read (((CfgEnumTag) value).source, step);
			return;
		}
		if (value is CfgEnumPayloadValue) {
			var payload = (CfgEnumPayloadValue) value;
			if (payload.field.owns_record || payload.field.owns_scalar || (payload.field.owns_buffer && payload.source.inspection_root == null)) {
				throw new EnumContractError.INVALID_GRAPH ("owning buffer field cannot enter copied slice projection");
			}
			binding (payload, block);
			if (payload.binding.instance != payload.source.instance || payload.binding.field != payload.field.identity) {
				throw new EnumContractError.INVALID_GRAPH ("enum projection lost intended selected binding");
			}
			projection (payload.source, payload.field, payload.record_path, value.semantic_type, block);
			read (payload.source, step);
			return;
		}
		if (value is CfgBinaryValue) {
			inspect_value (((CfgBinaryValue) value).left, step, block);
			inspect_value (((CfgBinaryValue) value).right, step, block);
		}
		if (value is CfgPrefixValue) {
			inspect_value (((CfgPrefixValue) value).operand, step, block);
		}
		if (value is CfgLoadValue) {
			inspect_place (((CfgLoadValue) value).source, step, block);
		}
		if (value is CfgAddressOfValue && ((CfgAddressOfValue) value).receiver_place != null) {
			if (view_place (((CfgAddressOfValue) value).receiver_place)) {
				throw new EnumContractError.INVALID_GRAPH ("enum inspection view cannot expose mutable record storage");
			}
			inspect_place (((CfgAddressOfValue) value).receiver_place, step, block);
		}
		if (value is CfgVectorDotValue) {
			var dot = (CfgVectorDotValue) value;
			if (dot.accumulator != null) {
				inspect_value (dot.accumulator, step, block);
			}
			inspect_value (dot.first, step, block);
			inspect_value (dot.second, step, block);
		}
		if (value is CfgDspValue) {
			var dsp = (CfgDspValue) value;
			inspect_value (dsp.first, step, block);
			if (dsp.second != null) {
				inspect_value (dsp.second, step, block);
			}
		}
		if (value is CfgIntegerShiftValue) {
			inspect_value (((CfgIntegerShiftValue) value).operand, step, block);
			inspect_value (((CfgIntegerShiftValue) value).count, step, block);
		}
		if (value is CfgNumericConversionValue) {
			inspect_value (((CfgNumericConversionValue) value).operand, step, block);
		}
		if (value is CfgFloatConversionValue) {
			inspect_value (((CfgFloatConversionValue) value).operand, step, block);
		}
		if (value is CfgIntegerConversionValue) {
			inspect_value (((CfgIntegerConversionValue) value).operand, step, block);
		}
		if (value is CfgVectorSplatValue) {
			inspect_value (((CfgVectorSplatValue) value).operand, step, block);
		}
		if (value is CfgVectorExtractValue) {
			inspect_value (((CfgVectorExtractValue) value).vector, step, block);
		}
		if (value is CfgVectorInsertValue) {
			inspect_value (((CfgVectorInsertValue) value).vector, step, block);
			inspect_value (((CfgVectorInsertValue) value).replacement, step, block);
		}
		if (value is CfgVectorShuffleValue) {
			inspect_value (((CfgVectorShuffleValue) value).vector, step, block);
		}
		if (value is CfgVectorSelectValue) {
			var select = (CfgVectorSelectValue) value;
			inspect_value (select.mask, step, block);
			inspect_value (select.true_value, step, block);
			inspect_value (select.false_value, step, block);
		}
		if (value is CfgVectorConstructValue) {
			foreach (var lane in ((CfgVectorConstructValue) value).lanes) {
				inspect_value (lane, step, block);
			}
		}
		if (value is CfgVectorReductionValue) {
			inspect_value (((CfgVectorReductionValue) value).operand, step, block);
		}
		if (value is CfgObjectValidateValue) {
			inspect_value (((CfgObjectValidateValue) value).reference, step, block);
		}
		if (value is CfgTextLengthValue) {
			inspect_value (((CfgTextLengthValue) value).receiver, step, block);
		}
		if (value is CfgSliceLengthValue) {
			inspect_value (((CfgSliceLengthValue) value).slice, step, block, false, true);
		}
		if (value is CfgSliceFromArrayValue) {
			var slice = (CfgSliceFromArrayValue) value;
			if (slice.start != null) {
				inspect_value (slice.start, step, block);
			}
			if (slice.count != null) {
				inspect_value (slice.count, step, block);
			}
		}

	}

	private bool view_place(CfgPlace place) {
		if (place is CfgFieldPlace) {
			return view_place (((CfgFieldPlace) place).aggregate);
		}
		var slice = place as CfgSliceElementPlace;
		return views.contains (place) || (slice != null && (captured_views.contains (slice.slice) || (slice.slice is CfgLoadValue && views.contains (((CfgLoadValue) slice.slice).source))));
	}
	private void verify_function(CfgFunction input) throws EnumContractError {
		views.remove_all ();
		captured_views.remove_all ();
		foreach (var block in input.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var evaluation = block.instructions[i] as CfgEvaluateInstruction;
				var payload = evaluation == null ? null : evaluation.value as CfgEnumPayloadValue;
				if (payload != null && payload.field.owns_buffer && i + 1 < block.instructions.length && block.instructions[i + 1] is CfgInitialize) {
					var initialization = (CfgInitialize) block.instructions[i + 1];
					views.insert (initialization.target, payload.source);
				}
			}
		}
		foreach (var block in input.blocks) {
			foreach (var instruction in block.instructions) {
				var evaluation = instruction as CfgEvaluateInstruction;
				var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
				if (load != null && views.contains (load.source)) {
					captured_views.insert (evaluation.result, views.lookup (load.source));
				}
			}
		}
		function = input;
		writes = new int[function.enum_slots.length];
		var acquired = new HashTable<CfgParameter, bool> (direct_hash, direct_equal);
		foreach (var slot in function.enum_slots) {
			this.slot (slot);
		}
		var blocks = new GenericArray<EnumFlowBlock> ();
		foreach (var block in function.blocks) {
			var flow = new EnumFlowBlock ();
			flow.normal_exit = block.terminator is CfgReturn || block.terminator is CfgFunctionEnd;
			foreach (var successor in block.terminator.successors ()) {
				flow.successors.add (successor.ordinal);
			}
			foreach (var instruction in block.instructions) {
				var step = new EnumFlowStep ();
				flow.steps.add (step);
				var ended = instruction as CfgEnumEndInspection;
				if (ended != null) {
					slot (ended.source);
					if (ended.source.inspection_root == null) {
						throw new EnumContractError.INVALID_GRAPH ("inspection end requires its exact view");
					}
					step.ends.add (ended.source.ordinal);
					continue;
				}
				var buffer_extraction = instruction as CfgEnumExtractBuffer;
				if (buffer_extraction != null) {
					var extraction = buffer_extraction;
					if (!extraction.field.owns_buffer || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.destination.ordinal != extraction.binding.local_ordinal || extraction.destination.semantic_type != extraction.field.semantic_type || extraction.destination.cleanup == null || extraction.destination.cleanup.buffer_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("owned enum buffer binding lost exact active field/owner correspondence");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var record_extraction = instruction as CfgEnumExtractRecord;
				if (record_extraction != null) {
					var extraction = record_extraction;
					if (!extraction.field.owns_record || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.destination.ordinal != extraction.binding.local_ordinal || extraction.results.shape.semantic_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("enum record binding lost its exact consuming active field and fresh root");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var scalar_extraction = instruction as CfgEnumExtractScalar;
				if (scalar_extraction != null) {
					var extraction = scalar_extraction;
					if (!extraction.field.owns_scalar || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.destination.ordinal != extraction.binding.local_ordinal || extraction.destination.semantic_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("enum scalar binding lost exact active field and fresh destination");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var finish = instruction as CfgEnumFinishArm;
				if (finish != null) {
					if (!owning (finish.source) || finish.source.inspection_root != null) {
						throw new EnumContractError.INVALID_GRAPH ("consuming arm requires an exact owning source");
					}
					if (finish.variant != null) {
						if (finish.variant.identity.enumeration != finish.source.definition.semantic_type.identity) {
							throw new EnumContractError.INVALID_GRAPH ("consuming arm lost its exact nominal variant");
						}
						try {
							selected_variant (finish.source, finish.variant, block);
						} catch (EnumContractError error) {
							throw new EnumContractError.INVALID_GRAPH ("consuming arm disposal lost its exact active variant: %s", error.message);
						}
					}
					int previous = -1;
					for (uint f = 0; f < finish.retained_count; f++) {
						var field = finish.field (f);
						if (finish.variant == null || field.identity.variant != finish.variant.identity || field.identity.ordinal <= previous || finish.variant.field (field.identity.ordinal) != field) {
							throw new EnumContractError.INVALID_GRAPH ("arm disposal mask lost exact selected fields");
						}
						previous = field.identity.ordinal;
						int projections = 0;
						foreach (var prior in block.instructions) {
							if (prior == finish) {
								break;
							}
							var buffer = prior as CfgEnumExtractBuffer;
							var scalar = prior as CfgEnumExtractScalar;
							var record = prior as CfgEnumExtractRecord;
							var sum = prior as CfgEnumExtractSum;
							if ((buffer != null && buffer.source == finish.source && buffer.field == field) || (scalar != null && scalar.source == finish.source && scalar.field == field) || (record != null && record.source == finish.source && record.field == field) || (sum != null && sum.source == finish.source && sum.field == field)) {
								projections++;
							}
						}
						if (projections != 1) {
							throw new EnumContractError.INVALID_GRAPH ("retained owning field requires exactly one complete active binding");
						}
					}
					foreach (var prior in block.instructions) {
						if (prior == finish) {
							break;
						}
						EnumField? field = null;
						if (prior is CfgEnumExtractBuffer) {
							var extract = (CfgEnumExtractBuffer) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is CfgEnumExtractScalar) {
							var extract = (CfgEnumExtractScalar) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is CfgEnumExtractRecord) {
							var extract = (CfgEnumExtractRecord) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is CfgEnumExtractSum) {
							var extract = (CfgEnumExtractSum) prior;
							if (extract.source == finish.source && owning (extract.destination)) {
								field = extract.field;
							}
						}
						if (field != null) {
							bool retained = false;
							for (uint f = 0; f < finish.retained_count; f++) {
								if (finish.field (f) == field) {
									retained = true;
								}
							}
							if (!retained) {
								throw new EnumContractError.INVALID_GRAPH ("bound owning field cannot also be disposed at arm entry");
							}
						}
					}
					consume (finish.source, step);
					continue;
				}
				var commit = instruction as CfgEnumCommit;
				if (commit != null) {
					var captured = commit.captured;
					slot (captured);
					if (!owning (captured) || captured.reservation_source == null || captured.inspection_root != null || captured.reservation_source.definition != captured.definition) {
						throw new EnumContractError.INVALID_GRAPH ("enum commit requires exact reserved owning source and complete capture");
					}
					read (captured, step);
					consume (captured.reservation_source, step);
					step.acquires.add (captured.ordinal);
					continue;
				}
				var drop = instruction as CfgEnumDrop;
				if (drop != null) {
					slot (drop.source);
					if (!owning (drop.source) || drop.source.inspection_root != null) {
						throw new EnumContractError.INVALID_GRAPH ("enum cleanup requires exact owning carrier, never a view");
					}
					step.kills.add (drop.source.ordinal);
					step.destroys.add (drop.source.ordinal);
					continue;
				}
				var run = instruction as CfgAsyncRunStatus;
				if (run != null) {
					if (run.operation.contract.kind != AsyncOperationKind.RUN || run.destination.definition.semantic_type != run.operation.contract.runtime.status_type || !run.destination.definition.payload_free || run.destination.definition.variant_count != 2) {
						throw new EnumContractError.INVALID_GRAPH ("run status requires its exact ordinary Completed/Cancelled enum");
					}
					write (run.destination, step);
					continue;
				}
				var construction = instruction as CfgEnumConstruct;
				if (construction != null) {
					if (!construction.matches_inputs ()) {
						throw new EnumContractError.INVALID_GRAPH ("enum constructor lost intended field/operand correspondence");
					}
					var variant = construction.variant;
					var definition = construction.destination.definition;
					if (variant.identity.ordinal < 0 || variant.identity.ordinal >= definition.variant_count || definition.variant (variant.identity.ordinal) != variant || construction.fields.length != variant.field_count) {
						throw new EnumContractError.INVALID_GRAPH ("enum constructor has invalid tag or incomplete active payload");
					}
					for (uint f = 0; f < variant.field_count; f++) {
						var field = variant.field (f);
						var supplied = construction.fields[f];
						if (supplied.field != field || (!field.owns_buffer && supplied.buffer != null) || (!field.owns_scalar && supplied.scalar_owner != null) || (!field.owns_record && supplied.record_move != null)) {
							throw new EnumContractError.INVALID_GRAPH ("enum constructor selected field correspondence mismatch");
						}
						if (field.owns_buffer) {
							if (supplied.buffer == null || supplied.sum != null || supplied.leaves.length != 0 || supplied.buffer.cleanup.buffer_type != field.semantic_type) {
								throw new EnumContractError.INVALID_GRAPH ("owning enum payload requires its exact complete buffer capture");
							}
						} else if (field.owns_scalar) {
							var owner = supplied.scalar_owner;
							if (owner == null || supplied.buffer != null || supplied.sum != null || supplied.leaves.length != 1 || supplied.leaves[0] != owner.result || owner.result.semantic_type != field.semantic_type || owner.cleanup.is_heap_object != field.owns_child || (field.owned_cleanup != null && owner.cleanup.external_symbol != field.owned_cleanup.external_symbol)) {
								throw new EnumContractError.INVALID_GRAPH ("enum scalar payload requires its exact typed named-owner capture");
							}
						} else if (field.owns_record) {
							var move = supplied.record_move;
							if (move == null || move.consumer != construction || move.use_kind != StructResultUseKind.ENUM_PAYLOAD || move.shape.semantic_type != field.semantic_type || move.leaves != supplied.leaves || supplied.sum != null || supplied.buffer != null || supplied.scalar_owner != null || !block.instructions.find (move)) {
								throw new EnumContractError.INVALID_GRAPH ("enum record payload requires its original complete nominal field commit");
							}
							foreach (var leaf in supplied.leaves) {
								inspect_value (leaf, step, block);
							}
						} else if (field.semantic_type is EnumType) {
							if (supplied.sum == null || supplied.sum.definition.semantic_type != field.semantic_type || supplied.leaves.length != 0) {
								throw new EnumContractError.INVALID_GRAPH ("nested enum payload nominal correspondence mismatch");
							}
							consume (supplied.sum, step);
						} else {
							if (supplied.sum != null) {
								throw new EnumContractError.INVALID_GRAPH ("unexpected sum channel in scalar/record payload");
							}
							var expected = new GenericArray<SemanticType> ();
							if (field.semantic_type.is_struct_storage ()) {
								try {
									foreach (var leaf in StructLeafOrder.enumerate (field.semantic_type, records)) {
										expected.add (leaf.semantic_type);
									}
								} catch (StructLeafError error) {
									throw new EnumContractError.INVALID_GRAPH (error.message);
								}
							} else {
								expected.add (field.semantic_type);
							}
							if (supplied.leaves.length != expected.length) {
								throw new EnumContractError.INVALID_GRAPH ("enum payload leaf count mismatch");
							}
							for (int l = 0; l < expected.length; l++) {
								if (supplied.leaves[l].semantic_type != expected[l]) {
									throw new EnumContractError.INVALID_GRAPH ("enum payload leaf exact type mismatch");
								}
								inspect_value (supplied.leaves[l], step, block);
							}
						}
					}
					write (construction.destination, step);
					if (owning (construction.destination)) {
						step.acquires.add (construction.destination.ordinal);
					}
					continue;
				}
				var copy = instruction as CfgEnumCopy;
				if (copy != null) {
					if (copy.destination == copy.source || copy.destination.definition != copy.source.definition) {
						throw new EnumContractError.INVALID_GRAPH ("enum snapshot requires distinct exact carriers");
					}
					if (owning (copy.source)) {
						if (copy.mode == EnumUse.COPY) {
							throw new EnumContractError.INVALID_GRAPH ("move-only enum cannot be copied, including its empty variants");
						}
						if (copy.mode == EnumUse.INSPECT) {
							if (copy.destination.inspection_root != (copy.source.inspection_root ?? copy.source)) {
								throw new EnumContractError.INVALID_GRAPH ("enum inspection lost its exact live root");
							}
							step.begins.add (copy.destination.ordinal);
							read (copy.source, step);
						} else if (copy.destination.reservation_source != null) {
							if (copy.destination.reservation_source != copy.source) {
								throw new EnumContractError.INVALID_GRAPH ("enum reservation source mismatch");
							}
							read (copy.source, step);
						} else {
							consume (copy.source, step);
							step.acquires.add (copy.destination.ordinal);
						}
					} else {
						if (copy.mode != EnumUse.COPY) {
							throw new EnumContractError.INVALID_GRAPH ("copyable enum requires ordinary snapshot transport");
						}
						read (copy.source, step);
					} write (copy.destination, step);
					continue;
				}
				var acquisition = instruction as CfgEnumAcquire;
				if (acquisition != null) {
					if (block != function.entry || acquisition.parameter.semantic_type != acquisition.destination.definition.semantic_type || (acquisition.parameter.ordinal < 0 || acquisition.parameter.ordinal >= function.parameters.length || function.parameters[acquisition.parameter.ordinal] != acquisition.parameter) || !(acquisition.destination.local != null && acquisition.destination.local.incoming_parameter == acquisition.parameter)) {
						throw new EnumContractError.INVALID_GRAPH ("enum parameter acquisition lost its exact entry storage/parameter association in %s (entry=%s, parameter=#%d, local=%s, incoming=%s)", function.name, (block == function.entry).to_string (), acquisition.parameter.ordinal, (acquisition.destination.local != null).to_string (), (acquisition.destination.local != null && acquisition.destination.local.incoming_parameter == acquisition.parameter).to_string ());
					}
					if (acquired.contains (acquisition.parameter)) {
						throw new EnumContractError.INVALID_GRAPH ("enum parameter has duplicate snapshots");
					}
					acquired.insert (acquisition.parameter, true);
					write (acquisition.destination, step);
					if (owning (acquisition.destination)) {
						step.acquires.add (acquisition.destination.ordinal);
					}
					continue;
				}
				var extraction = instruction as CfgEnumExtractSum;
				if (extraction != null) {
					if (extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.destination.local == null || extraction.destination.local.ordinal != extraction.binding.local_ordinal) {
						throw new EnumContractError.INVALID_GRAPH ("nested sum binding destination correspondence mismatch");
					}
					projection (extraction.source, extraction.field, null, extraction.destination.definition.semantic_type, block);
					if (owning (extraction.destination) && extraction.source.inspection_root == null) {
						binding_disposition (extraction.source, extraction.field, extraction, block);
					}
					read (extraction.source, step);
					write (extraction.destination, step);
					if (owning (extraction.destination)) {
						if (extraction.source.inspection_root != null) {
							if (extraction.destination.inspection_root != extraction.source.inspection_root) {
								throw new EnumContractError.INVALID_GRAPH ("nested enum inspection root mismatch");
							}
						} else {
							step.acquires.add (extraction.destination.ordinal);
						}
					}
					continue;
				}
				if (instruction is CfgTaskSuccess) {
					var success = (CfgTaskSuccess) instruction;
					if (success.enum_result != null) {
						if (success.enum_result.definition.semantic_type != success.success_type || success.operation.success != success || success.operation.discard) {
							throw new EnumContractError.INVALID_GRAPH ("enum await lost exact typed success authority");
						}
						write (success.enum_result, step);
						if (owning (success.enum_result)) {
							step.acquires.add (success.enum_result.ordinal);
						}
					}
					continue;
				}
				if (instruction is CfgGroupCallSuccess) {
					var success = (CfgGroupCallSuccess) instruction;
					if (success.call == null || success.call.exception_result == null) {
						throw new EnumContractError.INVALID_GRAPH ("exception success must name its exact checked call");
					}
					if (success.call.enum_result != null) {
						write (success.call.enum_result, step);
						if (owning (success.call.enum_result)) {
							step.acquires.add (success.call.enum_result.ordinal);
						}
					}
					continue;
				}
				var call = instruction as CfgCallInstruction;
				if (call != null) {
					if (call.target == null) {
						throw new EnumContractError.INVALID_GRAPH ("enum call target has expired");
					}
					if (!call.matches_enum_channels ()) {
						throw new EnumContractError.INVALID_GRAPH ("enum call lost exact argument/result instance correspondence");
					}
					foreach (var argument in call.arguments) {
						inspect_value (argument, step, block, true);
					}
					if (call is CfgTaskCreate) {
						continue;
					}
					if (call.target.return_type is EnumType) {
						if (call.enum_result == null || call.result != null || call.enum_result.definition.semantic_type != call.target.return_type) {
							throw new EnumContractError.INVALID_GRAPH ("enum call/result destination correspondence mismatch");
						}
						if (call.exception_result == null) {
							write (call.enum_result, step);
							if (owning (call.enum_result)) {
								step.acquires.add (call.enum_result.ordinal);
							}
						}
					} else if (call.enum_result != null) {
						throw new EnumContractError.INVALID_GRAPH ("unexpected enum call result carrier");
					}
					continue;
				}
				if (instruction is CfgEvaluateInstruction) {
					var evaluation = (CfgEvaluateInstruction) instruction;
					inspect_value (evaluation.value, step, block, false, captured_views.contains (evaluation.result));
				}
				if (instruction is CfgInitialize) {
					var initialization = (CfgInitialize) instruction;
					inspect_place (initialization.target, step, block);
					inspect_value (initialization.value, step, block);
				}
				if (instruction is CfgStore) {
					if (view_place (((CfgStore) instruction).target)) {
						throw new EnumContractError.INVALID_GRAPH ("enum inspection array view is read-only");
					}
					inspect_place (((CfgStore) instruction).target, step, block);
					inspect_value (((CfgStore) instruction).value, step, block);
				}
				if (instruction is CfgArrayInitialize) {
					foreach (var element in ((CfgArrayInitialize) instruction).elements) {
						inspect_value (element, step, block);
					}
					foreach (var field in ((CfgArrayInitialize) instruction).record_fields) {
						inspect_place (field, step, block);
					}
				}
				if (instruction is CfgValidatePlace) {
					inspect_place (((CfgValidatePlace) instruction).place, step, block);
				}
				if (instruction is CfgCleanupInstruction) {
					inspect_value (((CfgCleanupInstruction) instruction).value, step, block);
				}
				if (instruction is CfgCCallInstruction) {
					foreach (var argument in ((CfgCCallInstruction) instruction).arguments) {
						inspect_value (argument, step, block);
					}
				}
				if (instruction is CfgBufferAllocate) {
					inspect_value (((CfgBufferAllocate) instruction).count, step, block);
				}

			}
			var final = new EnumFlowStep ();
			flow.steps.add (final);
			var dispatch = block.terminator as CfgEnumDispatch;
			if (dispatch != null) {
				read (dispatch.source, final);
				if (dispatch.cases.length != dispatch.source.definition.variant_count || dispatch.invalid_target == null || !(dispatch.invalid_target.terminator is CfgEnumInvalidTag)) {
					throw new EnumContractError.INVALID_GRAPH ("enum dispatch must cover every valid tag and reject invalid tags");
				}
				for (uint v = 0; v < dispatch.cases.length; v++) {
					if (dispatch.cases[v].variant != dispatch.source.definition.variant (v) || dispatch.cases[v].target == null) {
						throw new EnumContractError.INVALID_GRAPH ("enum dispatch variant/edge correspondence mismatch");
					}
				}
			}
			var returned = block.terminator as CfgEnumReturn;
			if (returned != null) {
				if (returned.source.definition.semantic_type != function.return_type) {
					throw new EnumContractError.INVALID_GRAPH ("enum return requires its exact nominal result type");
				}
				consume (returned.source, final);
			}
			if (block.terminator is CfgConditionalBranch) {
				inspect_value (((CfgConditionalBranch) block.terminator).condition, final, block);
			}
			if (block.terminator is CfgReturn && ((CfgReturn) block.terminator).value != null) {
				inspect_value (((CfgReturn) block.terminator).value, final, block);
			}
			if (block.terminator is CfgStructReturn) {
				foreach (var leaf in ((CfgStructReturn) block.terminator).leaves) {
					inspect_value (leaf, final, block);
				}
			}
			if (block.terminator is CfgAllocationFailureTrap && ((CfgAllocationFailureTrap) block.terminator).failure.captured_receiver != null) {
				inspect_value (((CfgAllocationFailureTrap) block.terminator).failure.captured_receiver, final, block);
			}

			blocks.add (flow);
		}
		foreach (var parameter in function.parameters) {
			if (parameter.semantic_type is EnumType && !acquired.contains (parameter)) {
				throw new EnumContractError.INVALID_GRAPH ("enum parameter is missing its independent entry snapshot");
			}
		}
		var roots = new int[function.enum_slots.length];
		foreach (var slot in function.enum_slots) {
			roots[slot.ordinal] = slot.inspection_root == null ? -1 : slot.inspection_root.ordinal;
		}
		var loans = new int[function.enum_slots.length];
		foreach (var slot in function.enum_slots) {
			loans[slot.ordinal] = slot.ordinal;
		}
		bool changed_loans = true;
		uint loan_rounds = 0;
		while (changed_loans) {
			if (loan_rounds++ > function.enum_slots.length) {
				throw new EnumContractError.INVALID_GRAPH ("cyclic enum inspection loan association");
			}
			changed_loans = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var extract = instruction as CfgEnumExtractSum;
					if (extract != null && extract.destination.inspection_root != null) {
						int prior = loans[extract.destination.ordinal];
						loans[extract.destination.ordinal] = loans[extract.source.ordinal];
						changed_loans = changed_loans || prior != loans[extract.destination.ordinal];
					}
				}
			}
		}
		var owners = new bool[function.enum_slots.length];
		foreach (var slot in function.enum_slots) {
			owners[slot.ordinal] = owning (slot) && slot.inspection_root == null;
		}
		EnumInitializationProof.verify ((int) function.enum_slots.length, function.entry.ordinal, blocks, owners, roots, loans);
	}
}
}
