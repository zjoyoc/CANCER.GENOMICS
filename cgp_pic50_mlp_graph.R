#cgp_pic50_mlp_graph.R
library(data.table)
library(ggplot2)
library(reshape2)

Function.NRMSE <- function(pred, actual){

  NRMSE <- sqrt(mean((pred-actual)^2)) / diff(range(actual))
  return(NRMSE)
}

########################################################################################
#LOAD FILES
all_files <- list.files(path = "CGP_FILES/CGP_RESULTS/", pattern = "combined_D_values",
                        full.names = T)
file_out  <- paste0("FIGURES/CGP.MLP/", as.character(Sys.Date()), ".pdf")

########################################################################################
#EXECUTE
all_cgp_drugs <- c("A-770041", "AMG-706", "Axitinib", "AZD-0530", "BIBW2992",
                   "BMS-536924", "Bosutinib", "Erlotinib", "FTI-277", "Imatinib", "Lapatinib",
                   "NVP-TAE684", "OSI-906", "Pazopanib", "PD-173074", "PF-02341066",
                   "PHA-665752", "PLX4720", "SB590885", "Sorafenib","Sunitinib",
                   "WH-4-023", "A-443654", "BX-795", "GDC0941", "JW-7-52-1", "Midostaurin",
                   "Rapamycin", "Temsirolimus")

main_list <- lapply(all_files, function(y)  {

                    drug_name  <- strsplit(strsplit(y, "D_values.")[[1]][2],
                                          "_cgp_pIC50")[[1]][1]
                    ccle       <- length(grep("ccle", y, value = T))

                    if ((drug_name %in% all_cgp_drugs) & (ccle==0) ){

                      print(drug_name)

                      layers     <- strsplit(strsplit(y, "cgp_pIC50.")[[1]][2],
                                            ".txt")[[1]][1]

                      drug_table <- fread(y, sep="\t")
                      max_epoch  <- max(drug_table$EPOCH)
                      drug_table <- drug_table[EPOCH == max_epoch,]

                      drug_cor   <- cor(drug_table$ACTUAL, drug_table$PREDICTED, method="pearson")
                      drug_nrmse <- Function.NRMSE(drug_table$PREDICTED, drug_table$ACTUAL)

                      drug_table <- data.table(Drug = drug_name,
                                               Layers = layers,
                                               Cor = drug_cor,
                                               NRMSE = drug_nrmse)

                    } else {
                      drug_table <- data.table()
                    }

                    return(drug_table)
  })

main_list <- do.call(rbind, main_list)

#Plot
main_list$Layers <- factor(main_list$Layers, levels = c("50.50", "100.100", "200.200", "400.400", "500.500"), ordered=T)

pdf(file_out, width=12, height=8)

print (ggplot(main_list, aes(factor(Layers), Cor, fill=Layers)) + geom_boxplot() + geom_jitter(size=0.5) +
        theme_classic() + scale_fill_brewer(palette="Set1") +
        ggtitle("Prediciton Correlation Comparisson") + xlab("MLP architecture") + ylab("Predicted/Actual correlation")
      )

print (ggplot(main_list, aes(factor(Layers), NRMSE, fill=Layers)) + geom_boxplot() + geom_jitter(size=0.5) +
        theme_classic() + scale_fill_brewer(palette="Set1") +
        ggtitle("Prediciton NRMSE Comparisson") + xlab("MLP architecture") + ylab("Predicted/Actual NRMSE")
      )

dev.off()
print("Done plotting")
