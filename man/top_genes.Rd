% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/top_genes.R
\name{top_genes}
\alias{top_genes}
\title{Select highly expressed genes from a SCE object.}
\usage{
top_genes(data, threshold_minumun_gene_counts, threshold_cells_detected)
}
\arguments{
\item{data}{SCE object}

\item{threshold_minumun_gene_counts}{Select genes with more than this total counts}

\item{threshold_cells_detected}{Select genes present in at least a number of cells higher than this threshold}
}
\value{
SCE object with highly expressed genes
}
\description{
Select highly expressed genes from a SCE object.
}
