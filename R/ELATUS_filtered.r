#' ELATUS workflow
#' This workflow loads the Kallisto and CellRanger raw count matrices, performs emptydrops, then doublet removal, a quality control filtering. Next it gets the highly expressed lncRNAs only detected by Kallisto and the ratio of their expression between Kallisto/CellRanger and finally, after normalization and clustering it calculates the Specificity Index of each of them. The last step is generating the list of biologically relevant lncRNAs. In addition it identifies highly-expressed lncRNAs exclusively detected by Kallisto whose functionality has been proven by external biobliography (CRISPR screenings...) and those highly-expressed lncRNAs robustly detected by both Cell Ranger and Kallisto.
#' @param organism Human or Mouse dataset (for the example "Mouse") 
#' @param kallisto_sce Kallisto SingleCellExperiment object
#' @param cellRanger_path CellRanger SingleCellExperiment object
#' @param threshold_minumun_gene_counts Select genes with more than this total counts  (For the paper = 250 counts)
#' @param threshold_cells_detected Select genes present in at least a number of cells higher than this threshold (For the paper = 25)
#' @param dimred_clustering dimensionality reduction (For the example "PCA")
#' @param k_neighbors the number of nearest neighbors used to construct the graph. Choose a smaller k to more but smaller clusters as lncRNAs tend to be expressed in small subpopulations. (in this example, k=5)
#' @param ratio_threshold Threshold to remove lncRNAs whose ratio of expression between Kallisto and CellRanger is smaller than this defined threshold (For the paper = 40)
#' @param CR_threshold Threshold to remove lncRNAs that have a CellRanger expression higher than this defined threshold (For the paper = 10)
#' @param SI_threshold Threshold to remove lncRNAs whose SI is smaller than this defined threshold (For the paper = 0.15)
#' @return A list with most biologically relevant lncRNAs

