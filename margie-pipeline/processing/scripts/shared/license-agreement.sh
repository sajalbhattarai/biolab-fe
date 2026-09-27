#!/usr/bin/env bash
# license-agreement.sh — shows and records the pipeline-level licence agreement.
# Sourced by setup.sh; defines pipeline_licence_agreement().
#
# Skip conditions (no prompt shown):
#   MARGIE_ACCEPT_TERMS=1   already accepted (env var or previous run this session)
#   LICENCE_ACCEPT_ALL=1    --accept-all-licences was passed
#   stdin not a terminal    batch / SLURM / CI
#   --dry-run in $extra     nothing changes

# Sources once.
if [[ -n "${_LICENCE_AGREEMENT_SOURCED:-}" ]]; then return 0 2>/dev/null || true; fi
_LICENCE_AGREEMENT_SOURCED=1

# _pipeline_licence_write_record <source> <use_category> <detail>
# Appends a ledger row and writes the full-text agreement record to logs/licensing/
# and the depot. <detail> says how acceptance was given.
_pipeline_licence_write_record() {
    local _source="${1:-unknown}" _use_cat="${2:-academic}" _detail="${3:-${1:-unknown}}"
    local _ts _ts_compact _user _ip _pipeline_ver
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    _ts_compact="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
    _user=$(id -un 2>/dev/null || echo "${PIPELINE_USER:-${USER:-unknown}}")
    _ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$_ip" ]] && _ip="unavailable"
    _pipeline_ver=$(git -C "${REPO_ROOT:-$(pwd)}" rev-parse --short HEAD 2>/dev/null || echo unknown)

    local _ledger="${LICENCE_ACCEPTANCE_LEDGER:-${LOG_ROOT:-${LOG_DIR:-/tmp}}/licence-acceptances.tsv}"
    mkdir -p "$(dirname "$_ledger")" 2>/dev/null || true
    printf '%s\tpipeline-agreement\t%s\tuse=%s redistribute=no\tuser=%s\tpipeline=%s\n' \
        "$_ts" "$_source" "$_use_cat" "$_user" "$_pipeline_ver" >> "$_ledger" 2>/dev/null || true

    local _depot_file="${LICENCE_SHARED_LOG_DIR:+${LICENCE_SHARED_LOG_DIR%/}/${_user}-pipeline-agreement-${_ts_compact}.txt}"
    local _local_file="${LOG_ROOT:-${LOG_DIR:-logs}}/licensing/${_user}-pipeline-agreement-${_ts_compact}.txt"
    if [[ -n "$_depot_file" ]]; then mkdir -p "$(dirname "$_depot_file")" 2>/dev/null || true; fi
    mkdir -p "$(dirname "$_local_file")" 2>/dev/null || true
    {
        printf '================================================================\n'
        printf 'margie — Prokaryotic Genome Annotation Pipeline\n'
        printf 'Pipeline Licence Acceptance Record\n'
        printf '================================================================\n'
        printf '\n'
        printf '%s accepted the following pipeline licence terms\n' "$_user"
        printf 'via %s.\n' "$_detail"
        printf '\n'
        printf 'Date/Time (UTC):   %s\n' "$_ts"
        printf 'Pipeline Version:  %s\n' "$_pipeline_ver"
        printf 'IP Address:        %s\n' "$_ip"
        printf 'Declared Use:      %s (non-commercial / educational and research)\n' "$_use_cat"
        printf 'Redistribution:    no\n'
        printf '\n'
        printf '================================================================\n'
        printf 'The licence terms stated:\n'
        printf '================================================================\n'
        printf '\n'
        printf '--- FREELY REDISTRIBUTABLE TOOLS ---\n'
        printf '\n'
        printf 'Tool              Version    Licence          URL\n'
        printf '──────────────────────────────────────────────────────────────\n'
        printf 'rasttk            1.040      GPL-3.0+         https://github.com/BV-BRC/BV-BRC-CLI\n'
        printf 'kegg / KofamScan  1.3.0      MIT              https://www.genome.jp/tools/kofamkoala/\n'
        printf 'cog / BLAST+      2.16.0     Public Domain    https://ftp.ncbi.nlm.nih.gov/blast/\n'
        printf 'pfam / HMMER      3.4        BSD-3-Clause     http://hmmer.org/\n'
        printf 'pgap / HMMER HMMs hmm-15.0  U.S. Pub. Dom.   https://ftp.ncbi.nlm.nih.gov/hmm/\n'
        printf 'tigrfam           15.0       CC-BY-SA 4.0     https://ftp.ncbi.nlm.nih.gov/hmm/TIGRFAMs/\n'
        printf 'dbcan             5.1.2      GPL-3.0+         https://github.com/linnabrown/run_dbcan\n'
        printf 'eggnog-mapper     2.1.12     AGPL-3.0+        https://github.com/eggnogdb/eggnog-mapper\n'
        printf 'uniprot / DIAMOND 2.1.9      GPL-3.0+         https://github.com/bbuchfink/diamond\n'
        printf 'interpro          5.x        Apache-2.0 core  https://github.com/ebi-pf-team/interproscan\n'
        printf 'geneprop          —          Apache-2.0       https://github.com/ebi-pf-team/genome-properties\n'
        printf 'psortb            1.0.2      GPL-2.0+         https://github.com/brinkmanlab/psortb_commandline_docker\n'
        printf 'tmhmm.py          1.2.1      MIT              https://pypi.org/project/tmhmm.py/\n'
        printf 'deepsig           —          GPL-3.0          https://github.com/BolognaBiocomp/deepsig\n'
        printf 'operon / UniOP    2025-05    MIT              https://github.com/hongsua/UniOP\n'
        printf 'consolidation     —          BSD-3-Clause     (first-party scripts)\n'
        printf 'labeling/scoring  —          BSD-3-Clause     (first-party scripts)\n'
        printf '\n'
        printf 'Comparative genomics tools (run once over the full collection):\n'
        printf 'EzAAI 1.2.2       MIT        freely redistributable / commercial OK\n'
        printf '                             cite: Kim et al. 2021, J Microbiol 59:476\n'
        printf 'DIAMOND 2.1.9     GPL-3.0+   freely redistributable; copyleft — derivative\n'
        printf '                             works bundling DIAMOND must also be GPL\n'
        printf 'FastANI 1.34      Apache-2.0 freely redistributable / commercial OK\n'
        printf '                             cite: Jain et al. 2018, Nat Commun 9:5114\n'
        printf 'Liftoff 1.6.3     GPL-3.0+   freely redistributable; copyleft — derivative\n'
        printf '                             works bundling Liftoff must also be GPL\n'
        printf '                             cite: Shumate & Salzberg 2021, Bioinf 37:1639\n'
        printf 'minimap2 2.28     MIT        freely redistributable / commercial OK\n'
        printf 'rank_closest.py   MIT        first-party; freely redistributable\n'
        printf '\n'
        printf 'Pre-processing tools (run once before annotation):\n'
        printf 'Prodigal 2.6.3    GPL-3.0+   freely redistributable; copyleft\n'
        printf '                             cite: Hyatt et al. 2010, BMC Bioinformatics 11:119\n'
        printf 'HMMER 3.x         BSD-3-Clause freely redistributable / commercial OK\n'
        printf 'Barrnap HMMs 0.9  GPL-3.0    freely redistributable; copyleft\n'
        printf '                             cite: Seemann T. https://github.com/tseemann/barrnap\n'
        printf 'classify_genome.py MIT       first-party; freely redistributable\n'
        printf '\n'
        printf 'Conditions accepted:\n'
        printf '  tigrfam    CC-BY-SA 4.0  — will cite in publications\n'
        printf '  uniprot    CC-BY 4.0     — will cite in publications\n'
        printf '  eggnog     AGPL-3.0+     — if exposed as a network service, source\n'
        printf '                             must be published at https://github.com/eggnogdb/eggnog-mapper\n'
        printf '  psortb     GPL-2.0+      — derivative works must also be GPL\n'
        printf '  deepsig    GPL-3.0       — derivative works must also be GPL\n'
        printf '  diamond    GPL-3.0+      — (aai) derivative works must also be GPL\n'
        printf '  liftoff    GPL-3.0+      — (synteny) derivative works must also be GPL;\n'
        printf '                             cite Shumate & Salzberg 2021, Bioinformatics 37:1639\n'
        printf '  ezaai      MIT           — will cite Kim et al. 2021, J Microbiol 59:476\n'
        printf '  fastani    Apache-2.0    — will cite Jain et al. 2018, Nat Commun 9:5114\n'
        printf '  prodigal   GPL-3.0+      — (classify) derivative works must also be GPL;\n'
        printf '                             will cite Hyatt et al. 2010, BMC Bioinformatics 11:119\n'
        printf '  barrnap    GPL-3.0       — (classify) derivative works must also be GPL;\n'
        printf '                             will cite Seemann T. https://github.com/tseemann/barrnap\n'
        printf '  ncbi-blast+  2.14  Public Domain — US Government work; no restrictions\n'
        printf '  SILVA SSU NR99 138.2  CC-BY 4.0  — will cite:\n'
        printf '                                      Quast C et al. (2013) Nucleic Acids Res 41(D1):D590-D596.\n'
        printf '                                      doi:10.1093/nar/gks1219\n'
        printf '\n'
        printf '--- RESTRICTED TOOLS (academic / non-commercial use only) ---\n'
        printf '\n'
        printf 'These tools have explicit non-commercial or no-redistribution terms.\n'
        printf 'Commercial use requires a separate paid licence from the rights holder.\n'
        printf '\n'
        printf '  merops   12.5     Academic only. Commercial use requires an EBI licence.\n'
        printf '                    terms:   https://www.ebi.ac.uk/merops/about/license.shtml\n'
        printf '                    contact: merops-helpdesk@ebi.ac.uk\n'
        printf '\n'
        printf '  phobius  101      Academic only. NOT redistributable.\n'
        printf '                    Commercial use requires a DTU licence.\n'
        printf '                    terms:   https://phobius.sbc.su.se/data.html\n'
        printf '                    contact: software@cbs.dtu.dk\n'
        printf '\n'
        printf '  tmbed    1.0.0    ProtT5 model weights: CC-BY-NC-SA 4.0 (NonCommercial).\n'
        printf '  (ProtT5)          Commercial use requires a Rostlab licence.\n'
        printf '                    terms:   https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc\n'
        printf '                    contact: rostlab@in.tum.de\n'
        printf '\n'
        printf '  tcdb     2024     Free for academic use. Commercial use requires\n'
        printf '                    written permission from the Saier Lab.\n'
        printf '                    terms:   https://www.tcdb.org\n'
        printf '                    contact: msaier@ucsd.edu\n'
        printf '\n'
        printf '  interpro  5.x     Core: Apache-2.0. ProSite and SMART member\n'
        printf '  (ProSite/         databases are restricted for commercial use.\n'
        printf '   SMART)           terms:   https://prosite.expasy.org/prosite_license.html\n'
        printf '                    contact: licensing@sib.swiss (ProSite)\n'
        printf '                             smart@embl.de (SMART)\n'
        printf '\n'
        printf 'Each restricted tool will prompt the user individually when it runs.\n'
        printf '\n'
        printf '--- PIPELINE LICENCE ---\n'
        printf '\n'
        printf 'This pipeline is made available for EDUCATIONAL and RESEARCH purposes only.\n'
        printf 'Commercial use is NOT permitted without first obtaining individual written\n'
        printf 'licences from every upstream tool and database rights holder.\n'
        printf '\n'
        printf '--- CONFIRMED AGREEMENT ---\n'
        printf '\n'
        printf '  (a) I have read and understood all licence terms listed above.\n'
        printf '  (b) My intended use is educational / research (non-commercial).\n'
        printf '  (c) I will not redistribute restricted tools or binaries without\n'
        printf '      written permission from each rights holder.\n'
        printf '  (d) Restricted tools (merops, phobius, tmbed, tcdb, interpro)\n'
        printf '      will prompt me individually when they run.\n'
        printf '  (e) I will comply with all applicable laws and regulations.\n'
        printf '  (f) These licence terms apply to this version of the pipeline.\n'
        printf '      Any modifications I make are my sole responsibility. I am\n'
        printf '      responsible for ensuring continued compliance with all\n'
        printf '      applicable laws and regulations, and for updating this\n'
        printf '      agreement accordingly if I modify the pipeline.\n'
        printf '  (g) I will obtain proper permissions from all relevant original\n'
        printf '      tool developers as required.\n'
        printf '  (h) I acknowledge that this pipeline is provided "as is" with\n'
        printf '      no warranties or guarantees of any kind.\n'
        printf '\n'
        printf '================================================================\n'
        printf 'End of Licence Acceptance Record\n'
        printf '================================================================\n'
        printf '\n'
    } >> "$_local_file" 2>/dev/null || true
    if [[ -n "$_depot_file" ]]; then cp "$_local_file" "$_depot_file" 2>/dev/null || true; fi
}

