// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
#if ARGS_CORE || ARGS_CFG || ARGS_SSA
using Astra.Semantic;
using Astra.Text;
#endif
#if ARGS_CORE
using Astra.Core;
#elif ARGS_CFG
using Astra.Cfg;
#elif ARGS_SSA
using Astra.Ssa;
#else
using Astra.NativeAbi;
#endif

namespace Astra.Tests.ArgsStandalone {
private void models() {
	var span = SourceSpan (new SourceFile.from_text ("independent-text-slice", "x"), 0, 1);
	for (int variant = 0; variant <= 7; variant++) {
		try {
#if ARGS_CORE || ARGS_CFG || ARGS_SSA
			var t = new BuiltinTypes ();
			var slice = t.slice_of (t.string_type);
			var contract = variant == 1 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE;
			var provenance = new DataPointerProvenance (DataPointerOrigin.PARAMETER, 0, 0, variant != 4);
			var place_type = variant == 5 ? new SliceType (t.string_type) : slice;
			var payload = new TextBytes ({'x'});
			var return_type = variant == 3 ? (SemanticType) t.string_type : t.int_type;
#if ARGS_CORE
			var parameter = new CoreParameter (span, span, "values", slice, 0, contract);
			var parameters = new GenericArray<CoreParameter> ();
			parameters.add (parameter);
			var reference = new CoreParameterValue (span, variant == 7 ? new CoreParameter (span, span, "values", slice, 0, contract) : parameter);
			CoreValue view = variant == 6 ? (CoreValue) new CoreNullPointerValue (span, slice) : reference;
			var index = new CoreIntegerValue (span, t.int_type, AstraIntValue.from_int64 (0));
			var place = new CoreSliceElementPlace (span, view, place_type, index, provenance);
			var load = new CoreLoadValue (span, place);
			var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
			if (variant == 2) {
				body.statements.add (new CoreStore (span, place, new CoreTextValue (span, t.string_type, payload)));
			}
			body.statements.add (new CoreReturn (span, variant == 3 ? (CoreValue) load : new CoreTextLengthValue (span, t.int_type, load)));
			var functions = new GenericArray<CoreFunction> ();
			functions.add (new CoreFunction (span, span, "read", return_type, parameters, new GenericArray<CoreLocalPlace> (), body));
			var program = new CoreProgram (span, functions);
			program.text_literals.add (payload);
			CoreVerifier.verify (program);
#elif ARGS_CFG
			var parameter = new CfgParameter (span, span, "values", slice, 0, contract);
			var parameters = new GenericArray<CfgParameter> ();
			parameters.add (parameter);
			var reference = new CfgParameterValue (span, variant == 7 ? new CfgParameter (span, span, "values", slice, 0, contract) : parameter);
			var view = new CfgEvaluatedValue (span, slice);
			var captured = new CfgEvaluateInstruction (span, reference, view);
			var index = new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (0));
			var bounded = new CfgEvaluatedValue (span, t.int_type);
			var bounds = new CfgSliceBoundsCheck (span, view, index, bounded);
			var place = new CfgSliceElementPlace (span, view, place_type, variant == 6 ? (CfgValue) index : bounded, provenance);
			var load = new CfgLoadValue (span, place);
			var loaded = new CfgEvaluatedValue (span, t.string_type);
			var block = new CfgBlock.reserve (span, 0);
			block.instructions.add (captured);
			block.instructions.add (bounds);
			if (variant == 2) {
				block.instructions.add (new CfgStore (span, place, new CfgTextValue (span, t.string_type, payload)));
			}
			block.instructions.add (new CfgEvaluateInstruction (span, load, loaded));
			block.complete (span, new CfgReturn (span, variant == 3 ? (CfgValue) loaded : new CfgTextLengthValue (span, t.int_type, loaded)));
			var blocks = new GenericArray<CfgBlock> ();
			blocks.add (block);
			var functions = new GenericArray<CfgFunction> ();
			functions.add (new CfgFunction (span, span, "read", return_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
			var program = new CfgProgram (span, functions);
			program.text_literals.add (payload);
			CfgVerifier.verify (program);
#else
			var parameter = new SsaFunctionParameter (span, span, "values", slice, 0, contract);
			var parameters = new GenericArray<SsaFunctionParameter> ();
			parameters.add (parameter);
			var view = variant == 7 ? new SsaFunctionParameter (span, span, "values", slice, 0, contract) : parameter;
			var index = new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (0));
			var bounds = new SsaSliceBoundsCheck (span, view, index, 1);
			var place = new SsaSliceElementPlace (span, view, place_type, variant == 6 ? (SsaValue) index : bounds.result, provenance);
			var load = new SsaLoadInstruction (span, place, 2);
			var length = new SsaTextLengthInstruction (span, t.int_type, load.result, 3);
			var block = new SsaBlock (span, 0, 0);
			block.instructions.add (bounds);
			if (variant == 2) {
				block.instructions.add (new SsaStoreInstruction (span, place, new SsaTextConstant (span, t.string_type, payload)));
			}
			block.instructions.add (load);
			block.instructions.add (length);
			block.complete (new SsaReturn (span, variant == 3 ? load.result : length.result));
			var blocks = new GenericArray<SsaBlock> ();
			blocks.add (block);
			var functions = new GenericArray<SsaFunction> ();
			functions.add (new SsaFunction (span, span, "read", return_type, 0, parameters, blocks, block));
			var program = new SsaProgram (span, functions);
			program.text_literals.add (payload);
			SsaVerifier.verify (program);
#endif
#else
			var text = new NativeTextType (NativeTextContract.BORROWED_NOESCAPE, NativeScalarType.PTR, variant == 1 ? NativeScalarType.U32 : NativeScalarType.I32);
			var descriptor = new NativeTextDescriptor (text, variant == 2 ? 1 : 0, variant == 2 ? 0 : 1, variant != 3);
			var slice = new NativeTextSliceType (descriptor, variant == 4 ? NativeSliceAccess.READ_WRITE : NativeSliceAccess.READ, variant != 5, variant == 6 ? NativeScalarType.I32 : NativeScalarType.PTR);
			var parameters = new GenericArray<NativeParameter> ();
			parameters.add (new NativeParameter.typed (span, span, "values", 0, slice));
			var signature = new NativeSignature (variant == 7 ? NativeAbiVersion.TEXT_V9 : NativeAbiVersion.TEXT_SLICE_V10, parameters, new NativeResult (NativeScalarType.I32));
			var functions = new GenericArray<NativeFunction> ();
			functions.add (new NativeFunction (span, span, "read", 0, signature, NativeLinkage.NATIVE_INTERNAL));
			var program = new NativeAbiProgram (span, NativeAbiVersion.TEXT_SLICE_V10, functions);
			NativeAbiVerifier.verify (program);
			assert (signature.physical_parameter_count == 2);
#endif
			assert (variant == 0);
		} catch (GLib.Error error) {
			if (variant == 0) {
				GLib.error ("valid standalone model: %s", error.message);
			}
			Test.message ("rejected %d: %s", variant, error.message);
		}
	}
}

#if !ARGS_CORE && !ARGS_CFG && !ARGS_SSA
private void entry() {
	var span = SourceSpan (new SourceFile.from_text ("entry", "main"), 0, 4);
	try {
		new NativeProgramEntryPlan (0, span, NativeEntryKind.ZERO_ARGUMENTS).verify ();
		new NativeProgramEntryPlan (0, span, NativeEntryKind.TEXT_ARGUMENTS, new NativeTextSliceType ()).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
	NativeEntryStep[] missing_guard = {
		NativeEntryStep.INITIALIZE_NULL, NativeEntryStep.PREPARE, NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.DISPOSE, NativeEntryStep.RETURN
	};
	NativeEntryStep[] early_dispose = {
		NativeEntryStep.INITIALIZE_NULL, NativeEntryStep.PREPARE, NativeEntryStep.GUARD_SUCCESS, NativeEntryStep.DISPOSE, NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.RETURN
	};
	for (int i = 0; i < 2; i++) {
		bool rejected = false;
		try {
			new NativeProgramEntryPlan (0, span, NativeEntryKind.TEXT_ARGUMENTS, new NativeTextSliceType (), i == 0 ? missing_guard : early_dispose).verify ();
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	}
	assert (new NativeTextSliceLayout (0, 8, 16, 8, 8).qualified ());
	assert (!new NativeTextSliceLayout (0, 8, 12, 8, 8).qualified ());
	assert (!new NativeTextSliceLayout (0, 4, 8, 4, 4).qualified ());
}

#endif
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/args/standalone/descriptor-and-origins", models);
#if !ARGS_CORE && !ARGS_CFG && !ARGS_SSA
	Test.add_func ("/args/standalone/entry-and-layout", entry);
#endif
	return Test.run ();
}

}
