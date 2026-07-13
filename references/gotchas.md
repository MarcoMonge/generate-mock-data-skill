# Gotchas

Real bugs hit building `examples/CostaRica/generate_mock_CR.do`, the first
working instance of this pattern. Each is a class of bug the generated script
for a new country can hit again — check every item below against the
generated `.do` before running it.

## 1. Stata's positional varlist range operator on interleaved columns

`varname_first-varname_last` (e.g. `ZF_broad_2005-ZF_broad_2019`) selects
every column *physically between* those two in dataset order — not every
column matching the name pattern. In a wide year-panel where variables for
different concepts are interleaved by year (`ae_2005 ciiu4_2005 ..._2005
ae_2006 ciiu4_2006 ...`), a range like this sweeps up unrelated string
columns between the two named ones and causes a `type mismatch` (or, worse,
silently includes the wrong columns if types happen to match).

**Fix**: always use a name wildcard instead — `ZF_broad_*`, never
`ZF_broad_2005-ZF_broad_2019` — for any operation spanning a variable family
across years (`egen ... rowmax()`, `rowtotal()`, `keep`, etc.).

## 2. Merge-key name reuse across sequential merges

Two sequential `merge`s that both use a same-named key variable (e.g.
`pool_idx` used first to look up a seller ID, then reused for a buyer ID
lookup) will error with "variable already defined" on the second `merge` if
the first merge's key variable isn't dropped first.

**Fix**: `drop <key>` (and `drop _merge` if not using `nogen`) immediately
after each `merge`, before renaming the next lookup variable into that same
key name for the next `merge`.

## 3. ID-pool collision risk when sampling an "extra" pool

When a second file's ID range overlaps a first file's already-built ID pool
and needs additional IDs *beyond* that pool (e.g. a correspondence table with
more rows than the base firm-level file), sampling the extra IDs
independently over the same numeric range will collide with the base pool
often enough to fall short of the target row count. At Costa Rica's scale
(~142k IDs already used out of a ~7.9M range, needing ~130k more), a naive
independent draw undercounts by roughly the expected number of collisions
(~2,300 in that case) — small as a fraction of the range, but *not*
negligible against `n_needed`.

**Fix**: explicitly `merge ... keep(master) nogen` the candidate extra pool
against the already-used pool before counting toward `n_needed`, so only
genuinely-unused IDs are kept. `build_id_pool` in `_lib/mock_helpers.do`
already over-samples (1.4x + 2000) to absorb *within-pool* duplicate draws
from `runiform()`, but does **not** know about a separately-built pool it
needs to avoid — that exclusion has to be done by the caller before invoking
it, exactly as `examples/CostaRica/generate_mock_CR.do`'s `gen_revec_corresp`
does.

## 4. Literal `/*` inside a `*`-comment

A bare `/*` anywhere inside a `*`-prefixed line comment — even one just
describing or quoting text — makes Stata's parser treat everything from that
point to the next `*/` (or end of file, if none exists) as one unterminated
block comment. The whole rest of the file silently stops executing: no error
is raised, the script just does nothing past that point. This is easy to
trigger when a comment quotes codebook text or another `.do` file's contents
verbatim.

**Fix**: never write a literal `/*` in a `*`-comment; rephrase or escape it.

## 5. `nombre` / free-text disclosure risk (not a bug, but a hard rule)

Any high-cardinality string field (see `codebook_format.md`'s free-text
threshold) must **never** have the codebook's real `Examples:` values copied
into generated mock data — those are real entities (company names, in CR's
case) and copying them defeats the purpose of using synthetic data. Generate
placeholder values with a similar shape instead (e.g.
`"MOCK FIRM " + string(_n, "%05.0f") + " SOCIEDAD ANONIMA"`), and still apply
the field's reported missing rate.

## 6. Category labels the codebook never actually exposes

