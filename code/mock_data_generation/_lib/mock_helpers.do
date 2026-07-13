*===============================================================================
* mock_helpers.do
*
* Programas auxiliares compartidos para generadores de datos mock por país
* (code/mock_data_generation/<Name>/generate_mock_<Name>.do). Extraídos de
* code/mock_data_generation/CostaRica/generate_mock_CR.do (ver
* docs/plans/2026-07-10_step2-mock-data-costa-rica.md y
* docs/plans/2026-07-10_step2-mock-data-skill-generalized.md).
*
* `do` este archivo antes de usar build_id_pool o gen_fin_var.
*===============================================================================

********************************************************************************
* build_id_pool: pool de IDs únicos en un rango dado (sobremuestreo + dedup)
* args: n_needed  min_id  max_id  filename
*
* Sobremuestrea por 1.4x + 2000 para absorber duplicados de runiform() sobre
* rangos numéricos grandes, luego deduplica y recorta a n_needed. Si el
* sobremuestreo no alcanza, falla explícitamente en vez de guardar un pool
* incompleto en silencio (ver docs/codebooks gotcha: ID-pool collisions).
********************************************************************************
capture program drop build_id_pool
program define build_id_pool
	args n_needed min_id max_id filename
	clear
	local oversample = ceil(`n_needed' * 1.4) + 2000
	quietly set obs `oversample'
	gen long id_cand = `min_id' + floor((`max_id' - `min_id' + 1) * runiform())
	duplicates drop id_cand, force
	quietly count
	if r(N) < `n_needed' {
		display as error "build_id_pool: sobremuestreo insuficiente (`r(N)' < `n_needed'), aumentar factor"
		exit 198
	}
	gen long obs_n = _n
	keep if obs_n <= `n_needed'
	drop obs_n
	rename id_cand ID_anon
	sort ID_anon
	save "`filename'", replace
end

********************************************************************************
* gen_fin_var: variable financiera continua, log-normal con missing
* args: varname  missrate  med  p90
*
* Calibra mu/sigma de una log-normal a partir de la mediana y el percentil 90
* reportados por el codebook (`codebook_format.md`), luego aplica missingness
* uniforme a la tasa dada.
********************************************************************************
capture program drop gen_fin_var
program define gen_fin_var
	args varname missrate med p90
	local mu = ln(`med')
	local sigma = (ln(`p90') - ln(`med')) / 1.2816
	quietly gen double `varname' = exp(rnormal(`mu', `sigma'))
	quietly replace `varname' = . if runiform() < `missrate'
end
