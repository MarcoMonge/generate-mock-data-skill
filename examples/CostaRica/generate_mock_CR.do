clear all
set more off
version 17

*===============================================================================
* generate_mock_CR.do
*
* Genera versiones sintéticas (mock) de las 4 bases crudas anonimizadas de
* Costa Rica usadas por code/cleaning/CostaRica/cleaning_CR.do:
*   revec_group_2019          balance sheet CIT, nivel firma/grupo (panel wide)
*   revec_corresp_2019        tabla de correspondencia de IDs
*   all_foreign_2019          registro de firmas de capital extranjero (FDI)
*   trans_clean_corresp_2019  transacciones firma-a-firma (D-151)
*
* El esquema (nombres, tipos, escalas, tasas de missing, categorías) se
* hardcodea a partir de los codebooks en docs/codebooks/CostaRica (ver plan
* docs/plans/2026-07-10_step2-mock-data-costa-rica.md). No se parsean los
* .txt en tiempo de ejecución: eso queda para el "skill" genérico
* (.claude/skills/generate-mock-data/, ver
* docs/plans/2026-07-10_step2-mock-data-skill-generalized.md).
*
* build_id_pool y gen_fin_var viven en code/mock_data_generation/_lib/
* mock_helpers.do (compartido con futuros generadores por país).
*
* Salida: raw_data/CostaRica/mock/<fname>.dta (mismo nombre que la base real).
* Debe ejecutarse con el cwd en la raíz del repo (igual que Master.do).
*===============================================================================

do "code/mock_data_generation/_lib/mock_helpers.do"

set seed 20260710

global mockdir "raw_data/CostaRica/mock"
capture mkdir "raw_data/CostaRica"
capture mkdir "${mockdir}"

global years_cr "2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019"

* Tamaños reales tomados de "Observations:" en cada codebook
global N_revec_group   = 142081
global N_revec_corresp = 271617
global N_all_foreign   = 4216
global N_trans         = 9687438

* --- de la Decisión #7 del plan: all_foreign debe ser subconjunto de las
* firmas foreign_list==1 de revec_group. El conteo real de foreign_list==1
* en revec_group (2,338) es MENOR que N_all_foreign (4,216), así que para
* poder construir un subconjunto válido, en el mock generamos más firmas
* foreign_list==1 en revec_group (mismo orden de magnitud, ~3% del total).
global N_foreign_in_group = 4600

