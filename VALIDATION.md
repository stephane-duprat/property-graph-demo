# Validation record

Prepared 20 November 2026. Owner-expression and D2.1 revisions: 24 November 2026.

D2.1 revision: the reported line 16 maps to the endpoint query in the prior
PDF block. The replacement preserves the null/duplicate key checks and uses
`BULK COLLECT` plus PL/SQL `MEMBER OF` to validate endpoints. Explicit checks
cover null endpoints and the empty vertex collection. The SQL no longer joins
the two duality projections in the same endpoint validation statement.
This avoids the failing query shape; it does not identify a confirmed database
defect or establish a patch-level fix. No Oracle connection is available here,
so the workaround and its effect on the reported error remain unverified on ADB.

The PDF, chapter SQL, exact companion SQL, standalone workaround and embedded
HTML downloads are kept in sync. The revised PDF's text and page geometry are
checked, with changed pages rendered and visually reviewed. The previous
E13.1/E14.1 owner-expression correction is preserved unchanged.

Revision scope: replace bare `USER` in algorithm seed JSON with the explicit
`SYS_CONTEXT('USERENV', 'SESSION_USER')` call. This retains the own-schema
assumption and avoids the expression rejected in reported steps E13.1/E14.1.
The reported error identifies the failing expression; a specific Oracle defect
or affected patch range has not been established. Live execution of the revised
statements has not been performed. All artifact checks below are rerun for this
revision; database results remain independent reference calculations.

PDF companion added 20 November 2026:

- Generated a 49-page guide with 60 highlighted, selectable SQL/client panels.
- Every code panel is drawn as a single unit on one page. Extracted nonblank SQL
  lines match the companion scripts, including indentation, quotes and operators;
  blank display lines may be omitted by a PDF viewer.
- Checked page geometry, page footers, bookmarks, official source links, and all
  five `DBMS_OGA` function examples. No code screenshots or line-number prefixes.
- Rendered all PDF pages using Poppler and reviewed the contact sheets; dense
  code pages were also reviewed at full size.
- Rechecked sample relationships and independent algorithm reference results.
- The PDF guide does not change the live-execution limitation below. See
  `walkthrough/PDF_VALIDATION.json` and `tools/check_pdf_guide.py` for artifact checks.

Passed locally:

- Corrected the setup grants and preflight filter against the Oracle 26ai SQL Language Reference. The own-schema demo requires `CREATE PROPERTY GRAPH`; graph ownership permits querying and dropping. Removed the invalid system privilege names from executable grant examples and preflight checks, including the combined script and embedded HTML downloads.
- The relational INSERT statements produce five people and seven relationships.
- Independent SQL joins in SQLite produce exactly the three expected two-hop routes and two cycles anchored on Alice. This checks the example's relationships and answers; it does not validate Oracle syntax.
- Parsed JSON seed documents match the relational sample, with unique scalar keys and valid endpoints.
- All four walkthrough modes, four query patterns, route highlighting, city updates, shared versus independent data state, reset, keyboard selection, SQL copying, and nine embedded downloads passed JavaScript checks using a minimal DOM harness under Node.
- All six algorithm selections in the walkthrough passed, including the five documented DBMS_OGA functions and both Bellman-Ford distance metrics. Browser ranking calculations agree, to the displayed six decimal places, with independent Python linear-system solutions for global PageRank and both personalized variants.
- An independent all-pairs shortest-distance calculation confirms minimum hops `[0,1,1,2,2]` and minimum effort `[0,1,3,3,2]` in person ID order. An undirected transitive closure confirms a single weakly connected component.
- Reviewed the GAF argument order, full graph vertex identities, expression-property defaults, temporary result scope, transaction restriction and package privileges against current Oracle documentation. The new module does not introduce nonexistent graph system privileges.
- `algorithm_reference_results.json` records the independently calculated baseline results and their provenance. These are reference calculations, not outputs captured from Oracle.
- Local script references, downloadable file links, and the separation of cleanup from the setup runner were checked
- Live execution of Oracle DDL, SQL/PGQ, JSON collection, duality, or DBMS_OGA statements.


Run `run_core.sql` to execute the included database assertions. With graph-over-view support (DB RU 23.26.1+), run `run_optional.sql` to test the duality-document projection composition on the target instance. Save the database version and first Oracle error if a module fails.

For Part E, use a fresh connection to the established demo schema, confirm DB RU
23.26.2+ and package access, then run `run_algorithms.sql`. It prints all algorithm
queries and checks PageRank normalization, WCC membership, and both distance
results. An open transaction causes a preflight error before any graph DDL.
If Parts D and E succeed, `sql/08_algorithms_duality.sql` adds PageRank and WCC on
the document-projection graph.
