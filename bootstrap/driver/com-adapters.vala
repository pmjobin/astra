// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Driver {
// SDK-facing code is compiled by an explicit Windows C++ toolchain. It sees
// only the checked opaque C protocol, never a guessed native Class layout.
public class ComAdapters : Object {
	internal static string guid_initializer(string guid) {
		return "{0x%s,0x%s,0x%s,{0x%s,0x%s,0x%s,0x%s,0x%s,0x%s,0x%s,0x%s}}".printf (guid.substring (0, 8), guid.substring (9, 4), guid.substring (14, 4), guid.substring (19, 2), guid.substring (21, 2), guid.substring (24, 2), guid.substring (26, 2), guid.substring (28, 2), guid.substring (30, 2), guid.substring (32, 2), guid.substring (34, 2));
	}
	public static string generate(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		bool exported = false;
		foreach (var owner in program.classes) {
			exported |= owner.foreign_export != null;
		}
		string opaque_header = exported ? ForeignAdapters.header (program) : "";
		string imports = ComImports.generate (program, implementation);
		string guard = "ASTRA_COM_V1_" + Checksum.compute_for_string (ChecksumType.SHA256, opaque_header + imports).up ();
		var text = new StringBuilder ("#ifndef " + guard + "\n#define " + guard + "\n" + (implementation ? "#define ASTRA_FOREIGN14_INTERNAL\n#define ASTRA_FOREIGN16_INTERNAL\n" : ""));
		text.append (opaque_header);
		text.append ("\n#include <windows.h>\n#include <unknwn.h>\n#include <objbase.h>\n#ifndef __cplusplus\n#error Selected Astra COM adapters require a Windows C++17 SDK compiler\n#endif\nstatic_assert(sizeof(void *) == 8 && sizeof(LONG) == 4 && sizeof(HRESULT) == 4 && sizeof(GUID) == 16, \"Astra COM profile requires the Windows x64 ABI\");\n");
		if (implementation) {
			text.append ("#include <new>\n");
		}
		int count = 0;
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.com == null) {
				continue;
			}
			if (!ForeignClassPolicy.matches (policy, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name)) {
				throw new ForeignAdapterError.INVALID ("COM generator lost its admitted IID/vtable/lifetime/context contract");
			}
			count++;
			string p = policy.prefix;
			text.append_printf ("\n// %s\ninline constexpr IID IID_%s_Value = %s;\ninline constexpr IID IID_%s_Scale = %s;\n", policy.com.identity (), p, guid_initializer (policy.com.value_iid), p, guid_initializer (policy.com.scale_iid));
			text.append_printf ("struct %s_Value : IUnknown { virtual HRESULT STDMETHODCALLTYPE Get(LONG *out) = 0; virtual HRESULT STDMETHODCALLTYPE Set(LONG value) = 0; };\nstruct %s_Scale : IUnknown { virtual HRESULT STDMETHODCALLTYPE Scale(LONG factor, LONG *out) = 0; };\n", p, p);
			if (!implementation) {
				text.append_printf ("extern \"C\" HRESULT %s_as_com(%s_handle *self, IUnknown **out);\nextern \"C\" HRESULT %s_com_create(int32_t value, IUnknown **out);\n", p, p, p);
				continue;
			}
			text.append ("""
class @P@_Com final : public @P@_Value, public @P@_Scale {
	@P@_handle *root;
	APTTYPE apartment;
	APTTYPEQUALIFIER qualifier;
	~@P@_Com() = default;
public:
	@P@_Com(@P@_handle *root, APTTYPE apartment, APTTYPEQUALIFIER qualifier) noexcept : root(root), apartment(apartment), qualifier(qualifier) {}
	static void retire(void *value) noexcept { delete static_cast<@P@_Com *>(value); }
	HRESULT context() noexcept {
		HRESULT status = static_cast<HRESULT>(astra_foreign14_@P@_check_thread(root));
		if (FAILED(status)) return status;
		APTTYPE current; APTTYPEQUALIFIER detail;
		status = CoGetApartmentType(&current, &detail);
		if (FAILED(status)) return status;
		return current == apartment && detail == qualifier ? S_OK : RPC_E_WRONG_THREAD;
	}
	IUnknown *canonical() noexcept { return static_cast<@P@_Value *>(this); }
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) noexcept override {
		if (!out) return E_POINTER;
		*out = nullptr;
		HRESULT status = context();
		if (FAILED(status)) return status;
		if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_@P@_Value)) *out = static_cast<@P@_Value *>(this);
		else if (IsEqualIID(iid, IID_@P@_Scale)) *out = static_cast<@P@_Scale *>(this);
		else return E_NOINTERFACE;
		AddRef();
		return S_OK;
	}
	ULONG STDMETHODCALLTYPE AddRef() noexcept override { return @P@_acquire(root); }
	ULONG STDMETHODCALLTYPE Release() noexcept override { return @P@_release(root); }
	HRESULT STDMETHODCALLTYPE Get(LONG *out) noexcept override {
		if (!out) return E_POINTER;
		*out = 0;
		HRESULT status = context();
		if (FAILED(status)) return status;
		int32_t value = 0;
		status = static_cast<HRESULT>(@P@_get(root, &value));
		if (SUCCEEDED(status)) *out = value;
		return status;
	}
	HRESULT STDMETHODCALLTYPE Set(LONG value) noexcept override {
		HRESULT status = context();
		return FAILED(status) ? status : static_cast<HRESULT>(@P@_set(root, value));
	}
	HRESULT STDMETHODCALLTYPE Scale(LONG factor, LONG *out) noexcept override {
		if (!out) return E_POINTER;
		*out = 0;
		HRESULT status = context();
		if (FAILED(status)) return status;
		int32_t value = 0;
		status = static_cast<HRESULT>(@P@_get(root, &value));
		if (FAILED(status)) return status;
		if (factor < 0 || factor > 100 || value < 0 || value > 100) return E_INVALIDARG;
		*out = value * factor;
		return factor == 0 ? S_FALSE : S_OK;
	}
};
extern "C" __declspec(dllexport) HRESULT @P@_as_com(@P@_handle *self, IUnknown **out) noexcept {
	if (!out) return E_POINTER;
	*out = nullptr;
	HRESULT status = static_cast<HRESULT>(astra_foreign14_@P@_check_thread(self));
	if (FAILED(status)) return status;
	APTTYPE apartment; APTTYPEQUALIFIER qualifier;
	status = CoGetApartmentType(&apartment, &qualifier);
	if (FAILED(status)) return status;
	auto view = static_cast<@P@_Com *>(astra_foreign14_@P@_personality(self));
	if (!view) {
		view = new(std::nothrow) @P@_Com(self, apartment, qualifier);
		if (!view) return E_OUTOFMEMORY;
		status = static_cast<HRESULT>(astra_foreign14_@P@_attach(self, view, @P@_Com::retire));
		if (FAILED(status)) { @P@_Com::retire(view); return status; }
	}
	status = view->context();
	if (FAILED(status)) return status;
	view->AddRef();
	*out = view->canonical();
	return S_OK;
}
extern "C" __declspec(dllexport) HRESULT @P@_com_create(int32_t value, IUnknown **out) noexcept {
	if (!out) return E_POINTER;
	*out = nullptr;
	APTTYPE apartment; APTTYPEQUALIFIER qualifier;
	HRESULT status = CoGetApartmentType(&apartment, &qualifier);
	if (FAILED(status)) return status;
	auto root = @P@_create(value);
	if (!root) return E_OUTOFMEMORY;
	status = @P@_as_com(root, out);
	@P@_release(root);
	return status;
}
""".replace ("@P@", p));
		}
		if (count == 0 && imports == "") {
			throw new ForeignAdapterError.INVALID ("no checked COM Class exports or interface imports were selected");
		}
		text.append (imports);
		text.append (ComDeclared.generate_exports (program, implementation));
		text.append ("\n#endif\n");
		return text.str;
	}
}
}
