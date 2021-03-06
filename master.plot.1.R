library(ggplot2)
library(data.table)
library(grid)
library(gridExtra)
library(survival)
library(GGally)

Function.NRMSE <- function(pred, actual){

  NRMSE <- sqrt(mean((pred-actual)^2)) / diff(range(actual))
  return(NRMSE)
}

Function.range.0.1 <- function(x){
  scale.1 <-  (x-min(x))/(max(x)-min(x))
  return(scale.1)
}

Function.classify.lived.pred <- function(x, sd.multiplier=1, effective="NEG"){

  sd.factor <- sd.multiplier
  sd.mean <- 0 #CHANGE TO ACCOUNT FOR ORIGINAL DISTRIBUTION OF PREDICTIVE TARGET VARIABLE

  above.sd <- x[x > (sd.mean + sd.factor)]
  below.sd <- x[x < (sd.mean - sd.factor)]

  if (effective=="NEG"){
    main.table <- data.table(PREDICTION=below.sd, CASE="EFFECTIVE")
    main.table <- rbind(main.table,
                        data.table(PREDICTION=above.sd, CASE="NOT_EFFECTIVE"))
  } else {
    main.table <- data.table(PREDICTION=above.sd, CASE="EFFECTIVE")
    main.table <- rbind(main.table,
                        data.table(PREDICTION=below.sd, CASE="NOT_EFFECTIVE"))
  }

  #Return
  return (main.table)
}

args<-commandArgs(trailingOnly=T)
if (length(args)>1){
  target.name <- paste0(args[1:length(args)], collapse="_")
} else {
  target.name <- args[1]
}

# x <- read.csv("/Users/jzamalloa/Documents/Rotation/PIPELINES/METABOLIC.DRIVERS/TABLES/DRUG_THEANO_PRED/MLP/REGRESSION/TESTING/TRYING.FIGURES/HOO_D.txt",
#           header=T, sep="\t")
# x <- data.table(x)
# x <- x[1:(nrow(x)-1),]
# VALID.LOSS <- x[nrow(x),]$VALID
#
# x <- melt(x,id.vars = "EPOCH")
#
# file.name <- paste0("/Users/jzamalloa/Documents/Rotation/PIPELINES/METABOLIC.DRIVERS/TABLES/DRUG_THEANO_PRED/MLP/REGRESSION/TESTING/TRYING.FIGURES/",
#                     "LOG.OUTPUT/",target.name, ".pdf")
# pdf(file.name, width=12, height=8)
# ggplot(x, aes(EPOCH, value, colour=variable)) + geom_line() + theme_bw() + scale_fill_brewer(palette="Set1") +
#       ggtitle(paste0("VALID LOSS: ", VALID.LOSS))
# dev.off()

TABLES <- "/home/zamalloa/Documents/FOLDER/TABLES/TCGA.TRAINING/"#For Lab
TABLES <- "/tigress/zamalloa/TABLES/TCGA.TRAINING/" #For tigress
RESULTS <- "/home/zamalloa/Documents/FOLDER/RESULTS/TCGA.TRAINING/" #For Lab
RESULTS <- "/tigress/zamalloa/RESULTS/TCGA.TRAINING/" #For tigress
FIGURES <- "/home/zamalloa/Documents/FOLDER/FIGURES/TCGA.TRAINING/" #For Lab
FIGURES <- "/tigress/zamalloa/FIGURES/TCGA.TRAINING/" #For tigress

x <- read.csv(paste0(RESULTS,"combined_D.txt"),
          header=T, sep="\t")
x <- data.table(x)
x <- x[1:(nrow(x)-1),]
#setnames(x, c("EPOCH", "TRAIN", "VALID.ERROR", "VALID.COR"))

TRAIN <- x[nrow(x),]$TRAIN
VALID.LOSS <- min(x$VALID.ERROR[x$VALID.ERROR!=Inf])
TEST.LOSS <- x[nrow(x),]$TEST.COR

x <- melt(x,id.vars = "EPOCH")

file.name <- paste0(FIGURES,
                    target.name, ".pdf")
pdf(file.name, width=16, height=12)

grid.arrange(
  ggplot(x[variable=="TRAIN",], aes(EPOCH, value, colour=variable)) + geom_line() + theme_bw() + scale_fill_brewer(palette="Set1") +
        ggtitle(paste0("TRAIN LOSS: ", TRAIN)),
  ggplot(x[variable=="VALID.ERROR",], aes(EPOCH, value, colour=variable)) + geom_line() + theme_bw() + scale_fill_brewer(palette="Set1") +
        ggtitle(paste0("VALID LOSS: ", VALID.LOSS)),
  ggplot(x[variable=="TEST.COR",], aes(EPOCH, value, colour=variable)) + geom_line() + theme_bw() + scale_fill_brewer(palette="Set1") +
        ggtitle(paste0("TEST LOSS: ", TEST.LOSS)),
  ncol=1, nrow=3
  )
