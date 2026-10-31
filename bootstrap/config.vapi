// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

[CCode (cheader_filename = "astra-config.h")]
namespace Astra.Config {
[CCode (cname = "ASTRA_VERSION")]
public const string VERSION;
[CCode (cname = "ASTRA_MILESTONE")]
public const string MILESTONE;
}