A low-cardinality string variable can have all-blank `Examples` (i.e. the
codebook's per-variable block shows no real category strings at all, only a
`Tabulation` of *frequencies* with no visible value labels, or a labeled
numeric where the label defines aren't in the `.txt`). In that case there is
no real value to reuse — invent plausible placeholder category labels for
the domain and note in the generated script's comments that they're
synthetic, not real domain values (see `regimen_<yr>` in
`examples/CostaRica/generate_mock_CR.do` for the pattern).

## 7. A single oversized `program define` for one dataset can hang silently

A wide-panel dataset (e.g. 380 columns) generated as one giant `program define
gen_<fname> ... end` block can reproducibly stall partway through *execution*
(not parsing — the whole block echoes fine when defined) with no error and no
further log output, even though the exact same code runs instantly as a
standalone snippet outside that program. Confirmed via `display` checkpoints
between sections: the hang recurs at the same point across repeated runs, but
disappears once the program is split.

**Fix**: split any `program define` covering a wide dataset into several
smaller sequential programs (e.g. `gen_<fname>_a`, `_b`, `_c`) that all operate
on the same in-memory dataset (no `clear`/reload between them), called in order
from the orchestration section. Each split program needs its own copy of any
`local` used across the split — see gotcha #8.

## 8. `local` macros do not survive across split programs

Once a dataset's generator is split per gotcha #7, a `local` defined in the
first sub-program (e.g. `local N = <n_obs>`) is **not** visible in the later
sub-programs — Stata locals are scoped to the program that defines them, not
to the do-file. Referencing it there silently expands to an empty string,
turning `M_fam[`i',2] / `N'` into `.../ ` — an "invalid syntax" `r(198)` at the
very first line of the next sub-program.

**Fix**: re-declare any shared `local` (e.g. `local N = <n_obs>`) at the top of
every split sub-program.

## 9. `build_id_pool`'s default oversample isn't enough for a *second* exclusion

Gotcha #3 already covers excluding an already-used pool once. But when the
"extra" pool then also needs to be excluded from a *different* already-used
pool (e.g. `revec_corresp`'s extra IDs must avoid `revec_group`'s pool, and
separately `trans_clean_corresp`'s extra IDs must avoid it too), the default
1.4x+2000 oversample is calibrated only for *internal* duplicate collisions
within `build_id_pool` itself — it has no margin left for a second, external
exclusion step, and `build_id_pool` can return exactly `n_needed` rows that
then shrink below what's needed once the caller's own exclusion merge runs,
triggering the "pool extra insuficiente" `exit 198` (see gotcha #3) even though
`build_id_pool` itself succeeded.

**Fix**: pad the `n_needed` passed to `build_id_pool` for any "extra" pool that
will be excluded against another already-used pool afterward — e.g. request
`ceil(n_extra * 1.05) + 2000` instead of `n_extra`, sized roughly to the
expected overlap rate (base pool size / total ID range), then trim down to the
real target after the exclusion merge.

## 10. Matching a codebook field's *type* isn't enough when it codes a real external classification

A string field that is type-constrained (e.g. `str4`, purely numeric, because
downstream code `destring`s it) can still need a realistic *value domain*, not
just the right shape. `firm_ciiu4`/`ciiu4_<yr>` in Costa Rica encodes ISIC
Rev.4 economic-activity codes — `gen_synth_cat`-style sequential IDs like
`1000 + ceil(370*runiform())` satisfy the str4-numeric constraint but only
ever produce values in one narrow numeric band (e.g. `1001`-`1374`, i.e. ISIC
divisions 10-13 only). Downstream code that classifies firms by 2-digit
division (`floor(code/100)`) into broad sector buckets (manufacturing,
services, KIS, etc. — see `1-prepare_data.do`'s `RD_class`/`KIS`
classification) then silently loses entire buckets: a `merge` against a
reference table pre-filtered to a division range the mock data never
produces (e.g. divisions ≥45 for KIS/services) matches 0 observations, which
doesn't error immediately but breaks a `reshape`/`rename` several steps later
with a confusing `variable ... not found`, far from the actual cause.

**Fix**: when a field codes a real, external, well-known classification
(ISIC/CIIU, NACE, country/currency codes, postal/admin codes, etc.), don't
invent sequential IDs — sample real codes from a reference list. Check the
project's `raw_external_data/` (or similar) for an existing authoritative
list first (Costa Rica already has one at
`raw_external_data/classif/ISIC_Rev_4_english_structure.txt`); import it
once, keep only the codes at the codebook field's exact digit-length, and
draw from that list (e.g. via a `merge m:1 <random index>` against an
indexed copy of the list) instead of synthesizing a numeric ID. This
preserves both the type *and* the real category spread that downstream
classification logic depends on.

## 11. Order-biased subset sampling can silently empty downstream cells

When one file or flag is a subset of another population (foreign firms,
treated firms, SEZ firms, special firms, etc.), never create it by sorting on
an existing order and taking the first N rows. Earlier merges, ID-pool builds,
or reference-list joins can leave the dataset ordered by an unrelated domain
such as sector, geography, or ID range. The subset will still have the right
row count and valid IDs, but downstream tables/regressions can silently lose
variation: e.g. all treated firms land outside manufacturing, so a
manufacturing-only regression reports coefficients as `0.000` with standard
errors `(.)` instead of throwing an error.

**Fix**: create a fresh random variable immediately before subset selection,
sort on that random variable (or use an explicit random rank), then keep or
flag the target number of rows. When downstream code explicitly analyzes
broad domains such as sector, manufacturing, KIS/R&D class, region, or year,
tab the subset flag against those domains during self-verification. If an
important domain has zero subset support and the intended mock is supposed to
exercise that branch, redraw the subset with simple stratification or quotas
over the broad domain before saving outputs.

## 12. A clean full-pipeline run can still leave degenerate analysis outputs

It is possible for the raw mock data to pass row-count, merge-integrity, and
pipeline execution checks while final tables or regressions still contain
uninformative cells. In the Costa Rica mock run, the end-to-end
`Master.do` completed, but some regression tables reported standard errors as
`(.)`, a symptom of too little within-cell variation, collinearity, or tiny
subgroup samples rather than a runtime failure. This is especially likely when
a rare flag (FDI, treated, SEZ, superstar, policy exposure, etc.) is assigned
independently of the domains used later for subgroup analysis.

**Fix**: after identifying downstream domains in the consuming code, generate
rare flags with simple stratification or quota floors across the broad cells
that matter (year, sector bucket, manufacturing/non-manufacturing, KIS/R&D
class, region, etc.) when feasible. Preserve both treated and untreated support
and nonmissing outcomes inside targeted cells. During self-verification, add
lightweight diagnostics for the raw data that tab key flags by those cells and
check that key outcomes/regressors are not constant or all missing under the
same broad filters. If the user later runs the full pipeline, inspect logs and
result tables for `(.)` standard errors, `no observations`, all-zero outputs,
or all-missing generated variables; use those findings to tighten the mock's
joint support rather than treating "no Stata error" as sufficient.