********************************************************************************
* 1. revec_group_2019 (142,081 firmas, 380 variables) - establece el pool de IDs
********************************************************************************
capture program drop gen_revec_group
program define gen_revec_group

	tempfile pool_group geo_lookup
	build_id_pool ${N_revec_group} 1242 7881487 "`pool_group'"
	use "`pool_group'", clear

	* ---- identificadores base -------------------------------------------------
	* length_orig_ced: categorías 6-12, ponderadas según codebook (~89k en 10, ~48k en 9)
	gen double u_loc = runiform()
	gen byte length_orig_ced = 10
	replace length_orig_ced = 6  if u_loc < 0.00001
	replace length_orig_ced = 7  if u_loc >= 0.00001 & u_loc < 0.00002
	replace length_orig_ced = 8  if u_loc >= 0.00002 & u_loc < 0.0056
	replace length_orig_ced = 9  if u_loc >= 0.0056  & u_loc < 0.345
	replace length_orig_ced = 10 if u_loc >= 0.345   & u_loc < 0.973
	replace length_orig_ced = 11 if u_loc >= 0.973   & u_loc < 0.9737
	replace length_orig_ced = 12 if u_loc >= 0.9737
	drop u_loc

	* fuente: casi constante = 3, con missing base (~0.4%)
	gen byte fuente = 3
	gen double u_base = runiform()
	local missbase = 572/${N_revec_group}
	replace fuente = . if u_base < `missbase'

	* ---- geografía: lookup de 81 cantones, luego join a nivel firma -----------
	preserve
		clear
		set obs 81
		gen canton_id = _n
		gen str13 canton = "canton_" + string(canton_id, "%02.0f")
		* provincias reales de Costa Rica, con frecuencias ~ codebook
		gen double up = runiform()
		gen str10 provincia = "san jose"
		replace provincia = "alajuela"   if up < 0.31
		replace provincia = "cartago"    if up >= 0.31 & up < 0.40
		replace provincia = "heredia"    if up >= 0.40 & up < 0.47
		replace provincia = "guanacaste" if up >= 0.47 & up < 0.54
		replace provincia = "puntarenas" if up >= 0.54 & up < 0.61
		replace provincia = "limon"      if up >= 0.61 & up < 0.66
		drop up
		gen double ur = runiform()
		gen str2 region = "C"
		replace region = "A"  if ur < 0.10
		replace region = "B"  if ur >= 0.10 & ur < 0.19
		replace region = "Ch" if ur >= 0.19 & ur < 0.31
		replace region = "N"  if ur >= 0.31 & ur < 0.39
		replace region = "P"  if ur >= 0.39 & ur < 0.47
		drop ur
		gen str3 municipality_code = string(canton_id, "%03.0f")
		gen float lat = 8.53 + (10.89 - 8.53) * runiform()
		save "`geo_lookup'", replace

		* distritos: ~5 por cantón (405), se completa a 415 repitiendo cantones
		clear
		set obs 415
		gen distrito_id = _n
		gen canton_id = 1 + mod(distrito_id - 1, 81)
		gen str34 distrito = "distrito_" + string(distrito_id, "%03.0f")
		tempfile distrito_lookup
		save "`distrito_lookup'", replace
	restore

	gen double u_geo = runiform()
	gen int distrito_id = ceil(415 * u_geo)
	drop u_geo
	merge m:1 distrito_id using "`distrito_lookup'", nogen keep(match)
	merge m:1 canton_id using "`geo_lookup'", nogen keep(match)
	rename distrito distrito_full
	gen str34 distrito = distrito_full
	drop distrito_full distrito_id

	gen str11 district = municipality_code + "0" + string(canton_id, "%02.0f") + "_CCSS"
	replace district = "" if runiform() < 947/${N_revec_group}
	replace canton = "" if runiform() < 1301/${N_revec_group}
	replace provincia = "" if runiform() < 1291/${N_revec_group}
	replace distrito = "" if runiform() < 1934/${N_revec_group}
	replace region = "" if runiform() < 1301/${N_revec_group}
	replace municipality_code = "" if runiform() < 1301/${N_revec_group}
	replace lat = . if runiform() < 1301/${N_revec_group}
	drop canton_id

	* ---- códigos de grupo / sector institucional -------------------------------
	gen str4 grupo_corporativo = string(1 + floor(5729 * runiform()), "%04.0f")
	gen str4 grupo_empresarial = string(1 + floor(2416 * runiform()), "%04.0f")
	gen str7 sector_institucional = "S" + string(100001 + floor(50 * runiform()) * 1000, "%06.0f")
	foreach v in grupo_corporativo grupo_empresarial sector_institucional {
		replace `v' = "" if u_base < `missbase'
	}
	gen str8 relacion_dentro_ge = "TIPO" + string(1 + floor(25 * runiform()), "%02.0f")
	replace relacion_dentro_ge = "" if u_base < `missbase'
	drop u_base

	* ---- bloques anuales categóricos (ae, ciiu4, cantidad_actividades,
	*      regimen, estado, tamaño, ZF_broad) ------------------------------------
	foreach yr of global years_cr {
		gen double u_`yr' = runiform()

		gen str5 ae_`yr' = "AE" + string(1 + floor(139 * runiform()), "%03.0f")
		replace ae_`yr' = "" if u_`yr' < 894/${N_revec_group}

		gen str4 ciiu4_`yr' = string(111 + floor(9889 * runiform()), "%04.0f")
		replace ciiu4_`yr' = "" if u_`yr' < 1035/${N_revec_group}

		gen str2 cantidad_actividades`yr' = string(1 + floor(9 * runiform()), "%1.0f")
		replace cantidad_actividades`yr' = "" if u_`yr' < 572/${N_revec_group}

		gen byte estado_temp = 1
		replace estado_temp = 9 if runiform() < 0.73
		gen str1 estado_`yr' = string(estado_temp, "%1.0f")
		replace estado_`yr' = "" if u_`yr' < 572/${N_revec_group}
		drop estado_temp

		* regimen: valores reales no visibles en el codebook (solo blancos en
		* "Examples"); se usan etiquetas de régimen tributario/aduanero
		* plausibles para CR, marcador explícito de que son sintéticas.
		gen byte reg_pick = 1 + floor(6 * runiform())
		gen str13 regimen_`yr' = "DEFINITIVO"
		replace regimen_`yr' = "ZONA FRANCA"  if reg_pick == 2
		replace regimen_`yr' = "PERFECC ACT"  if reg_pick == 3
		replace regimen_`yr' = "TRANSITO"     if reg_pick == 4
		replace regimen_`yr' = "DEVOLUTIVO"   if reg_pick == 5
		replace regimen_`yr' = "ADM TEMPORAL" if reg_pick == 6
		replace regimen_`yr' = "" if u_`yr' < 572/${N_revec_group}
		drop reg_pick

		gen byte tamano_`yr' = 1
		gen double u_tam = runiform()
		replace tamano_`yr' = 2 if u_tam >= 0.70 & u_tam < 0.88
		replace tamano_`yr' = 3 if u_tam >= 0.88 & u_tam < 0.96
		replace tamano_`yr' = 4 if u_tam >= 0.96
		replace tamano_`yr' = . if u_`yr' < 0.55
		drop u_tam

		gen byte ZF_broad_`yr' = 0
		replace ZF_broad_`yr' = 1 if runiform() < 0.0012
		replace ZF_broad_`yr' = . if u_`yr' < 572/${N_revec_group}

		drop u_`yr'
	}
	rename tamano_2005 tamaão_2005
	rename tamano_2006 tamaão_2006
	rename tamano_2007 tamaão_2007
	rename tamano_2008 tamaão_2008
	rename tamano_2009 tamaão_2009
	rename tamano_2010 tamaão_2010
	rename tamano_2011 tamaão_2011
	rename tamano_2012 tamaão_2012
	rename tamano_2013 tamaão_2013
	rename tamano_2014 tamaão_2014
	rename tamano_2015 tamaão_2015
	rename tamano_2016 tamaão_2016
	rename tamano_2017 tamaão_2017
	rename tamano_2018 tamaão_2018
	rename tamano_2019 tamaão_2019

	gen str4 firm_ciiu4 = ciiu4_2019
	gen str5 firm_AE = ae_2019

	* ---- bloques anuales financieros (escala tomada de percentiles reales) ----
	* orden de args: nombre_stem  tasa_missing  mediana  p90
	gen_fin_var trabaj_2005     0.674 3        18
	gen_fin_var salarios_2005   0.674 3400000  34000000
	gen_fin_var exports_2005    0.986 68000    3900000
	gen_fin_var imports_2005    0.936 24000    780000
	gen_fin_var total_activo_neto_2005 0.698 19000000 260000000
	gen_fin_var activos_fijos_2005     0.70  8000000  110000000
	gen_fin_var ingresosir_2005        0.65  25000000 280000000
	gen_fin_var ingresos_finan_2005    0.85  500000   9000000
	gen_fin_var otros_ingresos_2005    0.80  1500000  22000000
	gen_fin_var total_de_gastos_2005   0.65  28000000 320000000
	gen_fin_var costo_de_ventas_2005   0.65  19000000 230000000
	gen_fin_var intereses_y_gastos_2005 0.85 900000   14000000
	gen_fin_var gastos_de_ventas_y_adm_2005 0.70 7500000 85000000
	gen_fin_var compras_2005    0.65  17000000 210000000
	gen_fin_var ventas_2005     0.623 30000000 300000000
	gen_fin_var va_2005         0.746 9500000  93000000

	local fin_stems "trabaj salarios exports imports total_activo_neto activos_fijos ingresosir ingresos_finan otros_ingresos total_de_gastos costo_de_ventas intereses_y_gastos gastos_de_ventas_y_adm compras ventas va"

	foreach stem of local fin_stems {
		local i = 1
		foreach yr of global years_cr {
			if `yr' != 2005 {
				local growth = 1 + 0.035 * (`yr' - 2005)
				quietly gen double `stem'_`yr' = `stem'_2005 * `growth' * exp(rnormal(0, 0.25)) if `stem'_2005 != .
			}
			local ++i
		}
	}

	* variables 2019-only de IVA (mismo orden de magnitud que ventas/2)
	gen_fin_var ingresos_iv_ene_jun_2019  0.70 14000000 140000000
	gen_fin_var ingresos_iva_jul_dic_2019 0.70 15000000 150000000

	* ---- flags y campos misceláneos --------------------------------------------
	gen byte foreign_list = 0
	gen long obs_n = _n
	sort obs_n
	replace foreign_list = 1 if obs_n <= ${N_foreign_in_group}
	quietly count
	local total = r(N)
	gen double u_shuf = runiform()
	sort u_shuf
	drop u_shuf obs_n
	replace foreign_list = . if runiform() < 572/${N_revec_group}

	gen int corp_group = 1 + floor(5868 * runiform())
	gen int empresarial = 1 + floor(4107 * runiform())
	replace corp_group = . if runiform() < 572/${N_revec_group}
	replace empresarial = . if runiform() < 572/${N_revec_group}
	gen double ced_group = ID_anon
	replace ced_group = . if corp_group == .

	egen ZF = rowmax(ZF_broad_*)
	replace ZF = . if ZF_broad_2005 == . & ZF_broad_2019 == .

	gen byte cinde_firm = 0
	replace cinde_firm = 1 if runiform() < 0.001
	replace cinde_firm = . if ZF == .

	gen byte sector_g = 1 + floor(20 * runiform())
	replace sector_g = . if runiform() < 2136/${N_revec_group}
	label define sector_lab 1 "Agriculture, forestry and fishing" 2 "Manufacturing" 3 "Electricity and Gas" 4 "Water Supply, Sewerage and Waste Management" 5 "Construction" 6 "Wholesale and Retail Trade" 7 "Transportation and Storage" 8 "Accommodation and Food Services" 9 "Information and Communication" 10 "Real Estate" 11 "Professional, Scientific and Technical" 12 "Administrative and Support Service" 13 "Education" 14 "Human Health and Social Work" 15 "Art, Entertainment and Recreation" 16 "Other Services" 17 "Financial Activities" 18 "Mining and Quarrying" 19 "Public Administration" 20 "Diplomatic Activities", replace
	label values sector_g sector_lab

	gen byte sophistication = 4
	gen double u_soph = runiform()
	replace sophistication = 1 if u_soph < 0.012
	replace sophistication = 2 if u_soph >= 0.012 & u_soph < 0.232
	replace sophistication = 3 if u_soph >= 0.232 & u_soph < 0.494
	replace sophistication = . if runiform() < 1814/${N_revec_group}
	drop u_soph
	label define sector_sophis 1 "High-Tech" 2 "Medium High-Tech" 3 "Medium Low-Tech" 4 "Low-Tech", replace
	label values sophistication sector_sophis

	gen byte ifinancieras = (runiform() < 0.043)
	gen byte ipublicas = (runiform() < 0.014)
	gen byte inolucro = (runiform() < 0.022)
	foreach v in ifinancieras ipublicas inolucro {
		replace `v' = . if runiform() < 572/${N_revec_group}
	}

	gen int entry = 2005 + floor(15 * runiform())
	replace entry = . if runiform() < 572/${N_revec_group}
	gen int exit = entry + 1 + floor((2018 - entry) * runiform()) if entry < 2018
	replace exit = . if runiform() < 61901/${N_revec_group}

	gen byte ipubgrupo = ipublicas
	gen byte ifingrupo = ifinancieras
	gen byte inolucrogrupo = inolucro

	gen float forshare = 0
	replace forshare = round(100 * runiform(), .01) if runiform() < 0.10
	replace forshare = . if runiform() < 572/${N_revec_group}

	order ID_anon length_orig_ced fuente district grupo_corporativo grupo_empresarial sector_institucional
	compress
	save "${mockdir}/revec_group_2019.dta", replace

	* pool de IDs completo, para revec_corresp y trans_clean_corresp
	preserve
		keep ID_anon
		save "temp/mock_id_pool_CR.dta", replace
	restore

	preserve
		keep if foreign_list == 1
		keep ID_anon corp_group empresarial
		save "temp/mock_foreign_pool_CR.dta", replace
	restore

end

********************************************************************************
* 2. revec_corresp_2019 (271,617 filas, 10 variables)
********************************************************************************
capture program drop gen_revec_corresp
program define gen_revec_corresp

	* IDs "extra" (no presentes en revec_group): se excluyen explícitamente
	* los IDs ya usados por revec_group para garantizar unión sin colisiones
	* (dos pools independientes sobre el mismo rango numérico sí colisionan
	* en la práctica - con ~142k vs ~130k sobre un rango de ~7.9M se esperan
	* ~2,300 colisiones si no se excluyen).
	tempfile extra_pool
	local n_extra = ${N_revec_corresp} - ${N_revec_group}
	local oversample = ceil(`n_extra' * 1.6) + 3000
	clear
	quietly set obs `oversample'
	gen long id_cand = 1236 + floor((7881487 - 1236 + 1) * runiform())
	duplicates drop id_cand, force
	rename id_cand ID_anon
	merge 1:1 ID_anon using "temp/mock_id_pool_CR.dta", keep(master) nogen
	quietly count
	if r(N) < `n_extra' {
		display as error "gen_revec_corresp: sobremuestreo insuficiente para IDs extra (`r(N)' < `n_extra'')"
		exit 198
	}
	gen long obs_n = _n
	keep if obs_n <= `n_extra'
	drop obs_n
	sort ID_anon
	save "`extra_pool'", replace

	use "temp/mock_id_pool_CR.dta", clear
	append using "`extra_pool'"
	quietly count
	if r(N) != ${N_revec_corresp} {
		display as error "gen_revec_corresp: conteo final inesperado (`r(N)')"
		exit 198
	}

	gen double u_g = runiform()
	gen long ID_g_anon = ID_anon
	replace ID_g_anon = 1236 + floor((7881487 - 1236 + 1) * runiform()) if u_g < 0.05
	drop u_g

	gen double u_loc = runiform()
	gen byte length_orig_ced = 10
	replace length_orig_ced = 6  if u_loc < 0.000004
	replace length_orig_ced = 7  if u_loc >= 0.000004 & u_loc < 0.00002
	replace length_orig_ced = 8  if u_loc >= 0.00002  & u_loc < 0.0068
	replace length_orig_ced = 9  if u_loc >= 0.0068   & u_loc < 0.464
	replace length_orig_ced = 10 if u_loc >= 0.464    & u_loc < 0.964
	replace length_orig_ced = 11 if u_loc >= 0.964    & u_loc < 0.9641
	replace length_orig_ced = 12 if u_loc >= 0.9641
	gen byte length_orig_ced_g = length_orig_ced
	drop u_loc

	gen byte foreign_list = 0
	replace foreign_list = 1 if runiform() < 3890/271617
	replace foreign_list = . if runiform() < 116/271617

	gen int corp_group = .
	gen int empresarial = .
	replace corp_group = 1 + floor(5868 * runiform()) if runiform() > 253688/271617
	replace empresarial = 1 + floor(4107 * runiform()) if runiform() > 260488/271617

	gen byte ZF = 0
	replace ZF = 1 if runiform() < 365/271617

	gen byte cinde_firm = 0
	replace cinde_firm = 1 if runiform() < 277/271617

	gen float forshare = 0
	replace forshare = round(100 * runiform(), .01) if runiform() < 0.08
	replace forshare = . if runiform() < 52/271617

	order ID_anon ID_g_anon length_orig_ced length_orig_ced_g foreign_list empresarial corp_group ZF cinde_firm forshare
	compress
	save "${mockdir}/revec_corresp_2019.dta", replace

