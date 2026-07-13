* Pointer, not a copy — the source of truth for these programs is
* code/mock_data_generation/_lib/mock_helpers.do (repo root). `do` that file
* directly in generated scripts:
*
*   do "code/mock_data_generation/_lib/mock_helpers.do"
*
* It defines two programs:
*
* build_id_pool n_needed min_id max_id filename
*   Draws a deduplicated pool of `n_needed` unique long IDs uniformly from
*   [min_id, max_id], oversampling to absorb duplicate runiform() draws, and
*   saves it as a one-column ID_anon .dta at `filename`. Errors out (rc 198)
*   rather than silently returning a short pool if oversampling wasn't
*   enough — see gotchas.md #3 for why a second, independent build_id_pool
*   call against an overlapping range still needs an explicit exclusion step
*   the caller must do itself.
*
* gen_fin_var varname missrate med p90
*   Generates a log-normal continuous variable calibrated to a reported
*   median and 90th percentile (both readable straight off a numeric
*   codebook block's Percentiles line), then applies missingness at
*   `missrate`. Use for any continuous financial variable.
*
* Do not redefine these inline in a generated <Name> script — always `do`
* the shared file, so fixes made there (or found for a future country) apply
* to every generator, including generate_mock_CR.do.