# Walks the user through the licence terms and records the agreement.
pipeline_licence_agreement() {
    local extra="${1:-}"

    # ── skip conditions ──
    [[ "${MARGIE_ACCEPT_TERMS:-0}" == "1" ]] && return 0
    if [[ "${LICENCE_ACCEPT_ALL:-0}" == "1" ]]; then
        local _detail
        if [[ -n "${SLURM_JOB_ID:-}" ]]; then
            _detail="the --accept-all-licences flag submitted as part of SLURM batch job ${SLURM_JOB_ID} (job name: ${SLURM_JOB_NAME:-not set}, non-interactive)"
        else
            _detail="the --accept-all-licences flag passed interactively to setup.sh"
        fi
        _pipeline_licence_write_record "accept-all-licences" "${LICENCE_INTENDED_USE:-accept-all-licences}" "$_detail"
        export MARGIE_ACCEPT_TERMS=1
        return 0
    fi
    [[ -t 0 ]]                               || return 0
    [[ "$extra" == *--dry-run* ]]            && return 0

    # ── step 1 of 6 — header ──
    printf '\n'
    printf '  ================================================================\n'
    printf '  margie — prokaryote genome annotation pipeline\n'
    printf '  Licence Agreement — please read before proceeding\n'
    printf '  ================================================================\n'
    printf '\n'

    # ── step 2 of 6 — why licensing matters ──
    printf '  ── WHY LICENSING MATTERS ────────────────────────────────────\n'
    printf '\n'
    printf '  This pipeline integrates tools and databases developed by many\n'
    printf '  independent research groups and organisations, each of which has\n'
    printf '  invested substantial resources in their creation. Each component\n'
    printf '  is released under its own licence that defines who may use it,\n'
    printf '  for what purposes, and under what conditions.\n'
    printf '\n'
    printf '  Using a tool or database without complying with its licence is a\n'
    printf '  legal violation that can expose you, your institution, and your\n'
    printf '  collaborators to liability. Several components in this pipeline\n'
    printf '  are FREE for academic / non-commercial use but REQUIRE a paid\n'
    printf '  or written licence for commercial use. Others restrict\n'
    printf '  redistribution entirely. It is your responsibility to ensure\n'
    printf '  your use is compliant before you proceed.\n'
    printf '\n'
    printf '  All agreements you make here are recorded with:\n'
    printf '    - A timestamp and pipeline version (git commit).\n'
    printf '    - Your username and declared intended use.\n'
    printf '  A copy of this acceptance record is saved in:\n'
    printf '    logs/licensing/   (local copy, this machine)\n'
    if [[ -n "${LICENCE_SHARED_LOG_DIR:-}" ]]; then printf '    %s   (shared copy)\n' "${LICENCE_SHARED_LOG_DIR%/}/"; fi
    printf '\n'

    # ── step 3 of 6 — exact quoted licence terms: DATABASES ──
    printf '  ── DATABASES ────────────────────────────────────────────────\n'
    printf '\n'
    printf '  The following databases are downloaded and used by this pipeline.\n'
    printf '\n'
    printf '  ┌─ SILVA SSU NR99 v138.2 (16S rRNA taxonomy) ─────────────────┐\n'
    printf '  │ Licence: Creative Commons Attribution 4.0 International      │\n'
    printf '  │ (CC-BY 4.0). Quoted from https://www.arb-silva.de/:          │\n'
    printf '  │   "The SILVA databases are provided under Creative Commons   │\n'
    printf '  │    license CC BY 4.0. This means that you may copy and       │\n'
    printf '  │    redistribute the material in any medium or format and      │\n'
    printf '  │    remix, transform, and build upon the material for any      │\n'
    printf '  │    purpose, even commercially, provided you give appropriate  │\n'
    printf '  │    credit, provide a link to the license, and indicate if     │\n'
    printf '  │    changes were made."                                        │\n'
    printf '  │ Condition: cite Quast C. et al. (2013) NAR 41(D1):D590-D596  │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ UniProt / Swiss-Prot (protein homology) ───────────────────┐\n'
    printf '  │ Licence: Creative Commons Attribution 4.0 International      │\n'
    printf '  │ (CC-BY 4.0). Quoted from https://www.uniprot.org/help/license:│\n'
    printf '  │   "We have chosen to apply the Creative Commons Attribution  │\n'
    printf '  │    (CC BY 4.0) License to all copyrightable parts of our     │\n'
    printf '  │    databases. This means anyone is free to download, use,    │\n'
    printf '  │    distribute, display, and make derivative works from our   │\n'
    printf '  │    data, as long as they credit UniProt."                    │\n'
    printf '  │ Condition: cite UniProt Consortium (2023) NAR 51(D1):D523    │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ MEROPS 12.5 (peptidase DB, EMBL-EBI) ─────────────────── ⚠️ ┐\n'
    printf '  │ ACADEMIC ONLY — commercial use requires a paid licence.       │\n'
    printf '  │ Quoted from https://www.ebi.ac.uk/merops/about/license.shtml: │\n'
    printf '  │   "The MEROPS database is freely accessible for academic use. │\n'
    printf '  │    Commercial organisations should contact the MEROPS team    │\n'
    printf '  │    to obtain a licence before downloading or using the data." │\n'
    printf '  │ Contact: merops-helpdesk@ebi.ac.uk                           │\n'
    printf '  │ Condition: cite Rawlings N.D. et al. (2018) NAR 46(D1):D624  │\n'
    printf '  │ A separate per-tool prompt will appear when MEROPS runs.      │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ TCDB 2024 (transporter classification, Saier Lab UCSD) ─ ⚠️ ┐\n'
    printf '  │ ACADEMIC / NON-PROFIT ONLY — commercial use needs permission. │\n'
    printf '  │ Quoted from https://www.tcdb.org/:                            │\n'
    printf '  │   "TCDB is provided free of charge for academic and non-profit│\n'
    printf '  │    use, subject to proper citation of the database in any     │\n'
    printf '  │    resulting publication. Commercial use of the data requires │\n'
    printf '  │    prior written permission from the Saier Lab."              │\n'
    printf '  │ Contact: msaier@ucsd.edu                                      │\n'
    printf '  │ Condition: cite Saier M.H. Jr et al. (2021) NAR 49(D1):D461  │\n'
    printf '  │ A separate per-tool prompt will appear when TCDB runs.        │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ EggNOG DB 5.0 (orthology annotations) ─────────────────────┐\n'
    printf '  │ Database content: CC-BY 4.0 (free for any use with credit).  │\n'
    printf '  │ eggnog-mapper software: AGPL-3.0+ (if exposed as a network   │\n'
    printf '  │ service, source must be published). Quoted from:              │\n'
    printf '  │   "The EggNOG database content is available under the        │\n'
    printf '  │    Creative Commons Attribution 4.0 International license."  │\n'
    printf '  │ Condition: cite Cantalapiedra C.P. et al. (2021) MBE 38:5825 │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ TIGRFAMs 15.0 (NCBI HMMs) ─────────────────────────────────┐\n'
    printf '  │ Licence: Creative Commons Attribution-ShareAlike 4.0          │\n'
    printf '  │ International (CC-BY-SA 4.0). Free for any use.               │\n'
    printf '  │ Condition: cite Haft D.H. et al. (2003) NAR 31(1):371-373     │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ KEGG / KofamScan 1.3.0 (functional annotation HMMs) ────────┐\n'
    printf '  │ KofamScan software: MIT licence (freely redistributable).     │\n'
    printf '  │ KEGG Orthology (KO) HMMs: freely downloadable for research.   │\n'
    printf '  │ Note: the full KEGG database for commercial use requires a    │\n'
    printf '  │ paid subscription from Kanehisa Laboratories.                 │\n'
    printf '  │ Contact (commercial): kegg@kanehisa.jp                        │\n'
    printf '  │ https://www.kegg.jp/kegg/legal.html                           │\n'
    printf '  │ Condition: cite Aramaki T. et al. (2020) Bioinformatics 36:7  │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'

    # ── step 4 of 6 — exact quoted licence terms: TOOLS ──
    printf '  ── TOOLS ────────────────────────────────────────────────────\n'
    printf '\n'
    printf '  ┌─ Prodigal 2.6.3 (gene prediction) ─────────────────────────┐\n'
    printf '  │ Licence: GNU General Public License v3.0 or later (GPL-3.0+)│\n'
    printf '  │ Quoted from the Prodigal LICENSE:                            │\n'
    printf '  │   "This program is free software: you can redistribute it   │\n'
    printf '  │    and/or modify it under the terms of the GNU General       │\n'
    printf '  │    Public License as published by the Free Software          │\n'
    printf '  │    Foundation, either version 3 of the License, or (at your │\n'
    printf '  │    option) any later version."                               │\n'
    printf '  │ Condition: cite Hyatt D. et al. (2010) BMC Bioinf 11:119    │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ barrnap 0.9 (rRNA prediction) ─────────────────────────────┐\n'
    printf '  │ Licence: GNU General Public License (GPL-3.0).               │\n'
    printf '  │ Quoted from the barrnap README:                              │\n'
    printf '  │   "This software is distributed under the GNU General Public │\n'
    printf '  │    Licence; see the accompanying file LICENSE."              │\n'
    printf '  │ Source: https://github.com/tseemann/barrnap                  │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ DIAMOND 2.1.9 (sequence alignment) ─────────────────────────┐\n'
    printf '  │ Licence: GNU General Public License v3.0 or later (GPL-3.0+) │\n'
    printf '  │ Quoted from the DIAMOND LICENSE:                              │\n'
    printf '  │   "This program is free software: you can redistribute it    │\n'
    printf '  │    and/or modify it under the terms of the GNU General Public │\n'
    printf '  │    License as published by the Free Software Foundation."     │\n'
    printf '  │ Source: https://github.com/bbuchfink/diamond                  │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ HMMER 3.4 (profile HMM searches) ──────────────────────────┐\n'
    printf '  │ Licence: BSD 3-Clause (free for academic and commercial use). │\n'
    printf '  │ Source: http://hmmer.org/                                     │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ InterProScan 5.x (domain annotation) ── core: Apache-2.0 ─┐\n'
    printf '  │ Core engine: Apache License 2.0.                             │\n'
    printf '  │ Quoted from the InterProScan LICENSE:                        │\n'
    printf '  │   "Licensed under the Apache License, Version 2.0 (the      │\n'
    printf '  │    License); you may not use this file except in compliance  │\n'
    printf '  │    with the License. You may obtain a copy of the License    │\n'
    printf '  │    at http://www.apache.org/licenses/LICENSE-2.0"            │\n'
    printf '  │                                                               │\n'
    printf '  │ ⚠️  ProSite member database (SIB, bundled in InterProScan):    │\n'
    printf '  │   Quoted from https://prosite.expasy.org/prosite_license.html:│\n'
    printf '  │   "The use of the PROSITE database is free of charge for     │\n'
    printf '  │    academic and non-commercial use. Commercial users must     │\n'
    printf '  │    obtain a licence from the SIB."                           │\n'
    printf '  │   Contact: licensing@sib.swiss                               │\n'
    printf '  │                                                               │\n'
    printf '  │ ⚠️  SMART member database (EMBL, bundled in InterProScan):     │\n'
    printf '  │   Quoted from http://smart.embl.de/:                         │\n'
    printf '  │   "SMART is freely accessible to academic users; commercial  │\n'
    printf '  │    users require a separate licence from EMBL."              │\n'
    printf '  │   Contact: smart@embl.de                                     │\n'
    printf '  │ A separate per-tool prompt will appear when InterProScan runs.│\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ Phobius 1.01 (signal peptide + TM topology) ──────────── ⚠️ ┐\n'
    printf '  │ ACADEMIC ONLY — no redistribution — commercial licence needed.│\n'
    printf '  │ Quoted from https://phobius.sbc.su.se/data.html:             │\n'
    printf '  │   "Phobius is available free of charge to academic users.    │\n'
    printf '  │    Commercial users must contact us for a licence.           │\n'
    printf '  │    You are NOT allowed to redistribute the program or to host│\n'
    printf '  │    it on another server. End users must download the software│\n'
    printf '  │    themselves from this page."                               │\n'
    printf '  │ Contact (commercial): lukas.kall@scilifelab.se               │\n'
    printf '  │ Condition: cite Kall L. et al. (2007) NAR 35:W429-W432       │\n'
    printf '  │ A separate per-tool prompt will appear when Phobius runs.     │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ TMbed 1.0.0 + ProtT5-XL-U50 weights (TM prediction) ──── ⚠️ ┐\n'
    printf '  │ TMbed software: Apache License 2.0 (commercial OK).          │\n'
    printf '  │ Quoted from https://github.com/BernhoferM/TMbed/LICENSE:     │\n'
    printf '  │   "Licensed under the Apache License, Version 2.0..."        │\n'
    printf '  │                                                               │\n'
    printf '  │ ⚠️  ProtT5-XL-U50 model weights: CC-BY-NC-SA 4.0              │\n'
    printf '  │ (NON-COMMERCIAL). Quoted from the Hugging Face model card at  │\n'
    printf '  │ https://huggingface.co/Rostlab/prot_t5_xl_half_uniref50-enc: │\n'
    printf '  │   "ProtTrans is licensed under the Academic Free License     │\n'
    printf '  │    v3.0 for models and the Creative Commons Attribution-     │\n'
    printf '  │    NonCommercial-ShareAlike 4.0 International License        │\n'
    printf '  │    (CC-BY-NC-SA-4.0) for the embeddings and any derived work.│\n'
    printf '  │    Commercial use is not permitted without explicit written   │\n'
    printf '  │    permission from the Rost Lab."                            │\n'
    printf '  │ Contact (commercial): rostlab@in.tum.de                      │\n'
    printf '  │ Condition: cite Bernhofer & Rost (2022) BMC Bioinf 23:326   │\n'
    printf '  │ A separate per-tool prompt will appear when TMbed runs.       │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  ┌─ RASttk (genome annotation, BV-BRC) ─────────────────────────┐\n'
    printf '  │ Licence: MIT (free for any use, including commercial).         │\n'
    printf '  │ Source: https://github.com/BV-BRC/BV-BRC-CLI                  │\n'
    printf '  └──────────────────────────────────────────────────────────────┘\n'
    printf '\n'
    printf '  Additional tools (freely redistributable, academic and commercial OK):\n'
    printf '  Tool              Version  Licence         Source\n'
    printf '  ──────────────────────────────────────────────────────────────\n'
    printf '  cog / BLAST+      2.16.0   Public Domain   https://ftp.ncbi.nlm.nih.gov/blast/\n'
    printf '  pfam / HMMER      3.4      BSD-3-Clause    http://hmmer.org/\n'
    printf '  pgap / HMMER HMMs hmm-15.0 U.S.Pub.Dom.   https://ftp.ncbi.nlm.nih.gov/hmm/\n'
    printf '  dbcan             5.1.2    GPL-3.0+        https://github.com/linnabrown/run_dbcan\n'
    printf '  psortb            1.0.2    GPL-2.0+        https://github.com/brinkmanlab/psortb_commandline_docker\n'
    printf '  tmhmm.py          1.2.1    MIT             https://pypi.org/project/tmhmm.py/\n'
    printf '  deepsig           —        GPL-3.0         https://github.com/BolognaBiocomp/deepsig\n'
    printf '  operon / UniOP    2025-05  MIT             https://github.com/hongsua/UniOP\n'
    printf '  geneprop          —        Apache-2.0      https://github.com/ebi-pf-team/genome-properties\n'
    printf '  EzAAI             1.2.2    MIT             https://github.com/endixk/ezaai\n'
    printf '  FastANI           1.34     Apache-2.0      https://github.com/ParBLiSS/FastANI\n'
    printf '  Liftoff           1.6.3    GPL-3.0+        https://github.com/agshumate/Liftoff\n'
    printf '  minimap2          2.28     MIT             https://github.com/lh3/minimap2\n'
    printf '\n'
    printf '  ── YOUR DECLARATION ─────────────────────────────────────────\n'
    printf '\n'
    printf '  Is your use of this pipeline for educational or research\n'
    printf '  purposes only (non-commercial)? [yes/no] '
    local _use_cat
    IFS= read -r _use_cat
    case "$_use_cat" in
        y|Y|yes|YES) export MARGIE_USE_CATEGORY="academic" ;;
        *)
            printf '\n'
            printf '  Commercial use requires written licences from all upstream\n'
            printf '  rights holders listed above. Obtain those first, then\n'
            printf '  re-run this pipeline.\n'
            printf '\n'
            err "commercial use declared — obtain upstream licences first and re-run"
            return 1
            ;;
    esac

    printf '\n'
    printf '  Will you redistribute this pipeline, its container images, or\n'
    printf '  outputs as part of a product or service? [yes/no] '
    local _redist
    IFS= read -r _redist
    case "$_redist" in
        y|Y|yes|YES)
            printf '\n'
            printf '  Redistribution includes components that are NOT redistributable\n'
            printf '  without prior written permission:\n'
            printf '    phobius  — DTU / SBC academic licence\n'
            printf '    merops   — EBI academic licence\n'
            printf '    tmbed    — ProtT5 CC-BY-NC-SA 4.0\n'
            printf '\n'
            printf '  Obtain written permission from each rights holder first.\n'
            printf '\n'
            err "redistribution declared — obtain upstream permissions first and re-run"
            return 1
            ;;
    esac
    export MARGIE_REDISTRIBUTE="no"

    # ── step 6 of 6 — final agreement + record ──
    printf '\n'
    printf '  ── FINAL AGREEMENT ──────────────────────────────────────────\n'
    printf '\n'
    printf '  By confirming below, you agree to ALL of the following:\n'
    printf '\n'
    printf '    (a) You have read and understood the licence terms above.\n'
    printf '    (b) Your intended use is educational / research (non-commercial).\n'
    printf '    (c) You will not redistribute restricted tools or binaries\n'
    printf '        without written permission from each rights holder.\n'
    printf '    (d) Restricted tools (merops, phobius, tmbed, tcdb, interpro)\n'
    printf '        will prompt you individually when they run.\n'
    printf '    (e) You will comply with all applicable laws and regulations.\n'
    printf '    (f) These licence terms apply to this version of the pipeline.\n'
    printf '        Any modifications you make are your sole responsibility.\n'
    printf '        You are responsible for ensuring continued compliance with\n'
    printf '        all applicable laws and regulations, and for updating this\n'
    printf '        agreement accordingly if you modify the pipeline.\n'
    printf '    (g) You will obtain proper permissions from all relevant\n'
    printf '        original tool developers as required.\n'
    printf '    (h) You acknowledge that this pipeline is provided "as is"\n'
    printf '        with no warranties or guarantees of any kind.\n'
    printf '\n'
    printf '  Your agreement is recorded with:\n'
    printf '    - A timestamp and pipeline version (git commit hash)\n'
    printf '    - Your username and declared intended use\n'
    printf '  A copy of this acceptance record will be saved in:\n'
    printf '    logs/licensing/   (local copy, this machine)\n'
    if [[ -n "${LICENCE_SHARED_LOG_DIR:-}" ]]; then printf '    %s   (shared copy)\n' "${LICENCE_SHARED_LOG_DIR%/}/"; fi
    printf '\n'
    printf '  Do you agree to the statement above? [yes/no] '
    local _final
    IFS= read -r _final
    case "$_final" in
        y|Y|yes|YES) ;;
        *)
            printf '\n'
            err "agreement declined — aborting"
            return 1
            ;;
    esac

    _pipeline_licence_write_record "interactive" "$MARGIE_USE_CATEGORY" \
        "interactive confirmation at the terminal prompt — ${_user:-$(id -un)} was presented with the full pipeline licence agreement and entered 'y' at the final confirmation prompt"
    export MARGIE_ACCEPT_TERMS=1
    ok "licence agreement recorded (use=$MARGIE_USE_CATEGORY)"
    printf '\n'
}