end

********************************************************************************
* 3. all_foreign_2019 (4,216 filas, 29 variables) - subconjunto de foreign_list
*    == 1 en revec_group_2019 (decisión #7 del plan)
********************************************************************************
capture program drop gen_all_foreign
program define gen_all_foreign

	use "temp/mock_foreign_pool_CR.dta", clear
	quietly count
	if r(N) < ${N_all_foreign} {
		display as error "gen_all_foreign: pool de foreign_list==1 insuficiente (`r(N)' < ${N_all_foreign})"
		exit 198
	}
	gen double u_sel = runiform()
	sort u_sel
	keep in 1/${N_all_foreign}
	drop u_sel

	rename corp_group corp_group_grp
	rename empresarial empresarial_grp

	gen long ID_group_anon = ID_anon
	replace ID_group_anon = corp_group_grp if corp_group_grp != . & runiform() < 0.4
	rename corp_group_grp corp_group
	rename empresarial_grp empresarial

	gen double u_loc = runiform()
	gen byte length_orig_ced = 10
	replace length_orig_ced = 8  if u_loc < 0.00024
	replace length_orig_ced = 9  if u_loc >= 0.00024 & u_loc < 0.00451
	replace length_orig_ced = 12 if u_loc >= 0.99929
	drop u_loc

	gen str19 fuente1 = "PART OF GROUP"
	gen double u1 = runiform()
	replace fuente1 = "BALANCE OF PAYMENTS" if u1 < 0.177
	replace fuente1 = "CINDE"               if u1 >= 0.177 & u1 < 0.197
	replace fuente1 = "ESTUDIO ECON"        if u1 >= 0.197 & u1 < 0.333
	replace fuente1 = "EXTERNAL_ORBIS_ETC"  if u1 >= 0.333 & u1 < 0.486
	replace fuente1 = "FDI"                 if u1 >= 0.486 & u1 < 0.572
	replace fuente1 = "OTHER"               if u1 >= 0.572 & u1 < 0.596
	drop u1

	gen str18 fuente2 = ""
	replace fuente2 = "CINDE"              if runiform() < 0.048
	gen str18 fuente3 = ""
	gen str18 fuente4 = ""
	gen str5  fuente5 = ""
	gen str5  fuente6 = ""
	gen str2  fuente7 = ""

	gen byte in_revec = 1
	replace in_revec = 0 if runiform() < 325/4216

	gen byte in_mh = 0
	replace in_mh = 1 if runiform() < 105/4216

	gen int foreign_group_id = 1 + floor(880 * runiform())
	replace foreign_group_id = . if runiform() < 2342/4216

	gen byte foreign_list = 1
	replace foreign_list = . if runiform() < 326/4216

	gen byte ZF = 0
	replace ZF = 1 if runiform() < 323/4216
	replace ZF = . if runiform() < 220/4216

	gen byte cinde_firm = 0
	replace cinde_firm = 1 if runiform() < 277/4216
	replace cinde_firm = . if ZF == .

	gen float forshare = 100
	replace forshare = round(83.3333 + (100-83.3333) * runiform(), .0001) if runiform() < 0.20
	replace forshare = . if runiform() < 262/4216

	* nombre: placeholder sintético - NUNCA se reutilizan los ejemplos reales
	* del codebook (riesgo de divulgación de nombres reales de empresas).
	gen long obs_id = _n
	gen str60 nombre = "MOCK FIRM " + string(obs_id, "%05.0f") + " SOCIEDAD ANONIMA"
	replace nombre = "" if runiform() < 322/4216
	drop obs_id

	gen str9 fuente_1 = "revec"
	gen str9 fuente_2 = "d151"
	replace fuente_2 = "" if runiform() < 95/4216
	gen str9 fuente_3 = "sicere"
	replace fuente_3 = "" if runiform() < 153/4216
	gen str9 fuente_4 = "imp"
	replace fuente_4 = "" if runiform() < 286/4216
	gen str9 fuente_5 = "exp"
	replace fuente_5 = "" if runiform() < 547/4216
	gen str9 fuente_6 = "ced_cus"
	replace fuente_6 = "" if runiform() < 1282/4216
	gen str9 fuente_7 = "llave_emc"
	replace fuente_7 = "" if runiform() < 2412/4216
	gen str9 fuente_8 = ""
	replace fuente_8 = "llave_emc" if runiform() < 103/4216
	gen str9 fuente_9 = ""

	order ID_anon ID_group_anon length_orig_ced fuente1 fuente2 fuente3 fuente4 fuente5 fuente6 fuente7 in_revec in_mh empresarial corp_group foreign_group_id foreign_list ZF cinde_firm forshare nombre fuente_1 fuente_2 fuente_3 fuente_4 fuente_5 fuente_6 fuente_7 fuente_8 fuente_9
	compress
	save "${mockdir}/all_foreign_2019.dta", replace

end

********************************************************************************
* 4. trans_clean_corresp_2019 (9,687,438 filas, 7 variables)
********************************************************************************
capture program drop gen_trans_clean_corresp
program define gen_trans_clean_corresp

	use "temp/mock_id_pool_CR.dta", clear
	gen long pool_idx = _n
	quietly count
	local n_pool = r(N)
	rename ID_anon ID_pool
	tempfile idpool
	save "`idpool'", replace

	clear
	quietly set obs ${N_trans}

	gen long seller_idx = 1 + floor(`n_pool' * runiform())
	gen long buyer_idx  = 1 + floor(`n_pool' * runiform())
	replace buyer_idx = buyer_idx + 1 if buyer_idx == seller_idx & buyer_idx < `n_pool'
	replace buyer_idx = buyer_idx - 1 if buyer_idx == seller_idx & buyer_idx >= `n_pool'

	rename seller_idx pool_idx
	merge m:1 pool_idx using "`idpool'", nogen keep(match)
	rename ID_pool seller_anon
	drop pool_idx
	rename buyer_idx pool_idx
	merge m:1 pool_idx using "`idpool'", nogen keep(match)
	rename ID_pool buyer_anon
	drop pool_idx

	gen double u_sl = runiform()
	gen byte seller_length_ced = 10
	replace seller_length_ced = 8  if u_sl < 0.0000064
	replace seller_length_ced = 9  if u_sl >= 0.0000064 & u_sl < 0.1889
	replace seller_length_ced = 10 if u_sl >= 0.1889    & u_sl < 0.994
	replace seller_length_ced = 12 if u_sl >= 0.994
	drop u_sl

	gen double u_bl = runiform()
	gen byte buyer_length_ced = 10
	replace buyer_length_ced = 9  if u_bl < 0.30
	replace buyer_length_ced = 10 if u_bl >= 0.30
	drop u_bl

	gen double u_yr = runiform()
	gen int year = 2015
	replace year = 2008 if u_yr < 0.05
	replace year = 2009 if u_yr >= 0.05 & u_yr < 0.10
	replace year = 2010 if u_yr >= 0.10 & u_yr < 0.16
	replace year = 2011 if u_yr >= 0.16 & u_yr < 0.22
	replace year = 2012 if u_yr >= 0.22 & u_yr < 0.29
	replace year = 2013 if u_yr >= 0.29 & u_yr < 0.37
	replace year = 2014 if u_yr >= 0.37 & u_yr < 0.45
	replace year = 2015 if u_yr >= 0.45 & u_yr < 0.55
	replace year = 2016 if u_yr >= 0.55 & u_yr < 0.65
	replace year = 2017 if u_yr >= 0.65 & u_yr < 0.77
	replace year = 2018 if u_yr >= 0.77 & u_yr < 0.90
	replace year = 2019 if u_yr >= 0.90
	drop u_yr

	* trans_: piso real de 2,500,000 (umbral de reporte D-151)
	local mu = ln(6200000 - 2500000)
	local sigma = (ln(31000000 - 2500000) - ln(6200000 - 2500000)) / 1.2816
	gen double trans_ = 2500000 + exp(rnormal(`mu', `sigma'))

	gen byte potentially_wrong = 0
	replace potentially_wrong = 1 if runiform() < 56889/9687438

	order seller_anon buyer_anon seller_length_ced buyer_length_ced year trans_ potentially_wrong
	compress
	save "${mockdir}/trans_clean_corresp_2019.dta", replace

end

********************************************************************************
* EJECUCIÓN
********************************************************************************
capture mkdir temp

gen_revec_group
gen_revec_corresp
gen_all_foreign
gen_trans_clean_corresp

capture erase "temp/mock_id_pool_CR.dta"
capture erase "temp/mock_foreign_pool_CR.dta"

display as result "Mock Costa Rica raw datasets generated in ${mockdir}"
