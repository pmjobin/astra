// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
#if TEXT_CORE || TEXT_CFG || TEXT_SSA
using Astra.Text;
#endif
#if TEXT_CORE
using Astra.Core;
using Astra.Semantic;
#elif TEXT_CFG
using Astra.Cfg;
using Astra.Semantic;
#elif TEXT_SSA
using Astra.Ssa;
using Astra.Semantic;
#else
using Astra.NativeAbi;
#endif

namespace Astra.Tests.TextStandalone {
#if TEXT_CORE
private CoreCallValue expired(SourceSpan span, SemanticType type) {
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var target = new CoreFunction (span, span, "expired", type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body);
	return new CoreCallValue (span, type, target, new GenericArray<CoreValue> ());
}
private CoreProgram sample(int variant) throws CoreError {
#elif TEXT_CFG
private CfgCallInstruction expired(SourceSpan span, SemanticType type) {
	var block = new CfgBlock (span, 0, new GenericArray<CfgInstruction> (), new CfgFunctionEnd (span));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var target = new CfgFunction (span, span, "expired", type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block);
	return new CfgCallInstruction (span, target, new GenericArray<CfgValue> (), new CfgCallResultValue (span, type));
}
private CfgProgram sample(int variant) throws CfgError {
#elif TEXT_SSA
private SsaCallInstruction expired(SourceSpan span, SemanticType type) {
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var target = new SsaFunction (span, span, "expired", type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block);
	return new SsaCallInstruction (span, type, 0, target, new GenericArray<SsaValue> ());
}
private SsaProgram sample(int variant) throws SsaError {
#else
private NativeAbiProgram sample(int variant) throws NativeAbiError {
#endif
	var span = SourceSpan (new SourceFile.from_text ("independent-text", "x"), 0, 1);
#if TEXT_CORE || TEXT_CFG || TEXT_SSA
	var t = new BuiltinTypes ();
	var payload = variant == 1 ? new TextBytes ({0xed, 0xa0, 0x80}) : new TextBytes ({'a', 0, 'b'}, variant == 2 ? 2147483648L : -1);
	SemanticType type = variant == 5 ? t.int_type : variant == 6 ? new StringType () : t.string_type;
	var contract = variant == 7 ? PointerParameterContract.UNMANAGED : PointerParameterContract.BORROWED_NOESCAPE;
#if TEXT_CORE
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "text", t.string_type, 0, contract);
	parameters.add (parameter);
	CoreValue value = variant == 4 ? (CoreValue) new CoreParameterValue (span, parameter) : new CoreTextValue (span, type, payload);
	if (variant == 8) {
		var call = expired (span, type);
		assert (call.target == null);
		value = call;
	}
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreReturn (span, value));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", t.string_type, parameters, new GenericArray<CoreLocalPlace> (), body));
	var program = new CoreProgram (span, functions);
#elif TEXT_CFG
	var parameters = new GenericArray<CfgParameter> ();
	var parameter = new CfgParameter (span, span, "text", t.string_type, 0, contract);
	parameters.add (parameter);
	CfgValue value = variant == 4 ? (CfgValue) new CfgParameterValue (span, parameter) : new CfgTextValue (span, type, payload);
	var block = new CfgBlock.reserve (span, 0);
	if (variant == 8) {
		var call = expired (span, type);
		assert (call.target == null);
		block.instructions.add (call);
		value = call.result;
	}
	block.complete (span, new CfgReturn (span, value));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (new CfgFunction (span, span, "f", t.string_type, 0, parameters, new GenericArray<CfgLocalPlace> (), blocks, block));
	var program = new CfgProgram (span, functions);
#else
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter = new SsaFunctionParameter (span, span, "text", t.string_type, 0, contract);
	parameters.add (parameter);
	SsaValue value = variant == 4 ? (SsaValue) parameter : new SsaTextConstant (span, type, payload);
	var block = new SsaBlock (span, 0, 0);
	if (variant == 8) {
		var call = expired (span, type);
		assert (call.target == null);
		block.instructions.add (call);
		value = call.result;
	}
	block.complete (new SsaReturn (span, value));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", t.string_type, 0, parameters, blocks, block));
	var program = new SsaProgram (span, functions);
#endif
	if (variant != 3) {
		program.text_literals.add (payload);
	}
	return program;
#else
	var parameters = new GenericArray<NativeParameter> ();
	var parameter = new NativeTextType (variant == 3 ? NativeTextContract.STATIC_TEXT : NativeTextContract.BORROWED_NOESCAPE, variant == 1 ? NativeScalarType.I32 : NativeScalarType.PTR, variant == 1 ? NativeScalarType.PTR : variant == 2 ? NativeScalarType.U32 : NativeScalarType.I32);
	parameters.add (new NativeParameter.typed (span, span, "text", 0, parameter));
	var result = new NativeResult.typed (new NativeTextType (variant == 4 ? NativeTextContract.BORROWED_NOESCAPE : NativeTextContract.STATIC_TEXT));
	var signature = new NativeSignature (variant == 5 ? NativeAbiVersion.BUFFER_V8 : NativeAbiVersion.TEXT_V9, parameters, result);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (new NativeFunction (span, span, "f", 0, signature, NativeLinkage.NATIVE_INTERNAL));
	return new NativeAbiProgram (span, NativeAbiVersion.TEXT_V9, functions);
#endif
}
private void models() {
#if TEXT_CORE || TEXT_CFG || TEXT_SSA
	int last = 8;
#else
	int last = 5;
#endif
	for (int variant = 0; variant <= last; variant++) {
		try {
			var program = sample (variant);
#if TEXT_CORE
			CoreVerifier.verify (program);
#elif TEXT_CFG
			CfgVerifier.verify (program);
#elif TEXT_SSA
			SsaVerifier.verify (program);
#else
			NativeAbiVerifier.verify (program);
			assert (program.functions[0].signature.physical_parameter_count == 2);
#endif
			if (variant != 0) {
				GLib.error ("accepted malformed text model %d", variant);
			}
		} catch (GLib.Error error) {
			if (variant == 0) {
				GLib.error ("%s", error.message);
			}
			Test.message ("rejected variant %d: %s", variant, error.message);
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text/independent-model-and-malformed", models);
	return Test.run ();
}
}
