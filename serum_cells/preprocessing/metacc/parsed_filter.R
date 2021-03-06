#############################################
## Third script to parse methylation data ##
#############################################

# This script performs the last and optional processing of the methylation data:
# - Filter sites by variance
# - Imputation: right now we only have implemented cell mean or site mean, but we should include more advanced methods

# Input:
# - dataframe object as generated by preproc_met2.R

# Output:
# - dataframe object with all annotations
# - (imputed) matrices for each annotation with dimensionality (ncells,nsites)

# Load libraries
suppressMessages(library(argparse))
suppressMessages(library(stringr))
suppressMessages(library(dplyr))
suppressMessages(library(tidyr))


######################
## Define functions ##
######################

impute <- function(d, margin) {
  if (margin == 1)
    means <- rowMeans(d, na.rm=T)
  else if (margin == 2)
    means <- colMeans(d, na.rm=T)
  else
    stop("Margin has to be either 1 (rows) or 2 (cols)")
  
  if (any(is.na(means))) {
    stop('Insufficient data for mean imputation!')
  }
  
  for (i in 1:length(means)) {
    if (margin == 1)
      d[i,is.na(d[i,])] <- means[i]
    else if (margin == 2)
      d[is.na(d[,i]), i] <- means[i]
  }
  return (d)
}

fnlist <- function(x, fil) { 
  if (file.exists(fil)) file.remove(fil)
  nams=names(x) 
  for (i in seq_along(x))
    cat(nams[i], "\t",  x[[i]], "\n",  file=fil, append=TRUE) 
}

####################
## Define options ##
####################

# Define input expression files
if (grepl("[k|K]vothe",Sys.info()['nodename'])) {
  # data.input <- str_c(datadir,'/met_data.rds')
  # datadir <- ""
} else {
  data.input <- "/hps/nobackup/stegle/users/ricard/NOMe/met/parsed/allele_inspecific/filt/met_data.rds"
}

if (!interactive()) {
  # Initialize argument parser
  p <- ArgumentParser(description='')
  # Define the fraction of sites to keep based on variance (1.0 to keep all sites)
  p$add_argument('-f','--frac_filt_var', nargs="+", default=1.0, type="double",help='A vector with the number of sites to keep (sorted by variance)')
  # Output directory
  p$add_argument('-o', '--outdir', type="character", required=TRUE,help='Output directory')
  # Define the genomic annotations to be processed 
  p$add_argument('-a','--annotations', nargs="+", type="character", required=TRUE, help="Annotations (separated by space")
  # Impute missing observations (0=not impute, 1=site-wise, 2=cell-wise)
  p$add_argument("-i", "--impute", type="integer", default=0, help="Axis to impute missing observations")
  # Read arguments
  args <- p$parse_args(commandArgs(TRUE))
} else {
  # Arguments (if run from RStudio)
  args <- list()
  args$frac_filt_var <- 0.6
  args$annotations <- "all"
  args$outdir <- "/tmp/test"
  args$impute <- 1
}

# Create output directory
dir.create(args$outdir,recursive=TRUE,showWarnings=FALSE)

###################
## Load datasets ##
###################

cat("\nLoading data...\n")

# Data
data <- readRDS(data.input)
if (args$annotations[1] == "all") 
  args$annotations <- unique(as.character(data$name))
for (anno in args$annotations)
  if (!anno %in% unique(as.character(data$name))) stop(sprintf("Annotation %s not present in the dataset",anno))
data <- data %>% filter(name %in% args$annotations)


###############
## Filtering ##
###############

cat("\nFiltering data...\n")

data_filt <- list()
for (anno in args$annotations) {
  cat(sprintf("%s...\n",anno))
  data_tmp <- filter(data, name==anno)
  
  # select the top fraction args$frac_filt_var sites with highest variance
  nids <- length(unique(data_tmp$id))
  idfilt <- data_tmp %>% group_by(id) %>% summarise(var=var(rate, na.rm=T)) %>% ungroup %>% arrange(desc(var)) %>% .$id
  idfilt <- head(idfilt, n=round(args$frac_filt_var*nids))
  data_filt[[anno]] <- data_tmp %>% filter(id %in% idfilt) %>% droplevels
  cat(sprintf("- after filtering by variance: %d/%d \n", length(idfilt), nids))
}

###################
## Create matrix ##
###################

cat("\nCreating data matrices...\n")

m <- list()
for (anno in args$annotations) {
  m[[anno]] <- data_filt[[anno]] %>% dplyr::select(id,sample,rate) %>% spread(sample,rate) %>% tibble::remove_rownames() %>% as.data.frame() %>% tibble::column_to_rownames("id") %>% as.matrix
  cat(sprintf("\nMethylation matrix for %s has dim (%d,%d) \n", anno, nrow(m[[anno]]), ncol(m[[anno]])))
  cat(sprintf("Percentage of missing values: %0.02f%% \n", 100*sum(is.na(m[[anno]]))/length(m[[anno]])))
  
  # Impute missing values
  if (args$impute != 0) {
    cat("Imputing...\n")
    m[[anno]] <- t(impute(m[[anno]],args$impute)) # Impute missing values using the feature mean
  }
}


###################
## Sanity checks ##
###################

# cat("Doing some sanity checks...\n")

# Sanity check that there are no genes with zero variance
# if (sum(sapply(m, function(x) sum(apply(x,2,var,na.rm=T) == 0))) > 0)
# warning("There are sites with zero variance in methylation rate, this might cause problems in GFA")

#################
## Store data ##
#################

cat("\nSave results...\n")
# saveRDS(Reduce(rbind,metadata_filt),sprintf("%s/meta_df.rds",args$outdir))
saveRDS(Reduce(rbind,data_filt),sprintf("%s/met_df.rds",args$outdir))
saveRDS(m,sprintf("%s/met_matrix.rds",args$outdir))
# for (anno in args$annotations)
# saveRDS(m[[anno]],sprintf("%s/m_%s_matrix.rds",args$outdir,anno))
fnlist(args, sprintf("%s/opts.txt",args$outdir))

