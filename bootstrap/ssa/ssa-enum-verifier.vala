// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Ssa {
internal class SsaEnumVerifier : Object {
	private HashTable<EnumType, EnumDefinition> definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private SsaFunction function;
	private SsaProgram program;
	private unowned CopyabilityFields records;
	private int[] writes;
	private HashTable<SsaValue, SsaEnumSlot> views = new HashTable<SsaValue, SsaEnumSlot> (direct_hash, direct_equal);
	private SsaEnumVerifier (CopyabilityFields records, SsaProgram program) {
		this.records = records;
		this.program = program;
	}

	internal static void verify(SsaProgram program, CopyabilityFields records) throws SsaError {
		if (program.enums.length == 0) {
			foreach (var function in program.functions) {
				if (function.enum_slots.length != 0 || function.return_type is EnumType) {
					throw new SsaError.INVALID_SSA ("enum carriers require a registered nominal definition");
				}
				foreach (var parameter in function.parameters) {
					if (parameter.semantic_type is EnumType) {
						throw new SsaError.INVALID_SSA ("enum parameters require a registered nominal definition");
					}
				}
			}
			foreach (var function in program.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						if (instruction is SsaAsyncRunStatus || instruction is SsaEnumConstruct || instruction is SsaEnumCopy || instruction is SsaEnumAcquire || instruction is SsaEnumExtractSum || instruction is SsaEnumTagInstruction || instruction is SsaEnumRead || instruction is SsaEnumReadRecord || instruction is SsaEnumReadScalar || instruction is SsaEnumReadBuffer || instruction is SsaEnumScalarCapture || instruction is SsaEnumScalarAbort || instruction is SsaEnumBufferCapture || instruction is SsaEnumBufferAbort || instruction is SsaEnumFinishArm || instruction is SsaEnumEndInspection || instruction is SsaEnumDrop || instruction is SsaEnumCommit) {
							throw new SsaError.INVALID_SSA ("enum operations require a registered nominal definition and owned carrier");
						}
					}
					if (block.is_complete && (block.terminator is SsaEnumDispatch || block.terminator is SsaEnumInvalidTag || block.terminator is SsaEnumReturn)) {
						throw new SsaError.INVALID_SSA ("enum control requires a registered nominal definition and owned carrier");
					}
				}
			}
			foreach (var function in program.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCallInstruction;
						if (call == null) {
							continue;
						}
						if (call.enum_result != null) {
							throw new SsaError.INVALID_SSA ("enum call result requires a registered nominal definition and owned carrier");
						}
						foreach (var argument in call.arguments) {
							if (argument.semantic_type is EnumType) {
								throw new SsaError.INVALID_SSA ("enum call argument requires a registered nominal definition and owned carrier");
							}
						}
					}
				}
			}
			return;
		}
		var proof = new SsaEnumVerifier (records, program);
		foreach (var definition in program.enums) {
			if (proof.definitions.contains (definition.semantic_type)) {
				throw new SsaError.INVALID_SSA ("duplicate enum definition");
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
			throw new SsaError.INVALID_SSA ("invalid enum contract: %s", error.message);
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

	private bool parameter_owned(SsaFunctionParameter parameter) {
		foreach (var candidate in function.parameters) {
			if (candidate == parameter) {
				return true;
			}
		}
		return false;
	}

	private void slot(SsaEnumSlot slot) throws EnumContractError {
		if (slot.ordinal < 0 || slot.ordinal >= function.enum_slots.length || function.enum_slots[slot.ordinal] != slot || definitions.lookup (slot.definition.semantic_type) != slot.definition) {
			throw new EnumContractError.INVALID_GRAPH ("enum slot lost its exact function, nominal definition or instance");
		}
	}

	private void write(SsaEnumSlot destination, EnumFlowStep step) throws EnumContractError {
		slot (destination);
		writes[destination.ordinal]++;
		if ((destination.source_ordinal < 0 || (destination.parameter_ordinal >= 0 && !owning (destination))) && writes[destination.ordinal] > 1) {
			throw new EnumContractError.INVALID_GRAPH ("enum scratch slot has multiple producers");
		}
		step.writes.add (destination.ordinal);
	}

	private bool owning(SsaEnumSlot source) {
		return EnumValueAuthority.owns (source.definition, definition);
	}

	private void consume(SsaEnumSlot source, EnumFlowStep step) throws EnumContractError {
		read (source, step);
		if (owning (source)) {
			if (source.inspection_root != null) {
				throw new EnumContractError.INVALID_GRAPH ("enum inspection view cannot transfer ownership");
			}
			step.transfers.add (source.ordinal);
			step.kills.add (source.ordinal);
		}
	}

	private void read(SsaEnumSlot source, EnumFlowStep step) throws EnumContractError {
		slot (source);
		step.reads.add (source.ordinal);
		if (source.inspection_root != null) {
			slot (source.inspection_root);
			step.reads.add (source.inspection_root.ordinal);
		}
	}

	private void selected_variant(SsaEnumSlot source, EnumVariant variant, SsaBlock block) throws EnumContractError {
		bool selected = false;
		foreach (var predecessor in function.blocks) {
			foreach (var successor in predecessor.terminator.successors ()) {
				if (successor != block) {
					continue;
				}
				var dispatch = predecessor.terminator as SsaEnumDispatch;
				if (dispatch == null || dispatch.source != source || dispatch.invalid_edge.target == block) {
					throw new EnumContractError.INVALID_GRAPH ("payload projection lacks a dominating exact active-variant dispatch");
				}
				foreach (var branch in dispatch.cases) {
					if (branch.edge.target == block) {
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
	private void binding_disposition(SsaEnumSlot source, EnumField field, SsaInstruction extraction, SsaBlock block) throws EnumContractError {
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
			var finish = instruction as SsaEnumFinishArm;
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

	private void projection(SsaEnumSlot source, EnumField field, StructLeafPath? path, SemanticType result, SsaBlock block) throws EnumContractError {
		slot (source);
		if (source.source_ordinal >= 0) {
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

	private void inspect_value(SsaValue value, EnumFlowStep step, SsaBlock block, bool argument = false) throws EnumContractError {
		if (value is SsaEnumArgument) {
			if (!argument) {
				throw new EnumContractError.INVALID_GRAPH ("enum carrier is not an ordinary value");
			}
			consume (((SsaEnumArgument) value).source, step);
			return;
		}

	}

	private void read_view(SsaValue value, EnumFlowStep step) throws EnumContractError {
		var source = views.lookup (value);
		if (source != null) {
			read (source, step);
		}
	}

	private void read_place_view(SsaMemoryPlace place, EnumFlowStep step) throws EnumContractError {
		if (place is SsaFieldPlace && ((SsaFieldPlace) place).aggregate != null) {
			read_place_view (((SsaFieldPlace) place).aggregate, step);
		}
		if (place is SsaSliceElementPlace) {
			read_view (((SsaSliceElementPlace) place).slice, step);
		}
	}

	private void verify_function(SsaFunction input) throws EnumContractError {
		views.remove_all ();
		foreach (var block in input.blocks) {
			foreach (var instruction in block.instructions) {
				var payload = instruction as SsaEnumRead;
				if (payload != null && (payload.field.owns_scalar || payload.field.owns_record)) {
					throw new EnumContractError.INVALID_GRAPH ("owned enum scalar requires an exact consuming binding, never a copied projection");
				}
				if (payload != null && payload.field.owns_buffer) {
					if (payload.source.inspection_root == null) {
						throw new EnumContractError.INVALID_GRAPH ("owning buffer field cannot enter copied slice projection");
					}
					views.insert (payload.result, payload.source);
				}
			}
		}
		function = input;
		writes = new int[function.enum_slots.length];
		var acquired = new HashTable<SsaFunctionParameter, bool> (direct_hash, direct_equal);
		foreach (var contract in function.enum_projections) {
			if (!contract.matches ()) {
				throw new EnumContractError.INVALID_GRAPH ("SSA enum projection lost intended instance/field/binding/result correspondence");
			}
		}
		foreach (var slot in function.enum_slots) {
			this.slot (slot);
		}
		var blocks = new GenericArray<EnumFlowBlock> ();
		foreach (var block in function.blocks) {
			var flow = new EnumFlowBlock ();
			flow.normal_exit = block.terminator is SsaReturn || block.terminator is SsaFunctionEnd;
			foreach (var successor in block.terminator.successors ()) {
				flow.successors.add (successor.ordinal);
			}
			foreach (var instruction in block.instructions) {
				var step = new EnumFlowStep ();
				flow.steps.add (step);
				if (instruction is SsaSliceLengthInstruction) {
					read_view (((SsaSliceLengthInstruction) instruction).slice, step);
				}
				if (instruction is SsaSliceBoundsCheck) {
					read_view (((SsaSliceBoundsCheck) instruction).slice, step);
				}
				if (instruction is SsaLoadInstruction) {
					read_place_view (((SsaLoadInstruction) instruction).source, step);
				}
				if (instruction is SsaValidatePlaceInstruction) {
					read_place_view (((SsaValidatePlaceInstruction) instruction).place, step);
				}
				var ended = instruction as SsaEnumEndInspection;
				if (ended != null) {
					slot (ended.source);
					if (ended.source.inspection_root == null) {
						throw new EnumContractError.INVALID_GRAPH ("inspection end requires its exact view");
					}
					step.ends.add (ended.source.ordinal);
					continue;
				}
				var buffer_extraction = instruction as SsaEnumReadBuffer;
				if (buffer_extraction != null) {
					var extraction = buffer_extraction;
					if (!extraction.field.owns_buffer || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.pair.shape.slice_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("owned enum buffer binding lost exact active field/owner correspondence");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var record_extraction = instruction as SsaEnumReadRecord;
				if (record_extraction != null) {
					var extraction = record_extraction;
					if (!extraction.field.owns_record || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.results.shape.semantic_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("enum record binding lost its exact consuming active field and result");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var scalar_extraction = instruction as SsaEnumReadScalar;
				if (scalar_extraction != null) {
					var extraction = scalar_extraction;
					if (!extraction.field.owns_scalar || extraction.source.inspection_root != null || extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.owner.source_ordinal != extraction.binding.local_ordinal || extraction.result.semantic_type != extraction.field.semantic_type) {
						throw new EnumContractError.INVALID_GRAPH ("enum scalar binding lost its exact selected field and fresh owner");
					}
					projection (extraction.source, extraction.field, null, extraction.field.semantic_type, block);
					binding_disposition (extraction.source, extraction.field, extraction, block);
					read (extraction.source, step);
					continue;
				}
				var finish = instruction as SsaEnumFinishArm;
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
							var buffer = prior as SsaEnumReadBuffer;
							var scalar = prior as SsaEnumReadScalar;
							var record = prior as SsaEnumReadRecord;
							var sum = prior as SsaEnumExtractSum;
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
						if (prior is SsaEnumReadBuffer) {
							var extract = (SsaEnumReadBuffer) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is SsaEnumReadScalar) {
							var extract = (SsaEnumReadScalar) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is SsaEnumReadRecord) {
							var extract = (SsaEnumReadRecord) prior;
							if (extract.source == finish.source) {
								field = extract.field;
							}
						}
						if (prior is SsaEnumExtractSum) {
							var extract = (SsaEnumExtractSum) prior;
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
				var commit = instruction as SsaEnumCommit;
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
				var drop = instruction as SsaEnumDrop;
				if (drop != null) {
					slot (drop.source);
					if (!owning (drop.source) || drop.source.inspection_root != null) {
						throw new EnumContractError.INVALID_GRAPH ("enum cleanup requires exact owning carrier, never a view");
					}
					step.kills.add (drop.source.ordinal);
					step.destroys.add (drop.source.ordinal);
					continue;
				}
				var run = instruction as SsaAsyncRunStatus;
				if (run != null) {
					if (run.operation.contract.kind != AsyncOperationKind.RUN || run.destination.definition.semantic_type != run.operation.contract.runtime.status_type || !run.destination.definition.payload_free || run.destination.definition.variant_count != 2) {
						throw new EnumContractError.INVALID_GRAPH ("run status requires its exact ordinary Completed/Cancelled enum");
					}
					write (run.destination, step);
					continue;
				}
				var construction = instruction as SsaEnumConstruct;
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
							if (supplied.buffer == null || supplied.sum != null || supplied.leaves.length != 0 || supplied.buffer.shape.slice_type != field.semantic_type) {
								throw new EnumContractError.INVALID_GRAPH ("owning enum payload requires its exact complete buffer capture");
							}
						} else if (field.owns_scalar) {
							var owner = supplied.scalar_owner;
							if (owner == null || supplied.buffer != null || supplied.sum != null || supplied.leaves.length != 1 || supplied.leaves[0] != owner.pointer || owner.pointer.semantic_type != field.semantic_type || owner.owner.cleanup.is_heap_object != field.owns_child || (field.owned_cleanup != null && owner.owner.cleanup.external_symbol != field.owned_cleanup.external_symbol)) {
								throw new EnumContractError.INVALID_GRAPH ("enum scalar field lost its original owner capture and cleanup");
							}
						} else if (field.owns_record) {
							var move = supplied.record_move;
							if (move == null || move.consumer != construction || move.use_kind != StructResultUseKind.ENUM_PAYLOAD || move.shape.semantic_type != field.semantic_type || move.leaves.length != supplied.leaves.length || supplied.sum != null || supplied.buffer != null || supplied.scalar_owner != null || !block.instructions.find (move)) {
								throw new EnumContractError.INVALID_GRAPH ("enum record payload requires its original complete nominal field commit");
							}
							for (int l = 0; l < supplied.leaves.length; l++) {
								if (supplied.leaves[l] != move.leaves[l]) {
									throw new EnumContractError.INVALID_GRAPH ("enum record payload changed an original physical field channel");
								}
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
				var copy = instruction as SsaEnumCopy;
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
				var acquisition = instruction as SsaEnumAcquire;
				if (acquisition != null) {
					if (block != function.entry || acquisition.parameter.semantic_type != acquisition.destination.definition.semantic_type || !parameter_owned (acquisition.parameter) || !(acquisition.destination.source_ordinal >= 0 && acquisition.destination.parameter_ordinal == acquisition.parameter.ordinal)) {
						throw new EnumContractError.INVALID_GRAPH ("enum parameter acquisition lost its exact entry storage/parameter association");
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
				var extraction = instruction as SsaEnumExtractSum;
				if (extraction != null) {
					if (extraction.binding.instance != extraction.source.instance || extraction.binding.field != extraction.field.identity || extraction.destination.source_ordinal != extraction.binding.local_ordinal) {
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
				if (instruction is SsaTaskSuccess) {
					var success = (SsaTaskSuccess) instruction;
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
				if (instruction is SsaGroupCallSuccess) {
					var success = (SsaGroupCallSuccess) instruction;
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
				var call = instruction as SsaCallInstruction;
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
					if (call is SsaTaskCreate) {
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
				if (instruction is SsaEnumTagInstruction) {
					read (((SsaEnumTagInstruction) instruction).source, step);
				}
				if (instruction is SsaEnumRead) {
					bool planned = false;
					foreach (var contract in function.enum_projections) {
						if (contract.instruction == instruction) {
							planned = true;
						}
					}
					if (!planned) {
						throw new EnumContractError.INVALID_GRAPH ("SSA enum projection lacks its independently retained input plan");
					}
					var payload = (SsaEnumRead) instruction;
					if (payload.binding.instance != payload.source.instance || payload.binding.field != payload.field.identity) {
						throw new EnumContractError.INVALID_GRAPH ("enum projection lost intended selected binding");
					}
					projection (payload.source, payload.field, payload.record_path, payload.result.semantic_type, block);
					read (payload.source, step);
				}
			}
			var final = new EnumFlowStep ();
			flow.steps.add (final);
			var dispatch = block.terminator as SsaEnumDispatch;
			if (dispatch != null) {
				read (dispatch.source, final);
				if (dispatch.cases.length != dispatch.source.definition.variant_count || dispatch.invalid_edge.target == null || !(dispatch.invalid_edge.target.terminator is SsaEnumInvalidTag)) {
					throw new EnumContractError.INVALID_GRAPH ("enum dispatch must cover every valid tag and reject invalid tags");
				}
				for (uint v = 0; v < dispatch.cases.length; v++) {
					if (dispatch.cases[v].variant != dispatch.source.definition.variant (v) || dispatch.cases[v].edge.target == null) {
						throw new EnumContractError.INVALID_GRAPH ("enum dispatch variant/edge correspondence mismatch");
					}
				}
			}
			var returned = block.terminator as SsaEnumReturn;
			if (returned != null) {
				if (returned.source.definition.semantic_type != function.return_type) {
					throw new EnumContractError.INVALID_GRAPH ("enum return requires its exact nominal result type");
				}
				consume (returned.source, final);
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
					var extract = instruction as SsaEnumExtractSum;
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