dev.off()

#Plot representation of results
x.values <- read.csv(paste0(RESULTS ,"combined_D_values.txt"),
          header=T, sep="\t")
x.values <- data.table(x.values)

plot.epochs <- sort(unique(x.values$EPOCH), decreasing = T)[2:5]
x.values <- x.values[EPOCH %in% plot.epochs,]
print (dim(x.values))

master.clinical <- fread(paste0(TABLES,"master.clinical.txt"), header=T)
print (dim(master.clinical))
x.values$LIVED <- master.clinical$LIVED
print (dim(x.values))
print (x.values)

file.name <- paste0(FIGURES,
                    target.name, ".values.pdf")
pdf(file.name, width=16, height=12)

ggplot(x.values, aes(factor(PREDICTED), LIVED)) + geom_boxplot() + geom_jitter(colour="steelblue4", size=0.2) +
  facet_wrap(~EPOCH, ncol=2) + scale_fill_brewer(palette="Set1") + theme_classic() +
  geom_text(aes(1, 3, label=paste0("P-value=", round(P.VAL, 3))),
            hjust=1, size=3.5,
            data=x.values[,list(P.VAL=wilcox.test(LIVED[which(PREDICTED==1)],
                                                  LIVED[which(PREDICTED==0)], paired=F, alternative="greater")$p.value),
                           by="EPOCH"])

dev.off()

#############Plot survival results##############
#master.clinical <- fread("/Users/jzamalloa/Documents/Rotation/PIPELINES/METABOLIC.DRIVERS/TABLES/DRUG_THEANO_PRED/MLP/REGRESSION/TESTING/TRYING.FIGURES/master.clinical.txt", header=T)

master.clinical$STATUS <- ifelse(master.clinical$DEATH=="[Not Applicable]", 0, 1)

file.name <- paste0(FIGURES,
                    target.name, ".survival.pdf")
pdf(file.name, width=16, height=12)

plot.list <- lapply(plot.epochs, function(ep) {
  ep.clinical <- copy(master.clinical)
  ep.clinical$PREDICTION <- x.values[EPOCH==ep,]$PREDICTED

  #Classify prediction
  #classes <- Function.classify.lived.pred(ep.clinical$PREDICTION, sd.multiplier=0.5, effective="NEG")
  #ep.clinical <- merge(ep.clinical, classes, by="PREDICTION")
  #ep.clinical$LIVED <- Function.range.0.1(ep.clinical$LIVED)
  ep.clinical$LIVED <- ep.clinical$LIVED - min(ep.clinical$LIVED)
  ep.clinical$CASE <- ifelse(ep.clinical$PREDICTION==1, "EFFECTIVE", "NOT_EFFECTIVE")

  #Survive
  #print (master.clinical)
  test.survival<-survfit(Surv(LIVED, STATUS)~CASE, data=ep.clinical)
  SURV.DIFF <- survdiff(Surv(LIVED, STATUS)~CASE, data=ep.clinical)
  #print (SURV.DIFF)
  P.VAL <- pchisq(SURV.DIFF$chisq, length(SURV.DIFF$n)-1, lower.tail = FALSE)
  print (c(ep, P.VAL))

  ep.plot <- ggsurv(test.survival, surv.col=c("black", "darkviolet")) + theme(legend.position="bottom") +
              theme_classic()
  label <- paste0("EPOCH: ", ep,"\n", "P-value: ", round(P.VAL,3))

  return(list(PLOT=ep.plot, LABEL=label))
})

grid.arrange(plot.list[[1]][["PLOT"]] + geom_text(aes(0.65, 0.85, label= plot.list[[1]][["LABEL"]]), size=5.0)  ,
             plot.list[[2]][["PLOT"]] + geom_text(aes(0.65, 0.85, label= plot.list[[2]][["LABEL"]]), size=5.0),
             plot.list[[3]][["PLOT"]] + geom_text(aes(0.65, 0.85, label= plot.list[[3]][["LABEL"]]), size=5.0),
             plot.list[[4]][["PLOT"]] + geom_text(aes(0.65, 0.85, label= plot.list[[4]][["LABEL"]]), size=5.0),
            ncol=2, nrow=2)

dev.off()
