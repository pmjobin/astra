# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
systems_dsp_proof = executable('astra-systems-dsp-proof',
	['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('systems-dsp-9-contracts', systems_dsp_proof, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root(), timeout: 180)
foreach name : ['minimal', 'numeric', 'volatile', 'arena', 'portability']
	test('systems-dsp-9-' + name, ints_python,
		args: [files(name + '.py'), astrac, meson.current_build_dir() / name],
		depends: astrac, workdir: meson.project_source_root(), timeout: 600,
		env: ['PYTHONDONTWRITEBYTECODE=1'])
endforeach
