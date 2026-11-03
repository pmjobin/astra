// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenericBodies {
private CheckedProgram check() throws GLib.Error {
	string text;
	string path = "tests/language-generalization-10/generic-body.astra";
	FileUtils.get_contents (path, out text);
	var files = new GenericArray<SourceFile> ();
	files.add (new SourceFile.from_text (path, text));
	var parsed = SyntaxProgram.parse (new SourceSet (files));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (parsed.program);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private CoreProgram core() throws GLib.Error {
	return CoreGenericMonomorphizer.build (CoreBuilder.build (check ()));
}

private CheckedProgram resource_sample() throws GLib.Error {
	string source, template, api;
	FileUtils.get_contents ("tests/language-generalization-10/generic-resource.astra", out source);
	FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-resource.astra", template + source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private CheckedProgram record_sample(bool storage_only = false) throws GLib.Error {
	string source, template;
	FileUtils.get_contents ("tests/language-generalization-10/generic-record.astra", out source);
	FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
	if (storage_only) {
		template = "class Shelf<T>{owned T[slots] entries;init(){this.entries=new T[slots];}}";
		source = "struct Plain{int x;int y;}int main(){var shelf=new Shelf<Plain>();return 0;}";
	}
	var parsed = Parser.parse (new SourceFile.from_text ("generic-record.astra", template + source));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private CoreClass core_depot(CoreProgram program, string argument) {
	foreach (var owner in program.classes) {
		if (owner.generic_instance != null && owner.generic_instance.argument.display_name () == argument) {
			return owner;
		}
	}
	assert_not_reached ();
}

private CfgClass cfg_depot(CfgProgram program, string argument) {
	foreach (var owner in program.classes) {
		if (owner.generic_instance != null && owner.generic_instance.argument.display_name () == argument) {
			return owner;
		}
	}
	assert_not_reached ();
}

private SsaClass ssa_depot(SsaProgram program, string argument) {
	foreach (var owner in program.classes) {
		if (owner.generic_instance != null && owner.generic_instance.argument.display_name () == argument) {
			return owner;
		}
	}
	assert_not_reached ();
}

private void independent() {
	try {
		CheckedProgram? checked = check ();
		var old = WeakRef (checked.classes[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (old.get () == null);
		CoreVerifier.verify (c);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (c);
		c = null;
		old = WeakRef (core_depot (concrete, "Entry"));
		CfgProgram? g = CfgBuilder.build (concrete);
		concrete = null;
		assert (old.get () == null);
		CfgVerifier.verify (g);
		old = WeakRef (cfg_depot (g, "Entry"));
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		assert (old.get () == null);
		SsaVerifier.verify (s);
		assert (ssa_depot (s, "Entry").methods[1].blocks.length > 1);
		old = WeakRef (ssa_depot (s, "Entry"));
		var n = NativeAbiBuilder.build (s);
		CAbiProgram? cabi = CAbiBuilder.build (s, n);
		var artifact = LlvmLowering.lower (s, n, cabi);
		cabi = null;
		s = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (n);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void concrete_keys() {
	try {
		var p = core ();
		var a = core_depot (p, "Entry");
		var b = core_depot (p, "Other");
		var key = a.generic_instance;
		a.generic_instance = b.generic_instance.copy ();
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (p);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		a.generic_instance = key;
		CoreVerifier.verify_concrete (p);
		var method = a.methods[3];
		var result = method.return_type;
		method.return_type = a.semantic_type;
		rejected = false;
		try {
			CoreVerifier.verify_concrete (p);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		method.return_type = result;
		CoreVerifier.verify_concrete (p);
		var g = CfgBuilder.build (p);
		var ga = cfg_depot (g, "Entry");
		var gb = cfg_depot (g, "Other");
		key = ga.generic_instance;
		ga.generic_instance = gb.generic_instance.copy ();
		rejected = false;
		try {
			CfgVerifier.verify (g);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		ga.generic_instance = key;
		CfgVerifier.verify (g);
		var s = SsaBuilder.build (g);
		var sa = ssa_depot (s, "Entry");
		var sb = ssa_depot (s, "Other");
		key = sa.generic_instance;
		sa.generic_instance = sb.generic_instance.copy ();
		rejected = false;
		try {
			SsaVerifier.verify (s);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		sa.generic_instance = key;
		SsaVerifier.verify (s);
		var n = NativeAbiBuilder.build (s);
		var na = n.classes[sa.ordinal];
		var native_key = na.generic_instance;
		var targets = new int[native_key.member_count];
		for (int i = 0; i < targets.length; i++) {
			targets[i] = native_key.member_target (i);
		}
		targets[1] = n.classes[sb.ordinal].generic_instance.member_target (1);
		na.generic_instance = new NativeExactClassInstance (native_key.definition, native_key.argument_ordinal, targets);
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		na.generic_instance = native_key;
		NativeAbiVerifier.verify (n);
		var append = n.functions[native_key.member_target (3)];
		var origin = append.signature.parameters[0].object_origin;
		append.signature.parameters[0].object_origin = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		append.signature.parameters[0].object_origin = origin;
		NativeAbiVerifier.verify (n);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void resource_authority() {
	try {
		CheckedProgram? checked = resource_sample ();
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		var ca = core_depot (c, "R");
		var cb = core_depot (c, "Other");
		var cleanup = ca.fields[0].slots_cleanup;
		ca.fields[0].slots_cleanup = cb.fields[0].slots_cleanup;
		bool rejected = false;
		try {
			CoreVerifier.verify (c);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		ca.fields[0].slots_cleanup = cleanup;
		CoreVerifier.verify (c);
		var old = WeakRef (ca);
		ca = null;
		cb = null;
		cleanup = null;
		CfgProgram? g = CfgBuilder.build (c);
		c = null;
		assert (old.get () == null);
		var ga = cfg_depot (g, "R");
		var gb = cfg_depot (g, "Other");
		var cfg_cleanup = ga.fields[0].slots_cleanup;
		ga.fields[0].slots_cleanup = gb.fields[0].slots_cleanup;
		rejected = false;
		try {
			CfgVerifier.verify (g);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		ga.fields[0].slots_cleanup = cfg_cleanup;
		CfgVerifier.verify (g);
		old = WeakRef (ga);
		ga = null;
		gb = null;
		cfg_cleanup = null;
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		assert (old.get () == null);
		var sa = ssa_depot (s, "R");
		var sb = ssa_depot (s, "Other");
		var ssa_cleanup = sa.fields[0].slots_cleanup;
		sa.fields[0].slots_cleanup = sb.fields[0].slots_cleanup;
		rejected = false;
		try {
			SsaVerifier.verify (s);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		sa.fields[0].slots_cleanup = ssa_cleanup;
		SsaVerifier.verify (s);
		int disarms = 0;
		foreach (var method in sa.methods) {
			foreach (var block in method.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var effect = block.instructions[i] as SsaSlotsEffect;
					if (effect == null || (effect.action != SsaSlotsAction.APPEND && effect.action != SsaSlotsAction.REPLACE)) {
						continue;
					}
					var disarm = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					rejected = false;
					try {
						SsaVerifier.verify (s);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i + 1, disarm);
					SsaVerifier.verify (s);
					disarms++;
				}
			}
		}
		assert (disarms == 2);
		var n = NativeAbiBuilder.build (s);
		var na = n.classes[sa.ordinal];
		var nb = n.classes[sb.ordinal];
		var key = na.generic_instance;
		na.generic_instance = nb.generic_instance;
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		na.generic_instance = key;
		NativeAbiVerifier.verify (n);
		var field = na.fields[0];
		var slots = (NativeOwnerSlotsType) field.storage_type;
		var forged = new NativeOwnerSlotsType (-1, slots.element_name, -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, new NativeScalarOwner (slots.element_name, nb.generic_instance.resource_argument.cleanup_symbol));
		na.fields[0] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, false, forged, -1);
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		na.fields[0] = field;
		NativeAbiVerifier.verify (n);
		NativeFunction? append = null;
		for (int i = 0; i < key.member_count; i++) {
			if (key.definition.member_name (i) == "append") {
				append = n.functions[key.member_target (i)];
			}
		}
		assert (append != null);
		var parameter = append.signature.parameters[0];
		append.signature.parameters[0] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, parameter.abi_type);
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		append.signature.parameters[0] = parameter;
		NativeAbiVerifier.verify (n);
		old = WeakRef (sa);
		sa = null;
		sb = null;
		ssa_cleanup = null;
		CAbiProgram? cabi = CAbiBuilder.build (s, n);
		var artifact = LlvmLowering.lower (s, n, cabi);
		s = null;
		cabi = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (n);
		artifact.verify ();
		int switched = 0;
		var wrong = CApi.named_function (artifact.module, "of_release_other");
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.slots.resource.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var target = CApi.called_value (instruction);
					if (CApi.value_name (target, out length) != "of_release") {
						continue;
					}
					CApi.set_operand (instruction, CApi.argument_count (instruction), wrong);
					char* message;
					int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
					if (failed != 0) {
						GLib.error ("ordinary LLVM fixture failure: %s", (string) message);
					}
					if (message != null) {
						CApi.dispose_message (message);
					}
					rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, CApi.argument_count (instruction), target);
					artifact.verify ();
					switched++;
				}
			}
		}
		assert (switched == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_authority() {
	try {
		CheckedProgram? checked = record_sample ();
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		var ca = core_depot (c, "Count");
		var cb = core_depot (c, "OtherCount");
		var type = ca.fields[0].semantic_type;
		ca.fields[0].semantic_type = cb.fields[0].semantic_type;
		bool rejected = false;
		try {
			CoreVerifier.verify (c);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		ca.fields[0].semantic_type = type;
		CoreVerifier.verify (c);
		ca = null;
		cb = null;
		CfgProgram? g = CfgBuilder.build (c);
		c = null;
		int cfg_groups = 0;
		foreach (var function in g.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var transfer = instruction as CfgSlotsRecordTransfer;
					if (transfer == null) {
						continue;
					}
					int last = (int) transfer.leaves.length - 1;
					var leaf = transfer.leaves[last];
					transfer.leaves.remove_index (last);
					rejected = false;
					try {
						CfgVerifier.verify (g);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					transfer.leaves.add (leaf);
					CfgVerifier.verify (g);
					cfg_groups++;
				}
			}
		}
		assert (cfg_groups >= 6);
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		int ssa_groups = 0;
		int consumptions = 0;
		foreach (var function in s.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var transfer = block.instructions[i] as SsaSlotsRecordTransfer;
					if (transfer != null) {
						int last = (int) transfer.leaves.length - 1;
						var leaf = transfer.leaves[last];
						transfer.leaves.remove_index (last);
						rejected = false;
						try {
							SsaVerifier.verify (s);
						} catch (SsaError error) {
							rejected = true;
						}
						assert (rejected);
						transfer.leaves.add (leaf);
						SsaVerifier.verify (s);
						ssa_groups++;
					}
					var read = block.instructions[i] as SsaSlotsRecordRead;
					if (read == null) {
						continue;
					}
					assert (block.instructions[i + 1] is SsaStructResultConsume);
					var consume = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					rejected = false;
					try {
						SsaVerifier.verify (s);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i + 1, consume);
					SsaVerifier.verify (s);
					consumptions++;
				}
			}
		}
		assert (ssa_groups == cfg_groups && consumptions >= 4);
		var n = NativeAbiBuilder.build (s);
		var count = n.classes[ssa_depot (s, "Count").ordinal];
		var other = n.classes[ssa_depot (s, "OtherCount").ordinal];
		var key = count.generic_instance;
		count.generic_instance = other.generic_instance;
		rejected = false;
		try {
			NativeAbiVerifier.verify (n);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		count.generic_instance = key;
		NativeAbiVerifier.verify (n);
		var old = WeakRef (ssa_depot (s, "Count"));
		CAbiProgram? cabi = CAbiBuilder.build (s, n);
		var artifact = LlvmLowering.lower (s, n, cabi);
		s = null;
		cabi = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (n);
		artifact.verify ();
		int extents = 0;
		int fields = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					string value_name = CApi.value_name (instruction, out length);
					if (name.has_prefix ("astra.slots.record.") && value_name == "reserve.checked.bytes") {
						var extent = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (extent), 8, 0));
						char* message;
						int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
						assert (failed == 0);
						if (message != null) {
							CApi.dispose_message (message);
						}
						rejected = false;
						try {
							artifact.verify ();
						} catch (LlvmError error) {
							rejected = true;
						}
						assert (rejected);
						CApi.set_operand (instruction, 1, extent);
						artifact.verify ();
						extents++;
					}
					if (fields == 0 && value_name.has_prefix ("slots.record.insert") && CApi.opcode (instruction) == CApi.Opcode.INSERT_VALUE && CApi.count_params (function) > 2) {
						var original = CApi.operand (instruction, 1);
						var changed = CApi.get_param (function, 2);
						if ((void*) original == (void*) changed || (void*) CApi.type_of (original) != (void*) CApi.type_of (changed)) {
							continue;
						}
						CApi.set_operand (instruction, 1, changed);
						char* message;
						int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
						assert (failed == 0);
						if (message != null) {
							CApi.dispose_message (message);
						}
						rejected = false;
						try {
							artifact.verify ();
						} catch (LlvmError error) {
							rejected = true;
						}
						assert (rejected);
						CApi.set_operand (instruction, 1, original);
						artifact.verify ();
						fields++;
					}
				}
			}
		}
		assert (extents == 3 && fields == 1);
		var minimal = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (record_sample (true))));
		var minimal_native = NativeAbiBuilder.build (minimal);
		minimal = null;
		NativeAbiVerifier.verify (minimal_native);
		assert (minimal_native.struct_values.length == 1);
		var plan = minimal_native.struct_values[0];
		var original = plan.leaves[0];
		plan.leaves[0] = new NativeStructLeafChannel (original.field_path, new NativeScalarAbiType (NativeScalarType.F32));
		rejected = false;
		try {
			NativeAbiVerifier.verify (minimal_native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		plan.leaves[0] = original;
		NativeAbiVerifier.verify (minimal_native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram method_sample() throws GLib.Error {
	string source, api;
	FileUtils.get_contents ("tests/language-generalization-10/generic-method.astra", out source);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-method.astra", source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void method_authority() {
	try {
		CheckedProgram? checked = method_sample ();
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? initial_core = CoreBuilder.build (checked);
		CoreProgram? core = CoreGenericMonomorphizer.build (initial_core);
		initial_core = null;
		checked = null;
		assert (upstream.get () == null);
		CoreVerifier.verify_concrete (core);
		var owner = core_depot (core, "Item");
		CoreMethod? echo = null;
		CoreMethod? constant = null;
		foreach (var method in owner.methods) {
			if (method.name == "echo<int>") {
				echo = method;
			}
			if (method.name == "constant<Payload>") {
				constant = method;
			}
		}
		assert (echo != null && constant != null);
		var key = echo.generic_method_instance;
		echo.generic_method_instance = constant.generic_method_instance.copy ();
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		echo.generic_method_instance = key;
		CoreVerifier.verify_concrete (core);
		upstream = WeakRef (owner);
		owner = null;
		echo = null;
		constant = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_owner = cfg_depot (cfg, "Item");
		CfgMethod? cfg_echo = null;
		foreach (var method in cfg_owner.methods) {
			if (method.name == "echo<int>") {
				cfg_echo = method;
			}
		}
		assert (cfg_echo != null);
		key = cfg_echo.generic_method_instance;
		cfg_echo.generic_method_instance = null;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg_echo.generic_method_instance = key;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg_owner);
		cfg_owner = null;
		cfg_echo = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		SsaVerifier.verify (ssa);
		var ssa_owner = ssa_depot (ssa, "Item");
		SsaMethod? forward = null;
		foreach (var method in ssa_owner.methods) {
			if (method.name == "forward<int>") {
				forward = method;
			}
		}
		assert (forward != null && forward.heap_result);
		forward.heap_result = false;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		forward.heap_result = true;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		upstream = WeakRef (ssa_owner);
		ssa_owner = null;
		forward = null;
		ssa = null;
		cabi = null;
		assert (upstream.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		NativeParameter? raw = null;
		NativeClassPlan? payload_class = null;
		foreach (var plan in native.classes) {
			if (plan.name == "Item") {
				payload_class = plan;
			}
		}
		foreach (var function in native.functions) {
			if (function.name != "echo<Payload>") {
				continue;
			}
			foreach (var parameter in function.signature.parameters) {
				if (parameter.abi_type is NativeScalarAbiType && parameter.scalar_type == NativeScalarType.PTR) {
					raw = parameter;
				}
			}
		}
		assert (raw != null && payload_class != null && raw.object_origin == null);
		raw.object_origin = new NativeObjectOriginPlan (payload_class.ordinal, payload_class.name, true);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = error.message.contains ("copied record leaf");
		}
		assert (rejected);
		raw.object_origin = null;
		NativeAbiVerifier.verify (native);
		NativeFunction? target = null;
		foreach (var function in native.functions) {
			if (function.name == "constant<Payload>") {
				target = function;
				break;
			}
		}
		assert (target != null);
		var binding = target.generic_method_instance;
		var native_owner = native.classes[binding.class_ordinal].generic_instance;
		assert (binding != null && binding.argument.record != null);
		target.generic_method_instance = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.generic_method_instance = binding;
		NativeAbiVerifier.verify (native);
		int rank = -1;
		for (int i = 0; i < native_owner.generic_methods.length; i++) {
			if (native_owner.generic_methods[i] == binding) {
				rank = i;
			}
		}
		assert (rank >= 0);
		var forged = new NativeGenericMethodInstance (binding.definition, binding.class_ordinal, binding.member, binding.target_ordinal, new NativeCopyType ("Payload", new NativeScalarAbiType (NativeScalarType.I32)));
		native_owner.generic_methods[rank] = forged;
		target.generic_method_instance = forged;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		native_owner.generic_methods[rank] = binding;
		target.generic_method_instance = binding;
		NativeAbiVerifier.verify (native);
		var leaf = binding.argument.record.leaves[0];
		binding.argument.record.leaves[0] = new NativeStructLeafChannel (leaf.field_path, new NativeScalarAbiType (NativeScalarType.F32));
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		binding.argument.record.leaves[0] = leaf;
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram owning_sample() throws GLib.Error {
	string source, template, errors, api;
	FileUtils.get_contents ("tests/language-generalization-10/generic-owning-record.astra", out source);
	FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-owning-record.astra", template + errors + source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void owning_record_authority() {
	try {
		CheckedProgram? checked = owning_sample ();
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CoreVerifier.verify (core);
		int copied_owners = 0;
		foreach (var owner in core.classes) {
			foreach (var method in owner.methods) {
				for (int i = 0; i < method.body.statements.length; i++) {
					var transfer = method.body.statements[i] as CoreSlotsRecordTransfer;
					if (transfer == null) {
						continue;
					}
					var move = transfer.value as CoreStructMoveProducer;
					assert (move != null);
					method.body.statements[i] = new CoreSlotsRecordTransfer (transfer.span, transfer.store, transfer.index, new CoreStructSnapshot (move.span, move.source.place));
					bool rejected = false;
					try {
						CoreVerifier.verify (core);
					} catch (CoreError error) {
						rejected = true;
					}
					assert (rejected);
					method.body.statements[i] = transfer;
					CoreVerifier.verify (core);
					copied_owners++;
				}
			}
		}
		assert (copied_owners == 4);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		int commits = 0;
		int takes = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var transfer = block.instructions[i] as CfgSlotsRecordTransfer;
					if (transfer != null) {
						var move = transfer.record_move;
						assert (move != null && move.shape.mode == StructValueMode.MOVE_VALUE);
						transfer.record_move = null;
						bool rejected = false;
						try {
							CfgVerifier.verify (cfg);
						} catch (CfgError error) {
							rejected = true;
						}
						assert (rejected);
						transfer.record_move = move;
						CfgVerifier.verify (cfg);
						commits++;
					}
					var read = block.instructions[i] as CfgSlotsRecordRead;
					if (read == null) {
						continue;
					}
					assert (read.remove && read.results.shape.mode == StructValueMode.MOVE_VALUE && block.instructions[i + 2] is CfgStructBoundaryAcquire);
					var acquire = block.instructions[i + 2];
					block.instructions.remove_index (i + 2);
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i + 2, acquire);
					CfgVerifier.verify (cfg);
					takes++;
				}
			}
		}
		assert (commits == 4 && takes == 2);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		int disarms = 0;
		int acquired_groups = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var read = block.instructions[i] as SsaSlotsRecordRead;
					if (read != null) {
						assert (read.remove && block.instructions[i + 2] is SsaStructBoundaryAcquire);
						var acquire = block.instructions[i + 2];
						block.instructions.remove_index (i + 2);
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							rejected = true;
						}
						assert (rejected);
						block.instructions.insert (i + 2, acquire);
						SsaVerifier.verify (ssa);
						acquired_groups++;
					}
					var move = block.instructions[i] as SsaStructBoundaryMove;
					if (move == null || move.shape.semantic_type.display_name () != "Packet" || !(move.consumer is SsaSlotsRecordTransfer)) {
						continue;
					}
					assert (move.owners.length == 3 && move.buffers.length == 1 && block.instructions[i + 1] is SsaHeapOwnerEvent);
					var disarm = block.instructions[i + 1];
					block.instructions.remove_index (i + 1);
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i + 1, disarm);
					SsaVerifier.verify (ssa);
					int next = i + 1 + (int) move.owners.length;
					assert (block.instructions[next] is SsaBufferWriteInstruction);
					var buffer_disarm = block.instructions[next];
					block.instructions.remove_index (next);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (next, buffer_disarm);
					SsaVerifier.verify (ssa);
					disarms++;
				}
			}
		}
		assert (disarms == 2 && acquired_groups == 2);
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		cabi = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		NativeOwnerSlotsType? slots = null;
		foreach (var owner in native.classes) {
			if (owner.name == "Vector<Packet>") {
				slots = owner.fields[0].storage_type as NativeOwnerSlotsType;
			}
		}
		assert (slots != null && slots.record_value.mode == NativeStructValueMode.MOVE_VALUE && slots.record_value.ownership.length == 4);
		var first = slots.record_value.ownership[0];
		var second = slots.record_value.ownership[1];
		slots.record_value.ownership[0] = second;
		slots.record_value.ownership[1] = first;
		assert (!slots.matches_record_layout ());
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		slots.record_value.ownership[0] = first;
		slots.record_value.ownership[1] = second;
		NativeAbiVerifier.verify (native);
		var wrong = CApi.named_function (artifact.module, "of_release_other");
		assert ((void*) wrong != null);
		int changed = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			if (!CApi.value_name (function, out length).has_prefix ("astra.slots.record.%d.".printf (slots.record_value.struct_ordinal))) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var target = CApi.called_value (instruction);
					if (CApi.value_name (target, out length) != "of_release") {
						continue;
					}
					CApi.set_operand (instruction, CApi.argument_count (instruction), wrong);
					char* message;
					int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
					assert (failed == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, CApi.argument_count (instruction), target);
					artifact.verify ();
					changed++;
				}
			}
		}
		assert (changed == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram owner_sample() throws GLib.Error {
	string source, template, errors, api;
	FileUtils.get_contents ("tests/language-generalization-10/generic-owner.astra", out source);
	FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-owner.astra", template + errors + source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void owner_boundaries() {
	try {
		CheckedProgram? checked = owner_sample ();
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CoreFunction? relay = null;
		foreach (var function in core.functions) {
			if (function.name == "relay") {
				relay = function;
			}
		}
		assert (relay != null && relay.heap_result && relay.parameters[0].heap_object);
		relay.heap_result = false;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		relay.heap_result = true;
		CoreVerifier.verify (core);
		relay.parameters[0].heap_object = false;
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		relay.parameters[0].heap_object = true;
		CoreVerifier.verify (core);
		relay = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		int aborted = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (!(block.instructions[i] is CfgOwnedArgumentAbort)) {
						continue;
					}
					var abort = block.instructions[i];
					block.instructions.remove_index (i);
					rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i, abort);
					CfgVerifier.verify (cfg);
					aborted++;
				}
			}
		}
		assert (aborted == 1);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		int restored = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					if (!(block.instructions[i] is SsaOwnedArgumentAbort)) {
						continue;
					}
					var abort = block.instructions[i];
					block.instructions.remove_index (i);
					rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i, abort);
					SsaVerifier.verify (ssa);
					restored++;
				}
			}
		}
		assert (restored == 1);
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		cabi = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		NativeFunction? target = null;
		NativeClassPlan? wrong = null;
		foreach (var function in native.functions) {
			if (function.name == "relay") {
				target = function;
			}
		}
		foreach (var owner in native.classes) {
			if (owner.name == "Vector<Other>") {
				wrong = owner;
			}
		}
		assert (target != null && wrong != null && target.signature.generic_owner_result_origin != null && target.signature.parameters[0].generic_owner_origin != null);
		var result = target.signature.heap_result;
		target.signature.heap_result = new NativeObjectOriginPlan (wrong.ordinal, wrong.name, true);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.signature.heap_result = result;
		NativeAbiVerifier.verify (native);
		var incoming = target.signature.parameters[0].object_origin;
		target.signature.parameters[0].object_origin = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.signature.parameters[0].object_origin = new NativeObjectOriginPlan (wrong.ordinal, wrong.name, true);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.signature.parameters[0].object_origin = incoming;
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void slot_record_cycles() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("slot-record-graph.astra", "class Leaf{init(){}}struct Packet{owned Leaf child;}class Root{owned Packet[slots] entries;init(){this.entries=new Packet[slots];}}int main(){var root=new Root();return 0;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		var core = CoreBuilder.build (checked.program);
		CoreClass? root = null;
		foreach (var owner in core.classes) {
			if (owner.name == "Root") {
				root = owner;
			}
		}
		CoreCleanupContract? cleanup = null;
		foreach (var contract in core.cleanups) {
			if (contract.is_heap_object && contract.object_class == root) {
				cleanup = contract;
			}
		}
		assert (root != null && cleanup != null && core.structs.length == 1);
		var field = core.structs[0].fields[0];
		var type = field.semantic_type;
		var original = field.owned_cleanup;
		field.semantic_type = root.semantic_type;
		field.owned_cleanup = cleanup;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = error.message.contains ("cyclic");
		}
		assert (rejected);
		field.semantic_type = type;
		field.owned_cleanup = original;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgClass? cfg_root = null;
		CfgCleanupContract? cfg_cleanup = null;
		foreach (var owner in cfg.classes) {
			if (owner.name == "Root") {
				cfg_root = owner;
			}
		}
		foreach (var contract in cfg.cleanups) {
			if (contract.is_heap_object && contract.object_class == cfg_root) {
				cfg_cleanup = contract;
			}
		}
		assert (cfg_root != null && cfg_cleanup != null);
		var cfg_field = cfg.structs[0].fields[0];
		var cfg_changed = new CfgStructField (cfg_field.span, cfg_field.name_span, cfg_field.name, cfg.structs[0], cfg_root.semantic_type, 0);
		cfg_changed.owned_cleanup = cfg_cleanup;
		cfg.structs[0].fields[0] = cfg_changed;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = error.message.contains ("cyclic");
		}
		assert (rejected);
		cfg.structs[0].fields[0] = cfg_field;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaClass? ssa_root = null;
		SsaCleanupContract? ssa_cleanup = null;
		foreach (var owner in ssa.classes) {
			if (owner.name == "Root") {
				ssa_root = owner;
			}
		}
		foreach (var contract in ssa.cleanups) {
			if (contract.is_heap_object && contract.object_class == ssa_root) {
				ssa_cleanup = contract;
			}
		}
		assert (ssa_root != null && ssa_cleanup != null);
		var ssa_field = ssa.structs[0].fields[0];
		var ssa_changed = new SsaStructField (ssa_field.span, ssa_field.name_span, ssa_field.name, ssa.structs[0], ssa_root.semantic_type, 0);
		ssa_changed.owned_cleanup = ssa_cleanup;
		ssa.structs[0].fields[0] = ssa_changed;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = error.message.contains ("cyclic");
		}
		assert (rejected);
		ssa.structs[0].fields[0] = ssa_field;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void nested_authority() {
	try {
		string source, template, api;
		FileUtils.get_contents ("tests/language-generalization-10/generic-nested.astra", out source);
		FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
		FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
		var parsed = Parser.parse (new SourceFile.from_text ("generic-nested.astra", template + source));
		var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
		assert (parsed.diagnostic == null && vapi.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		var core = CoreBuilder.build (checked.program);
		var first = core_depot (core, "Vector<Entry>");
		var other = core_depot (core, "Vector<Pair>");
		var key = first.generic_instance;
		first.generic_instance = other.generic_instance.copy ();
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		first.generic_instance = key;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_first = cfg_depot (cfg, "Vector<Entry>");
		var cfg_other = cfg_depot (cfg, "Vector<Pair>");
		key = cfg_first.generic_instance;
		cfg_first.generic_instance = cfg_other.generic_instance.copy ();
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
		}
		assert (rejected);
		cfg_first.generic_instance = key;
		CfgVerifier.verify (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		var owner = ssa_depot (ssa, "Vector<Entry>");
		var old = WeakRef (owner);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		int rank = owner.ordinal;
		owner = null;
		ssa = null;
		cabi = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		var plan = native.classes[rank];
		NativeClassPlan? wrong = null;
		foreach (var candidate in native.classes) {
			if (candidate.name == "Vector<Pair>") {
				wrong = candidate;
			}
		}
		assert (wrong != null);
		var field = plan.fields[0];
		plan.fields[0] = new NativeClassField (field.span, field.name, field.type_name, 0, false, new NativeOwnerSlotsType (wrong.ordinal, wrong.name, wrong.destructor_ordinal), -1);
		assert (!plan.matches_slot_declarations ());
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		plan.fields[0] = field;
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram cache_sample(bool asynchronous = false) throws GLib.Error {
	string source, template, errors, api;
	FileUtils.get_contents (asynchronous ? "tests/language-generalization-10/generic-cache-async.astra" : "tests/language-generalization-10/generic-cache.astra", out source);
	if (asynchronous) {
		string runtime;
		FileUtils.get_contents ("lib/astra/async/virtual.astra", out runtime);
		source = runtime + source;
	}
	FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
	FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-cache.astra", template + errors + source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void cache_channels() {
	try {
		CheckedProgram? checked = cache_sample ();
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CoreVerifier.verify (core);
		int count = 0;
		foreach (var owner in core.classes) {
			foreach (var property in owner.properties) {
				if (!property.is_owned_lazy) {
					continue;
				}
				property.factory.heap_result = false;
				bool rejected = false;
				try {
					CoreVerifier.verify (core);
				} catch (CoreError error) {
					rejected = true;
				}
				assert (rejected);
				property.factory.heap_result = true;
				CoreVerifier.verify (core);
				count++;
			}
			foreach (var field in owner.fields) {
				if (!GenericClassTypes.general (field.semantic_type)) {
					continue;
				}
				var cleanup = field.owned_cleanup;
				field.owned_cleanup = null;
				bool rejected = false;
				try {
					CoreVerifier.verify (core);
				} catch (CoreError error) {
					rejected = true;
				}
				assert (rejected);
				field.owned_cleanup = cleanup;
				CoreVerifier.verify (core);
				count++;
			}
		}
		assert (count == 2);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		CfgVerifier.verify (cfg);
		count = 0;
		foreach (var owner in cfg.classes) {
			foreach (var property in owner.properties) {
				if (!property.is_owned_lazy) {
					continue;
				}
				property.is_borrowed = false;
				bool rejected = false;
				try {
					CfgVerifier.verify (cfg);
				} catch (CfgError error) {
					rejected = true;
				}
				assert (rejected);
				property.is_borrowed = true;
				CfgVerifier.verify (cfg);
				count++;
			}
		}
		assert (count == 1);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		SsaVerifier.verify (ssa);
		count = 0;
		foreach (var owner in ssa.classes) {
			foreach (var property in owner.properties) {
				if (!property.is_owned_lazy) {
					continue;
				}
				var factory = property.factory;
				property.factory = null;
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError error) {
					rejected = true;
				}
				assert (rejected);
				property.factory = factory;
				SsaVerifier.verify (ssa);
				count++;
			}
		}
		assert (count == 1);
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		cabi = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		count = 0;
		foreach (var owner in native.classes) {
			foreach (var cache in owner.lazy_caches) {
				if (!cache.is_owned) {
					continue;
				}
				int rank = cache.owned_class_ordinal;
				cache.owned_class_ordinal = owner.ordinal;
				bool rejected = false;
				try {
					NativeAbiVerifier.verify (native);
				} catch (NativeAbiError error) {
					rejected = true;
				}
				assert (rejected);
				cache.owned_class_ordinal = rank;
				NativeAbiVerifier.verify (native);
				int factory = cache.factory_ordinal;
				cache.factory_ordinal = -1;
				rejected = false;
				try {
					NativeAbiVerifier.verify (native);
				} catch (NativeAbiError error) {
					rejected = true;
				}
				assert (rejected);
				cache.factory_ordinal = factory;
				NativeAbiVerifier.verify (native);
				count++;
			}
			for (int f = 0; f < owner.fields.length; f++) {
				var field = owner.fields[f];
				if (field.owned_class_ordinal < 0) {
					continue;
				}
				owner.fields[f] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, field.text_snapshot, field.storage_type, field.record_ordinal, field.is_private);
				assert (!owner.matches_slot_declarations ());
				bool rejected = false;
				try {
					NativeAbiVerifier.verify (native);
				} catch (NativeAbiError error) {
					rejected = true;
				}
				assert (rejected);
				owner.fields[f] = field;
				NativeAbiVerifier.verify (native);
				count++;
			}
		}
		assert (count == 2);
		int altered = 0;
		for (var f = CApi.first_function (artifact.module); (void*) f != null; f = CApi.next_function (f)) {
			for (var block = CApi.first_block (f); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
						continue;
					}
					size_t length;
					string address = CApi.value_name (CApi.operand (instruction, 1), out length);
					if (!address.has_prefix ("lazy.retire.") || !address.has_suffix (".state.address")) {
						continue;
					}
					var value = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (value), 2, 0));
					bool rejected = false;
					try {
						artifact.verify ();
					} catch (LlvmError error) {
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, 0, value);
					artifact.verify ();
					altered++;
				}
			}
		}
		assert (altered >= 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cache_suspension_owner() {
	try {
		CheckedProgram? checked = cache_sample (true);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		int worker = -1;
		foreach (var function in native.functions) {
			if (function.name == "cached_worker") {
				worker = function.ordinal;
			}
		}
		assert (worker >= 0);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		cabi = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		int acquisitions = 0;
		foreach (var frame in artifact.async_frames) {
			if (frame.plan.function_ordinal != worker) {
				continue;
			}
			bool cache_owner = false;
			for (uint o = 0; o < frame.plan.owner_count; o++) {
				int rank = frame.plan.owner (o).class_ordinal;
				if (rank >= 0 && native.classes[rank].name == "AsyncCache") {
					cache_owner = true;
				}
			}
			assert (cache_owner && frame.plan.state_count > 1);
			for (uint o = 0; o < frame.owner_write_count; o++) {
				var store = frame.owner_write (o);
				var value = CApi.operand (store, 0);
				var empty = CApi.const_null (CApi.type_of (value));
				if ((void*) value == (void*) empty) {
					continue;
				}
				CApi.set_operand (store, 0, empty);
				bool rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = error.message.contains ("exact frame owner acquisition");
				}
				assert (rejected);
				CApi.set_operand (store, 0, value);
				artifact.verify ();
				acquisitions++;
			}
			bool bypassed = false;
			for (var block = CApi.first_block (frame.destroy); (void*) block != null && !bypassed; block = CApi.next_block (block)) {
				var branch = CApi.block_terminator (block);
				if (CApi.successor_count (branch) != 2) {
					continue;
				}
				var wanted = CApi.successor (branch, 0);
				var skipped = CApi.successor (branch, 1);
				CApi.set_successor (branch, 0, skipped);
				bool rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = true;
				}
				assert (rejected);
				CApi.set_successor (branch, 0, wanted);
				artifact.verify ();
				bypassed = true;
			}
			assert (bypassed);
		}
		assert (acquisitions >= 1);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void general_nonnull() {
	try {
		string source, template;
		FileUtils.get_contents ("tests/language-generalization-10/nonnull-general.astra", out source);
		FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
		var parsed = Parser.parse (new SourceFile.from_text ("nonnull-general.astra", template + source));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		CoreVerifier.verify (core);
		CoreFunction? guarded = null;
		foreach (var function in core.functions) {
			if (function.name == "guarded") {
				guarded = function;
			}
		}
		assert (guarded != null);
		var sum = ((CoreReturn) guarded.body.statements[1]).value as CoreBinaryValue;
		assert (sum != null && sum.left is CoreBinaryValue);
		var left = (CoreBinaryValue) sum.left;
		foreach (var value in new CoreValue[] {left.left, left.right, sum.right}) {
			var call = value as CoreCallValue;
			assert (call != null && call.target.parameters[0].requires_nonnull);
			var original = call.arguments[0];
			call.arguments[0] = new CoreNullPointerValue (original.span, original.semantic_type);
			bool rejected = false;
			try {
				CoreVerifier.verify (core);
			} catch (CoreError error) {
				rejected = true;
			}
			assert (rejected);
			call.arguments[0] = original;
			CoreVerifier.verify (core);
		}
		// Drop temporary Core nodes before asserting later graph independence.
		guarded = null;
		sum = null;
		left = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		CfgVerifier.verify (cfg);
		int count = 0;
		foreach (var function in cfg.functions) {
			if (function.name != "guarded") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var node in block.instructions) {
					var call = node as CfgCallInstruction;
					if (call == null || !call.target.parameters[0].requires_nonnull) {
						continue;
					}
					var original = call.arguments[0];
					call.arguments[0] = new CfgNullPointerValue (original.span, original.semantic_type);
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = true;
					}
					assert (rejected);
					call.arguments[0] = original;
					CfgVerifier.verify (cfg);
					count++;
				}
			}
		}
		assert (count == 3);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		SsaVerifier.verify (ssa);
		count = 0;
		foreach (var function in ssa.functions) {
			if (function.name != "guarded") {
				continue;
			}
			foreach (var block in function.blocks) {
				foreach (var node in block.instructions) {
					var call = node as SsaCallInstruction;
					if (call == null || !call.target.parameters[0].requires_nonnull) {
						continue;
					}
					var original = call.arguments[0];
					call.arguments[0] = new SsaNullPointerConstant (original.span, original.semantic_type);
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = true;
					}
					assert (rejected);
					call.arguments[0] = original;
					SsaVerifier.verify (ssa);
					count++;
				}
			}
		}
		assert (count == 3);
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		cabi = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void projection_invalidation() {
	try {
		string source, template, errors, runtime;
		FileUtils.get_contents ("tests/language-generalization-10/nonnull-projection.astra", out source);
		FileUtils.get_contents ("lib/astra/collections/vector.astra", out template);
		FileUtils.get_contents ("lib/astra/base/errors.astra", out errors);
		FileUtils.get_contents ("lib/astra/async/virtual.astra", out runtime);
		var parsed = Parser.parse (new SourceFile.from_text ("nonnull-projection.astra", template + errors + runtime + source));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		if (checked.diagnostic != null) {
			GLib.error ("%s", checked.diagnostic.format ());
		}
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		CoreVerifier.verify (core);
		CoreFunction? selected = null;
		foreach (var function in core.functions) {
			if (function.name == "inspect_repository") {
				selected = function;
			}
		}
		assert (selected != null);
		var effect = selected.body.statements[0] as CoreCallStatement;
		var branch = selected.body.statements[1] as CoreIf;
		assert (effect != null && branch != null);
		selected.body.statements.remove_index (0);
		branch.then_block.statements.insert (0, effect);
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = error.message.contains ("nonnull");
		}
		assert (rejected);
		branch.then_block.statements.remove_index (0);
		selected.body.statements.insert (0, effect);
		CoreVerifier.verify (core);
		selected = null;
		effect = null;
		branch = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		CfgVerifier.verify (cfg);
		int count = 0;
		foreach (var function in cfg.functions) {
			if (function.name != "inspect_repository") {
				continue;
			}
			CfgBlock? before = null;
			CfgBlock? after = null;
			CfgInstruction? operation = null;
			int position = -1;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as CfgCallInstruction;
					if (call == null) {
						continue;
					}
					if (call.target.name == "projection_effect") {
						before = block;
						operation = call;
						position = i;
					}
					if (call.target.name == "inspect_projection") {
						after = block;
					}
				}
			}
			assert (before != null && after != null && before != after && operation != null && position >= 0);
			before.instructions.remove_index (position);
			after.instructions.insert (0, operation);
			rejected = false;
			try {
				CfgVerifier.verify (cfg);
			} catch (CfgError error) {
				rejected = error.message.contains ("nonnull");
			}
			assert (rejected);
			after.instructions.remove_index (0);
			before.instructions.insert (position, operation);
			CfgVerifier.verify (cfg);
			count++;
		}
		assert (count == 1);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		SsaVerifier.verify (ssa);
		count = 0;
		foreach (var function in ssa.functions) {
			if (function.name != "inspect_repository") {
				continue;
			}
			SsaBlock? before = null;
			SsaBlock? after = null;
			SsaInstruction? operation = null;
			int position = -1;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as SsaCallInstruction;
					if (call == null) {
						continue;
					}
					if (call.target.name == "projection_effect") {
						before = block;
						operation = call;
						position = i;
					}
					if (call.target.name == "inspect_projection") {
						after = block;
					}
				}
			}
			assert (before != null && after != null && before != after && operation != null && position >= 0);
			before.instructions.remove_index (position);
			after.instructions.insert (0, operation);
			rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				rejected = error.message.contains ("nonnull");
			}
			assert (rejected);
			after.instructions.remove_index (0);
			before.instructions.insert (position, operation);
			SsaVerifier.verify (ssa);
			count++;
		}
		assert (count == 1);
		var old = WeakRef (ssa.classes[0]);
		var native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		cabi = null;
		ssa = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CheckedProgram property_sample() throws GLib.Error {
	string source, api;
	FileUtils.get_contents ("tests/language-generalization-10/generic-property.astra", out source);
	FileUtils.get_contents ("tests/own-field/fixtures/resources.vapi", out api);
	var parsed = Parser.parse (new SourceFile.from_text ("generic-property.astra", source));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resources.vapi", api));
	assert (parsed.diagnostic == null && vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}

private void generic_properties() {
	try {
		CheckedProgram? checked = property_sample ();
		var old = WeakRef (checked.classes[0]);
		CoreProgram? parameterized = CoreBuilder.build (checked);
		CoreProgram? core = CoreGenericMonomorphizer.build (parameterized);
		parameterized = null;
		checked = null;
		assert (old.get () == null);
		int selected_ordinal = -1;
		{
			var owner = core_depot (core, "PropertyPoint");
			var other = core_depot (core, "PropertyEntry");
			selected_ordinal = owner.ordinal;
			var property = owner.properties[0];
			var getter = property.getter;
			owner.properties.remove_index (0);
			bool rejected = false;
			try {
				CoreVerifier.verify_concrete (core);
			} catch (CoreError error) {
				rejected = true;
			}
			assert (rejected);
			owner.properties.insert (0, property);
			CoreVerifier.verify_concrete (core);
			property.getter = other.properties[0].getter;
			rejected = false;
			try {
				CoreVerifier.verify_concrete (core);
			} catch (CoreError error) {
				rejected = true;
			}
			assert (rejected);
			property.getter = getter;
			CoreVerifier.verify_concrete (core);
		}
		old = WeakRef (core.classes[selected_ordinal]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (old.get () == null);
		{
			var owner = cfg_depot (cfg, "PropertyPoint");
			var property = owner.properties[0];
			var getter = property.getter;
			property.is_lazy = true;
			bool rejected = false;
			try {
				CfgVerifier.verify (cfg);
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
			property.is_lazy = false;
			CfgVerifier.verify (cfg);
			property.getter = cfg_depot (cfg, "PropertyEntry").properties[0].getter;
			rejected = false;
			try {
				CfgVerifier.verify (cfg);
			} catch (CfgError error) {
				rejected = true;
			}
			assert (rejected);
			property.getter = getter;
			CfgVerifier.verify (cfg);
		}
		old = WeakRef (cfg.classes[selected_ordinal]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (old.get () == null);
		{
			var owner = ssa_depot (ssa, "PropertyPoint");
			var property = owner.properties[0];
			var getter = property.getter;
			owner.properties.remove_index (0);
			bool rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
			owner.properties.insert (0, property);
			SsaVerifier.verify (ssa);
			property.getter = ssa_depot (ssa, "PropertyEntry").properties[0].getter;
			rejected = false;
			try {
				SsaVerifier.verify (ssa);
			} catch (SsaError error) {
				rejected = true;
			}
			assert (rejected);
			property.getter = getter;
			SsaVerifier.verify (ssa);
		}
		var native = NativeAbiBuilder.build (ssa);
		var selected = native.classes[selected_ordinal];
		var key = selected.generic_instance;
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		cabi = null;
		old = WeakRef (ssa.classes[selected_ordinal]);
		ssa = null;
		assert (old.get () == null);
		var members = new int[key.member_count];
		for (int m = 0; m < members.length; m++) {
			members[m] = key.member_target (m);
		}
		selected.generic_instance = new NativeExactClassInstance (key.definition, key.argument_ordinal, members, key.resource_argument, key.record_argument, key.generic_methods);
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		selected.generic_instance = key;
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		var properties = new int[key.property_count];
		for (int p = 0; p < properties.length; p++) {
			properties[p] = key.property_target (p);
		}
		properties[0] = key.property_target (1);
		selected.generic_instance = new NativeExactClassInstance (key.definition, key.argument_ordinal, members, key.resource_argument, key.record_argument, key.generic_methods, properties);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		selected.generic_instance = key;
		NativeAbiVerifier.verify (native);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/generic-bodies/property-schema-receiver-targets-native-llvm-restored", generic_properties);
	Test.add_func ("/generic-bodies/nonnull-projection-effect-core-cfg-ssa-restored", projection_invalidation);
	Test.add_func ("/generic-bodies/nonnull-generic-interface-code-core-cfg-ssa-restored", general_nonnull);
	Test.add_func ("/generic-bodies/cache-suspension-frame-acquisition-retirement-restored", cache_suspension_owner);
	Test.add_func ("/generic-bodies/child-cache-owner-observation-native-llvm-restored", cache_channels);
	Test.add_func ("/generic-bodies/slot-record-cycle-core-cfg-ssa-restored", slot_record_cycles);
	Test.add_func ("/generic-bodies/nested-exact-keys-class-slot-declaration-restored", nested_authority);
	Test.add_func ("/generic-bodies/owner-boundaries-rollback-exact-native-restored", owner_boundaries);
	Test.add_func ("/generic-bodies/owning-record-slot-commits-cleanup-native-llvm-restored", owning_record_authority);
	Test.add_func ("/generic-bodies/method-type-argument-ownership-native-restored", method_authority);
	Test.add_func ("/generic-bodies/independent-ordinary-control-flow", independent);
	Test.add_func ("/generic-bodies/concrete-definition-signature-ownership-restored", concrete_keys);
	Test.add_func ("/generic-bodies/resource-exact-cleanup-disarms-native-llvm-restored", resource_authority);
	Test.add_func ("/generic-bodies/record-complete-groups-layout-native-llvm-restored", record_authority);
	return Test.run ();
}

}
