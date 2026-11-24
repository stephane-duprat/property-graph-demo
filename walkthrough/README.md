# Step-by-step PDF companion

Revision 24 November 2026, D2.1: run `D2-workaround.sql` to replace only the
failing validation block after the D1 views exist. It keeps the SQL key checks
and validates edge endpoints against a PL/SQL collection of projected person
IDs. It changes no database objects or data. Continue to D3 only if it passes.
This workaround still needs confirmation on the target ADB instance. See
`D2-workaround.md`; `D2-diagnostics.sql` contains optional read-only diagnostics.

Revision 24 November 2026: `E13-E14-corrected.sql` contains just the two revised
checks. Run it against the existing demo as its owner; no setup or cleanup is
needed. All algorithm seed JSON now uses
`SYS_CONTEXT('USERENV', 'SESSION_USER')` instead of the bare `USER` expression
rejected in the reported PL/SQL query. This is a proposed compatibility fix;
live validation on the target ADB instance remains pending.

Read `../adb26ai-property-graphs-step-by-step.pdf` and run the SQL panels in order.
The 49-page guide contains 60 highlighted, selectable code panels. Each panel is
wholly on one page, with no line numbers to remove. Every nonblank line extracted
from the PDF was compared with these SQL files; PDF viewers may omit blank lines.

Use a dedicated demo schema. If you already completed the original `run_core.sql`,
do not repeat the core setup: continue at the optional or algorithm chapter you
need. These files and the original scripts create the same object names.

| File | PDF steps | Run rule |
|---|---|---|
| `administrator_once.sql` | 00.1 | Optional administrator action for an existing demo user; replace PG_DEMO. |
| `sqlcl_settings.sql` | 00.2 | SQLcl / SQL*Plus client settings. For Database Actions, use its output and autocommit settings. |
| `core_steps.sql` | 01, A1-A6, B1-B5, C1-C3, V1-V4 | New installation as the demo owner. Stop at the first error. |
| `optional_duality_steps.sql` | D1-D4 | After core; graph-over-view support from database RU 23.26.1. |
| `algorithms_steps.sql` | E0-E14 | After core; database RU 23.26.2+, package access, and no open demo transaction. |
| `optional_duality_algorithms.sql` | F1 | Only after D and E succeed. |
| `optional_sharing.sql` | SHARE | Optional grant to an existing reader and a read-only privilege-catalog query. |
| `cleanup_steps.sql` | CLEAN | Optional, destructive; dedicated demo schema only. Never called automatically. |

The PDF uses the existing demo SQL, reflowed for readable pages. It adds an explicit
current-schema check and full rollbacks after completed teaching sequences. Some
repetitive live-update assertions remain in the original chapter scripts; the PDF
includes the core result assertions. The long algorithm assertion is split into
four independently runnable anonymous blocks, with short individual PASS messages.
The algorithm transaction diagnostic is shortened for the page.

The queries use the corrected privileges: `CREATE PROPERTY GRAPH` for own-schema
creation; ownership for querying and dropping; `READ` or `SELECT` as graph object
privileges when sharing. No `READ PROPERTY GRAPH` or `DROP PROPERTY GRAPH` system
grant is included.

The guide explains PageRank, personalized PageRank for one seed and a seed set,
weakly connected components, and Bellman-Ford with unit and weighted costs. Expected
scores and distances are mathematical reference results for the supplied dataset,
not output captured from an Oracle instance.

The duality-document projection is explicitly optional. Oracle documents graphs
over SQL views and JSON_TABLE sources; execute the supplied composition on the
target service to verify it. The shared-table duality design works without that
graph-over-view dependency.

`PDF_VALIDATION.json` records artifact checks. No Oracle execution was performed
in this session. To rebuild the PDF, use `tools/build_pdf_guide.py` from the kit root
with Python, ReportLab and Pygments installed, plus the DejaVu fonts. Run
`tools/check_pdf_guide.py` with PyMuPDF for text and page-placement checks.
