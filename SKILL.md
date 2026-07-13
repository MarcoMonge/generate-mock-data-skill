---
name: generate-mock-data
description: Generates a co-aligned synthetic (mock) dataset bundle for a country from a directory of codebooks, replicating schema, scale, and cross-file ID relationships without touching any real data. Use when asked to generate mock/synthetic raw data for a country, or to regenerate a mock bundle after that country's codebooks change. Invoke with /generate-mock-data <codebooks_dir> <output_dir>.
---

# generate-mock-data

Produces a mock raw-data bundle for one country from its codebooks alone —
no real data is read. The bundle is co-generated as one batch so that merge
keys (firm IDs, group IDs, buyer/seller IDs, etc.) align across files exactly
as they do in the real data, letting downstream cleaning/integration code run
against it unmodified.

Built by generalizing a working Costa Rica generator, the first instance of
this pattern — see `examples/CostaRica/generate_mock_CR.do` for the full,
working script this skill's pattern was generalized from.

## Invocation

```
/generate-mock-data <codebooks_dir> <output_dir>
```

Exactly two inputs — do not ask for or infer anything else:
- `<codebooks_dir>`: directory containing one `*_codebook.txt` per raw dataset
  (Stata `describe` + `codebook` output; exact format in
  `references/codebook_format.md`). The directory's basename is `<Name>`
  (e.g. `docs/codebooks/CostaRica` → `CostaRica`).
- `<output_dir>`: directory to save the generated mock `.dta` files.

## Procedure

### 1. Parse codebooks
Parse every `*_codebook.txt` in `<codebooks_dir>` into a per-variable schema:
name, storage type, display format, value label, the file's `Observations:`
count, and each variable's stats block (Type; Range + Percentiles for
numeric, or Tabulation Freq/Value pairs for categorical numeric/string;
Unique values; Missing count; Examples for free-text string). Match against
`references/codebook_format.md`.

### 2. Derive `<Name>`
`<Name>` = basename of `<codebooks_dir>`.

### 3. Infer merge keys and cross-file ID relationships
A standalone codebook cannot say two ID columns in *different* files share a
population — that only shows up in how the files are actually joined
downstream, in whatever code consumes these raw datasets (cleaning,
integration, or analysis scripts). Folder layout for that code varies by
project, so don't assume one:
- Grep the project for each parsed file's name and for each of its ID-like
  variable names, to find any script that reads more than one of these files
  together.
- If nothing turns up, ask the user where the code that merges/cleans
  `<Name>`'s raw files lives, rather than assuming a specific path.

From whatever code you find, determine:
- Which ID-like variables across the parsed files are the same underlying ID
  population, possibly renamed (e.g. a `_anon` suffix stripped, or a
  `_group`/`_g` suffix meaning "the same population, group level").
- Which files are a subset of another file's ID pool (e.g. a "foreign firms"
  or "special firms" file filtered from a larger firm-level file).

Infer from usage, not from codebooks alone. If no consuming code exists yet
for `<Name>` — the grep turns up nothing and the user confirms there's no
merge/cleaning code to look at — check whether `mattpocock-skills:grilling`
appears in the available-skills list before relying on it (it's a separate
plugin, not bundled with this skill, so it may not be installed for every
user/team). If it's available, invoke it instead of a single flat question:
walk the user through every ID-like variable pair across the parsed files one
at a time, proposing your best-guess relationship (same population possibly
renamed, subset of another file's pool, or independent) from name similarity
as the recommended answer, and wait for confirmation or correction before
moving to the next pair. Do not proceed to step 5 until every pair has been
resolved this way. If it's *not* available, fall back to asking the same
question directly, one pair at a time in the same manner, and mention once in
the final report that installing the `mattpocock` plugin
(`mattpocock-skills:grilling`) would make this step more thorough.

If code exists but still doesn't clarify a relationship between two files, do
**not** guess — treat that pair as independent ID pools and say so explicitly
in the final report.

### 4. Classify string variables: free text vs. categorical
For every string variable: `unique-value count / Observations` from the
codebook.
- **Above ~5%** → free text. Never reuse the codebook's real `Examples`
  values (disclosure risk) — generate synthetic placeholders instead.
- **At or below ~5%** → categorical. Reuse the codebook's real tabulated
  category labels verbatim, sampled at the codebook's reported frequencies.
- **Borderline (~3-7%)** → flag it in the final report for a manual second
  look instead of silently picking a side.

### 5. Generate `code/mock_data_generation/<Name>/generate_mock_<Name>.do`
Write one Stata script for the whole batch that:
- Opens with `do "code/mock_data_generation/_lib/mock_helpers.do"` to load
  the shared `build_id_pool` and `gen_fin_var` programs (see
  `references/mock_helpers.do`). Reuse them rather than reimplementing ID
  sampling or financial-variable synthesis — they already encode the fixes in
  `references/gotchas.md`.
- Sets a fixed `set seed` for reproducibility.
- Builds **one shared ID pool** for the batch (largest/base file first), so
  every file's IDs are drawn from — or checked against — that same pool.
  Generate files in dependency order: any file whose IDs are a subset of
  another file's pool must be generated *after* that pool exists.
- One `program define gen_<fname>` block per dataset, each generating at full
  scale (`N` = that codebook's `Observations:`), every variable synthesized
  from its own codebook block only (type, range/percentiles or tabulation,
  missing rate). No cross-year trend modeling by default — see
  `references/gotchas.md` for the CR growth-rate pattern as an optional,
  non-default technique for wide year-panel codebooks.
- Applies the step 4 free-text/categorical classification.
- Saves each dataset to `<output_dir>/<fname>.dta`, filename matching the
  codebook (`<fname>_codebook.txt` → `<fname>.dta`).
- Checks every item in `references/gotchas.md` before considering the script
  done.

### 6. Run the generated script
Execute in Stata batch mode with cwd at the project root — wherever
`<output_dir>` and `code/mock_data_generation/_lib/mock_helpers.do` are
anchored from.

### 7. Self-verify
Don't trust a clean exit alone — check explicitly and report each:
- **Row counts**: every output `.dta` row count matches its codebook's
  `Observations:`.
- **No errors**: the run log has zero `r()` error codes.
- **Referential integrity**: for every subset/superset relationship inferred
  in step 3, confirm the subset file's IDs actually exist in the superset's
  pool (merge and check for unmatched-from-subset).

### 8. Report
Files generated and row counts; any borderline free-text classifications
flagged in step 4; any ID relationships that couldn't be inferred in step 3;
the step 7 self-verification results, pass/fail per check.

## Explicitly out of scope

Do not do these even if the request seems to imply them:
- Wiring a `use_mock` flag into any pipeline, or running a pipeline
  end-to-end. This skill only generates mock data.
- Producing the input codebooks themselves — that's a separate
  `codebook_raw_<Name>.do` run against real data, a prerequisite this skill
  assumes is already done.
- Deciding git / git-lfs handling of the generated `.dta` outputs.
- Cross-year trend modeling as a default, built-in behavior.

## References

- `references/codebook_format.md` — exact codebook text layout to parse.
- `references/gotchas.md` — real bugs hit building the Costa Rica generator;
  check every one against the generated script before running it.
- `references/mock_helpers.do` — what `build_id_pool` and `gen_fin_var` do
  and how to call them.
- `examples/CostaRica/generate_mock_CR.do` — full worked example: the actual
  Costa Rica generator this skill's pattern was generalized from.
