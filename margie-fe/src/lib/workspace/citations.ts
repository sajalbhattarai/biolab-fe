/** Citations for the tools a genome's results came from (from the pipeline README). */

export const MARGIE_CITATION = 'Bhattarai S et al. MARGIE: Mostly Automated Rapid Genome Inference Environment. (manuscript in preparation)';

export const CITATIONS: Record<string, { name: string; cite: string }> = {
	prodigal: { name: 'Prodigal', cite: 'Hyatt D, Chen G-L, LoCascio PF, Land ML, Larimer FW, Hauser LJ (2010). Prodigal: prokaryotic gene recognition and translation initiation site identification. BMC Bioinformatics 11:119.' },
	operon: { name: 'UniOP', cite: 'Hong S (2023). UniOP: predicting operons using intergenic distance. GitHub repository.' },
	gtdbtk: { name: 'GTDB-Tk', cite: 'Parks DH et al. (2022). GTDB: an ongoing census of bacterial and archaeal diversity through a phylogenetically consistent, rank normalised and complete genome-based taxonomy. Nucleic Acids Research 50:D785–D794.' },
	rasttk: { name: 'RASTtk', cite: 'Brettin T et al. (2015). RASTtk: a modular and extensible implementation of the RAST algorithm for building custom annotation pipelines and annotating batches of genomes. Scientific Reports 5:8365.' },
	psortb: { name: 'PSORTb', cite: 'Yu NY et al. (2010). PSORTb 3.0: improved protein subcellular localization prediction with refined localization subcategories and predictive capabilities for all prokaryotes. Bioinformatics 26:1608–1615.' },
	deepsig: { name: 'DeepSig', cite: 'Savojardo C et al. (2018). DeepSig: deep learning improves signal peptide detection in proteins. Bioinformatics 34:1690–1696.' },
	tmbed: { name: 'TMbed', cite: 'Bernhofer M et al. (2022). TMbed: transmembrane proteins predicted through language model embeddings. BMC Bioinformatics 23:326.' },
	phobius: { name: 'Phobius', cite: 'Käll L et al. (2004). A combined transmembrane topology and signal peptide prediction method. Journal of Molecular Biology 338:1027–1036.' },
	dbcan: { name: 'dbCAN', cite: 'Yin Y et al. (2012). dbCAN: a web resource for automated carbohydrate-active enzyme annotation. Nucleic Acids Research 40:W445–W451.' },
	eggnog: { name: 'eggNOG-mapper', cite: 'Cantalapiedra CP et al. (2021). eggNOG-mapper v2: functional annotation, orthology assignments, and domain prediction at the metagenomic scale. Molecular Biology and Evolution 38:5825–5829.' },
	interpro: { name: 'InterProScan', cite: 'Jones P et al. (2014). InterProScan 5: genome-scale protein function classification. Bioinformatics 30:1236–1240.' },
	pfam: { name: 'Pfam', cite: 'Mistry J et al. (2021). Pfam: the protein families database in 2021. Nucleic Acids Research 49:D412–D419.' },
	tigrfam: { name: 'TIGRFAMs', cite: 'Haft DH et al. (2003). TIGRFAMs and Genome Properties: tools for the assignment of molecular function and biological process in prokaryotic genomes. Nucleic Acids Research 31:371–373.' },
	merops: { name: 'MEROPS', cite: 'Rawlings ND et al. (2018). The MEROPS database of proteolytic enzymes, their substrates and inhibitors in 2017. Nucleic Acids Research 46:D624–D632.' },
	tcdb: { name: 'TCDB', cite: 'Saier MH et al. (2021). The Transporter Classification Database (TCDB): 2021 update. Nucleic Acids Research 49:D461–D467.' },
	cog: { name: 'COG', cite: 'Galperin MY et al. (2021). COG database update: focus on microbial diversity, model organisms, and widespread pathogens. Nucleic Acids Research 49:D274–D281.' },
	uniprot: { name: 'UniProt', cite: 'The UniProt Consortium (2023). UniProt: the universal protein knowledgebase in 2023. Nucleic Acids Research 51:D523–D531.' },
	geneprop: { name: 'Genome Properties', cite: 'Richardson LJ et al. (2019). Genome properties in 2019: a new companion database to InterPro for the inference of complete functional attributes. Nucleic Acids Research 47:D564–D572.' },
	kegg: { name: 'KEGG', cite: 'Kanehisa M et al. (2023). KEGG for taxonomy-based analysis of pathways and genomes. Nucleic Acids Research 51:D587–D592.' },
	pgap: { name: 'PGAP', cite: 'Tatusova T et al. (2016). NCBI prokaryotic genome annotation pipeline. Nucleic Acids Research 44:6614–6624.' }
};
