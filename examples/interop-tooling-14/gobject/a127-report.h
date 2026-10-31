/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA127_REPORT_H
#define ASTRA127_REPORT_H
#include "Astra127.h"
/**
 * astra127_diagnostic_report:
 * @self: a diagnostic
 * @severity_offset: adjustment to the selected severity
 * @error: (nullable): a mapped native or adapter error
 *
 * Copy a validated Astra-owned UTF-8 diagnostic through explicit scalar channels.
 * All native Text owners retire before this method returns.
 *
 * Returns: (transfer full) (nullable): a newly allocated UTF-8 report
 */
gchar *astra127_diagnostic_report(Astra127Diagnostic *self, gint severity_offset, GError **error);
#endif
