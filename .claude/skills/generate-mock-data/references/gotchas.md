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
