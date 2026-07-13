# Codebook text format

Codebooks are produced by a `codebook_raw_<Name>.do`-style generator — a
project-specific script run against real data, out of scope for this skill
(see `SKILL.md`'s "Explicitly out of scope"): for each raw `.dta`, it runs
`describe, fullnames` then `codebook *, head`,
captured to an smcl log and translated to `.txt` with
`translate ..., linesize(150)`. One `.txt` file per raw dataset, named
`<fname>_codebook.txt`.

Every codebook has two parts, in this order.

## Part 1 — `describe` block

A fixed-width table between two full-width `---` rule lines, header:

```
Variable      Storage   Display    Value
    name         type    format    label      Variable label
```

Then the file header gives the row/column counts to cross-check against
Part 2's per-file `Observations:`/`Variables:` lines:

```
Contains data from <path>/<fname>.dta
 Observations:         4,216
    Variables:            29                  9 Oct 2023 18:09
```

Notes when parsing:
- A long variable name wraps the rest of its row (type/format/label) onto the
  *next* line, e.g.:
  ```
  foreign_group_id
                  int     %10.0g                1 mnc_id
  ```
- `Variable label` is often blank.
- Storage type of `strNN` marks a string variable; anything else (`byte`,
  `int`, `long`, `float`, `double`) is numeric.

## Part 2 — per-variable `codebook` blocks

One block per variable, each delimited by a full-width `---` rule line above
and below a header line (`<varname>` left-aligned, its Variable label
right-aligned). Inside:

```
                  Type: Numeric (float)

                   Range: [49494,6437264]               Units: 1
           Unique values: 4,216                     Missing .: 0/4,216

                    Mean: 2.5e+06
               Std. dev.:  287056

             Percentiles:     10%       25%       50%       75%       90%
                          2.4e+06   2.4e+06   2.5e+06   2.6e+06   2.6e+06
```

or, for a low-cardinality numeric/string variable, `Range`+`Percentiles` is
replaced by `Tabulation`:

```
              Type: Numeric (byte)

               Range: [8,12]                        Units: 1
       Unique values: 4                         Missing .: 0/4,216

          Tabulation: Freq.  Value
                          1  8
                         18  9
                      4,194  10
                          3  12
```

Strings use `Missing "":` instead of `Missing .:` and, above the free-text
unique-value threshold, an `Examples:` block instead of `Tabulation` — quoted
example values, **never** to be reused verbatim in mock output (see
`gotchas.md`):

```
                Type: String (str60), but longest is str50

         Unique values: 2,484                     Missing "": 322/4,216

              Examples: "MOCK EXAMPLE ONE SOCIEDAD ANONIMA"
                        "MOCK EXAMPLE TWO SERVICIOS SOCIEDAD ANONIMA"
```

Fields to extract per variable, all present except where noted:
- `Type`: `Numeric (<storage>)` or `String (str<N>)`, sometimes suffixed
  `, but longest is str<M>` — use `<N>` (the declared width) for `gen`.
- `Range: [min,max]` (numeric only, omitted when `Tabulation` is shown
  instead).
- `Unique values: <count>`.
- `Missing .: <n>/<N>` (numeric) or `Missing "": <n>/<N>` (string) — `<N>` is
  this file's total `Observations:`, should match Part 1's header count.
- `Mean:` / `Std. dev.:` (numeric, continuous only).
- `Percentiles: 10% 25% 50% 75% 90%` row + values row (numeric, continuous
  only) — use median (50%) and p90 as `gen_fin_var`'s `med`/`p90` args for
  financial variables.
- `Tabulation: Freq. Value` pairs (numeric or string, low-cardinality only) —
  frequencies sum to `Observations:` minus any separately-reported missing
  count; a `""` or `.` row inside the tabulation itself is also valid (see
  `foreign_list` above: `326  .` appears as its own tabulation row).
- `Examples:` quoted values (string, high-cardinality only) — **read for
  format shape only** (e.g. "looks like a company name string"), never
  copied into generated data.
- `Warning:` lines (e.g. "has embedded blanks") — informational, no parsing
  action needed beyond confirming the string type.

## Gotcha specific to this format

A literal `/*` inside a `*`-comment referencing this file's own text (e.g. in
a generator's header comment) makes Stata's parser treat the rest of the
entire `.do` file as one unterminated block comment, silently skipping all
execution with no error. Never write a bare `/*` in a Stata comment, even
when quoting or describing codebook text.