#' @export
ELATUS_filtered <- function(organism, kallisto_sce, cellRanger_sce, threshold_minumun_gene_counts, threshold_cells_detected, dimred_clustering, k_neighbors, ratio_threshold, CR_threshold, SI_threshold)
{
    if (organism == "Human")
    {
        gencode_path <- system.file("extdata", "hg38_v37.rds", package = "ELATUS")
    } 
    if (organism == "Mouse")
    {
        gencode_path <- system.file("extdata", "mm10_vM27.rds", package = "ELATUS")
    }
    crispr_data <- readRDS(system.file("extdata", "hits_info_Liu_science_2015_ensids.rds", package = "ELATUS"))
    gtf <- readRDS(gencode_path)
    gtf$gene_id <- gsub("_","-",gtf$gene_id)
    lncrna_ens_ids <- unique(c(gtf$gene_id[grep("lncRNA",gtf$gene_type)]))
    protein_coding_ens_ids <- unique(c(gtf$gene_id[gtf$gene_type=="protein_coding"]))
    lncrna_names <- unique(gtf$gene_name[gtf$gene_id %in% lncrna_ens_ids])
    protein_coding_names <-  unique(gtf$gene_name[gtf$gene_id %in% protein_coding_ens_ids])

    # Now get the highly expressed lncRNAs only detected by Kallisto and the ratio of their expression between Kallisto/CellRanger. Also get the highly-expressedcommonly detected by Cell Ranger and Kallisto
    # uniquifyFeatures
    gene_name <- gtf$gene_name[match(rownames(kallisto_filt_sce),gtf$gene_id)]
    rownames(kallisto_filt_sce) <- scuttle::uniquifyFeatureNames(rownames(kallisto_filt_sce), gene_name)
    gene_name <- gtf$gene_name[match(rownames(cellRanger_filt_sce),gtf$gene_id)]
    rownames(cellRanger_filt_sce) <- scuttle::uniquifyFeatureNames(rownames(cellRanger_filt_sce), gene_name)

    # We considered highly expressed lncRNAs as those with at least 250 counts in at least 25 cells
    top_genes(kallisto_filt_sce,threshold_minumun_gene_counts,threshold_cells_detected)
    candidate_lncRNAs_exclusive <- get_candidates(kallisto_filt_sce, cellRanger_filt_sce , threshold_minumun_gene_counts = threshold_minumun_gene_counts, threshold_cells_detected = threshold_cells_detected,lncrna_names = lncrna_names,gtf=gtf)
    candidate_lncRNAs_common <- get_candidates(kallisto_filt_sce, cellRanger_filt_sce, threshold_minumun_gene_counts = threshold_minumun_gene_counts, threshold_cells_detected = threshold_cells_detected,lncrna_names = lncrna_names,gtf=gtf, exclusive = F)

    # clustering
    set.seed(100100100)
    kallisto_filt_sce <- scater::runPCA(kallisto_filt_sce) 
    g <- scran::buildSNNGraph(kallisto_filt_sce, use.dimred = dimred_clustering, k = k_neighbors ) # k is the number of nearest neighbors used to construct the graph. Choose a smaller k to more but smaller clusters as lncRNAs tend to be expressed in small subpopulations. (in this example, k=5). dimred_clustering is the dimensionality reduction (PCA here, but could be the corrected space after integrating samples)
    clust <- igraph::cluster_louvain(g)$membership
    print(table(clust))
    kallisto_filt_sce$louvain_clusters <- factor(clust)

    # Calculate the Specificity Index for each gene
    SI <- SI(kallisto_filt_sce,group_by="louvain_clusters", average_by="mean")
    cell_type_specific_score <- SI[["cell_type_specificity_score"]]
    counts_cell_specificity_index <- SI[["counts_cell_specificity_index"]]
    candidate_lncRNAs_exclusive$SI <- cell_type_specific_score[rownames(candidate_lncRNAs_exclusive)]
    candidate_lncRNAs_common$SI <- cell_type_specific_score[rownames(candidate_lncRNAs_common)]
    # To know in which cluster the SI is the highest 
    candidate_lncRNAs_exclusive$cell_type_SI <- colnames(counts_cell_specificity_index[rownames(candidate_lncRNAs_exclusive),])[apply(counts_cell_specificity_index[rownames(candidate_lncRNAs_exclusive),],1,which.max)]
    candidate_lncRNAs_exclusive <- crispr_info(crispr_data, candidate_lncRNAs_exclusive)
    candidate_lncRNAs_common$cell_type_SI <- candidate_lncRNAs_common$cell_type_SI <- colnames(counts_cell_specificity_index[rownames(candidate_lncRNAs_common),])[apply(counts_cell_specificity_index[rownames(candidate_lncRNAs_common),],1,which.max)]

    # Get the biologically relevant lncRNAs from these candidates (In the paper we used the following parameters: ratio_threshold = 40, CR_threshold = 10, SI_threshold = 0.15)
    exclusive_lncRNAs_CRISPRi <- candidate_lncRNAs_exclusive[candidate_lncRNAs_exclusive$crispr_intersection == T,]
    exclusive_biologically_relevant_lncRNAs <- biologically_relevant_lncRNAs(candidate_lncRNAs_exclusive, ratio_threshold,CR_threshold,SI_threshold)
    candidate_lncRNAs_common$crispr_intersection = "NA"
    if (nrow(exclusive_lncRNAs_CRISPRi)>0)
    {
        exclusive_lncRNAs_CRISPRi$category = "Exclusive_lncRNA_CRISPRi"
    }
    exclusive_biologically_relevant_lncRNAs$category = "Exclusive_lncRNA"
    candidate_lncRNAs_common$category = "Common_lncRNA"

    biologically_relevant_lncRNAs <- rbind(exclusive_biologically_relevant_lncRNAs, candidate_lncRNAs_common,exclusive_lncRNAs_CRISPRi)
    biologically_relevant_lncRNAs
}