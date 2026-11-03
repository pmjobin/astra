// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Driver {
public class ComImports : Object {
	public static string generate(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		string declared = ComDeclared.generate_imports (program, implementation);
		var identities = new StringBuilder ();
		foreach (var handle in program.handles) {
			if (handle.com_import != null) {
				identities.append (handle.com_import.identity ());
				identities.append_c ('\n');
			}
		}
		if (identities.len == 0) {
			return declared;
		}
		string guard = "ASTRA_COM_IMPORT_V1_" + Checksum.compute_for_string (ChecksumType.SHA256, identities.str).up ();
		var text = new StringBuilder ("\n#ifndef " + guard + "\n#define " + guard + "\n#include <windows.h>\n#include <unknwn.h>\n#include <objbase.h>\n#include <stdint.h>\n#ifndef __cplusplus\n#error Astra COM import requires a Windows C++17 SDK toolchain\n#endif\nstatic_assert(sizeof(void *) == 8 && sizeof(LONG) == 4 && sizeof(HRESULT) == 4 && sizeof(GUID) == 16, \"Astra COM import requires Windows x64\");\n");
		if (implementation) {
			text.append ("#include <new>\n#include <cstdlib>\nextern \"C\" uint64_t astra_foreign14_thread_identity(void);\n");
		}
		foreach (var handle in program.handles) {
			var contract = handle.com_import;
			if (contract == null) {
				continue;
			}
			if (!ComImportContract.matches (contract, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol)) {
				throw new ForeignAdapterError.INVALID ("COM import generator lost its exact nominal IID/cleanup/context authority");
			}
			string p = contract.prefix;
			text.append_printf ("\n// %s\ntypedef struct %s_handle %s_handle;\n", contract.identity (), p, p);
			if (!implementation) {
				text.append_printf ("extern \"C\" %s_handle *%s_acquire(void *unknown, int32_t *status);\nextern \"C\" %s_handle *%s_clone(%s_handle *self, int32_t *status);\nextern \"C\" void %s_release(%s_handle *self);\n", p, p, p, p, p, p, p);
				if (contract.view == "value") {
					text.append_printf ("extern \"C\" int32_t %s_get(%s_handle *self, int32_t *out);\nextern \"C\" int32_t %s_set(%s_handle *self, int32_t value);\n", p, p, p, p);
				} else {
					text.append_printf ("extern \"C\" int32_t %s_scale(%s_handle *self, int32_t factor, int32_t *out);\n", p, p);
				}
				continue;
			}
			text.append_printf ("inline constexpr IID IID_%s_Import = %s;\nstruct %s_Imported : IUnknown { %s };\n", p, ComAdapters.guid_initializer (contract.iid), p, contract.view == "value" ? "virtual HRESULT STDMETHODCALLTYPE Get(LONG *) = 0; virtual HRESULT STDMETHODCALLTYPE Set(LONG) = 0;" : "virtual HRESULT STDMETHODCALLTYPE Scale(LONG, LONG *) = 0;");
			text.append ("""
struct @P@_handle { @P@_Imported *view; uint64_t thread; APTTYPE apartment; APTTYPEQUALIFIER qualifier; };
static HRESULT @P@_context(@P@_handle *self) noexcept {
	if (!self) return E_POINTER;
	if (astra_foreign14_thread_identity() != self->thread) return RPC_E_WRONG_THREAD;
	APTTYPE apartment; APTTYPEQUALIFIER qualifier;
	HRESULT status = CoGetApartmentType(&apartment, &qualifier);
	if (FAILED(status)) return status;
	return apartment == self->apartment && qualifier == self->qualifier ? S_OK : RPC_E_WRONG_THREAD;
}
extern "C" @P@_handle *@P@_acquire(void *unknown, int32_t *out_status) noexcept {
	if (!out_status) return nullptr;
	*out_status = static_cast<int32_t>(E_POINTER);
	if (!unknown) return nullptr;
	APTTYPE apartment; APTTYPEQUALIFIER qualifier;
	HRESULT status = CoGetApartmentType(&apartment, &qualifier);
	if (FAILED(status)) { *out_status = static_cast<int32_t>(status); return nullptr; }
	void *raw = nullptr;
	status = static_cast<IUnknown *>(unknown)->QueryInterface(IID_@P@_Import, &raw);
	if (FAILED(status) || !raw) {
		if (raw) static_cast<@P@_Imported *>(raw)->Release();
		*out_status = static_cast<int32_t>(FAILED(status) ? status : E_UNEXPECTED);
		return nullptr;
	}
	auto result = new(std::nothrow) @P@_handle{static_cast<@P@_Imported *>(raw), astra_foreign14_thread_identity(), apartment, qualifier};
	if (!result) { static_cast<@P@_Imported *>(raw)->Release(); *out_status = static_cast<int32_t>(E_OUTOFMEMORY); return nullptr; }
	*out_status = static_cast<int32_t>(status);
	return result;
}
extern "C" @P@_handle *@P@_clone(@P@_handle *self, int32_t *out_status) noexcept {
	if (!out_status) return nullptr;
	HRESULT status = @P@_context(self);
	*out_status = static_cast<int32_t>(status);
	if (FAILED(status)) return nullptr;
	auto result = new(std::nothrow) @P@_handle{self->view, self->thread, self->apartment, self->qualifier};
	if (!result) { *out_status = static_cast<int32_t>(E_OUTOFMEMORY); return nullptr; }
	self->view->AddRef();
	return result;
}
extern "C" void @P@_release(@P@_handle *self) noexcept {
	if (!self) return;
	if (FAILED(@P@_context(self))) std::abort();
	self->view->Release();
	delete self;
}
""".replace ("@P@", p));
			if (contract.view == "value") {
				text.append ("""
extern "C" int32_t @P@_get(@P@_handle *self, int32_t *out) noexcept {
	if (!out) return static_cast<int32_t>(E_POINTER);
	*out = 0;
	HRESULT status = @P@_context(self);
	if (FAILED(status)) return static_cast<int32_t>(status);
	LONG value = 0;
	status = self->view->Get(&value);
	if (SUCCEEDED(status)) *out = value;
	return static_cast<int32_t>(status);
}
extern "C" int32_t @P@_set(@P@_handle *self, int32_t value) noexcept {
	HRESULT status = @P@_context(self);
	return static_cast<int32_t>(FAILED(status) ? status : self->view->Set(value));
}
""".replace ("@P@", p));
			} else {
				text.append ("""
extern "C" int32_t @P@_scale(@P@_handle *self, int32_t factor, int32_t *out) noexcept {
	if (!out) return static_cast<int32_t>(E_POINTER);
	*out = 0;
	HRESULT status = @P@_context(self);
	if (FAILED(status)) return static_cast<int32_t>(status);
	LONG value = 0;
	status = self->view->Scale(factor, &value);
	if (SUCCEEDED(status)) *out = value;
	return static_cast<int32_t>(status);
}
""".replace ("@P@", p));
			}
		}
		text.append ("\n#endif\n");
		text.append (declared);
		return text.str;
	}

}
}
