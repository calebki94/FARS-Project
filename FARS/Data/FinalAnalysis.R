data1 = read.csv("DriversData.csv") #only data for the drivers selected 

library(plyr)
library(dplyr)
library(mlbench)
library(caret)
library(readr)
require(mosaic)
library(randomForest)
library(geepack)
library(gee)

#should get around 30000 observations: if more than person involved in an accident 

small <- data %>% dplyr::select(V_V_CONFIG, V_TRAV_SP, V_DEFORMED, V_DR_DRINK, V_PREV_ACC, 
                                V_PREV_SUS, V_PREV_DWI, V_PREV_SPD, V_VALIGN, V_VPAVETYP, V_VSURCOND,
                                A_LGT_COND, A_FATALS, A_DRUNK_DR, A_WEATHER, A_WEATHER1, A_WEATHER2,
                                A_WRK_ZONE, A_MAN_COLL, P_AGE, P_SEX, P_INJ_SEV, P_SEAT_POS, 
                                P_AIR_BAG, P_EJECTION, P_EJ_PATH, P_DRINKING, P_DRUGS, 
                                P_LAG_HRS, P_DOA, A_COUNTY, A_STATE, A_CITY, A_DAY_WEEK, A_HOUR)

filter <- unique(small) 
small <- filter

#Counting the county frequency by fips code

small$A_STATE <- as.numeric(small$A_STATE)
small$A_COUNTY <- as.numeric(small$A_COUNTY)
small <- small %>% mutate(FIPSCode = ((1000*A_STATE) + A_COUNTY)) #fips code 


countiesL <- tally(small$FIPSCode)
data4 <- data.frame(countiesL)
data6 <- rename(data4, FIPSCode = X)
data7 <- merge(data6, small) 
data7 <- unique(data7) 

#create new variable here: only counties 

data8 <- data7 %>%
  filter(Freq > 10)
nrow(data8) #48169 observations 

data8$P_SEX = as.factor(data8$P_SEX)
data8$P_DRUGS = as.factor(data8$P_DRUGS)
data8$P_DOA = as.factor(data8$P_DOA)
data8$V_DEFORMED = as.factor(data8$V_DEFORMED)
data8$V_DR_DRINK = as.factor(data8$V_DR_DRINK)

data8 <- rename(data8, state = A_STATE)
data8 <- rename(data8, county = A_COUNTY)
data8$state = as.factor(data8$state)
data8$county = as.factor(data8$county)

data8 <- data8 %>% mutate(TravSpeed = as.numeric(V_TRAV_SP),
                          Age = as.numeric(P_AGE),
                          PDWI = as.numeric(V_PREV_DWI),
                          PSuspension = as.numeric(V_PREV_SUS),
                          PCrash = as.numeric(V_PREV_ACC),
                          PSpeed = as.numeric(V_PREV_SPD))

data9 <- data8

ACS <- load("CensusFinalD1.Rda")
CensusFinalD1$FIPSCode <- as.factor(CensusFinalD1$FIPSCode)
FinalMerge2<- CensusFinalD1 %>% right_join(data9, by = "FIPSCode") #40422 observations
FinalMerge2 <- na.omit(FinalMerge2)

########Build training and test models here
FinalMerge2 <- rename(FinalMerge2, IncomeToPovRatio = C17002_001) #Quant
FinalMerge2 <- rename(FinalMerge2, TotalPopulation = B01003_001) #Quant
FinalMerge2 <- rename(FinalMerge2, Sex = P_SEX) #Cat
FinalMerge2 <- rename(FinalMerge2, PrevDWIConvictions = PDWI) #Quantitative
FinalMerge2 <- rename(FinalMerge2, PrevSpeeding = PSpeed) #Quantitative
FinalMerge2 <- rename(FinalMerge2, PrevSuspensions = PSuspension) #Quant
FinalMerge2 <- rename(FinalMerge2, VehicleSpeed = TravSpeed) #Quant
FinalMerge2 <- rename(FinalMerge2, ReportedDrugs = P_DRUGS) #Cat
FinalMerge2 <- rename(FinalMerge2, NumFatalities = A_FATALS) #Quant
FinalMerge2 <- rename(FinalMerge2, DeathSceneStatus = P_DOA) #Cat
FinalMerge2 <- rename(FinalMerge2, DriverDrinking = V_DR_DRINK) #Cat

FinalMerge2 <- FinalMerge2 %>% filter(Sex == '1' | Sex == '2')
FinalMerge2$Sex <- droplevels(FinalMerge2$Sex)
levels(FinalMerge2$Sex) <- c("Male", "Female")

FinalMerge2 <- FinalMerge2 %>% filter(ReportedDrugs == '0' | ReportedDrugs == '1')
FinalMerge2$ReportedDrugs <- droplevels(FinalMerge2$ReportedDrugs)
levels(FinalMerge2$ReportedDrugs) <- c("No", "Yes")

FinalMerge2 <- FinalMerge2 %>% filter(DeathSceneStatus == '7' | DeathSceneStatus == '8')
FinalMerge2$DeathSceneStatus <- droplevels(FinalMerge2$DeathSceneStatus)
levels(FinalMerge2$DeathSceneStatus) <- c("DiedAtScence", "DiedAtEnroute")

#Creating weekend/weekday predictor 
FinalMerge2 <- FinalMerge2 %>%
  mutate(WeekdayStatus = ifelse(A_DAY_WEEK == '1' | A_DAY_WEEK == '7', "Weekend", "Weekday"))
FinalMerge2$WeekdayStatus <- as.factor(FinalMerge2$WeekdayStatus)

FinalMerge2 <- FinalMerge2 %>%
  mutate(DayStatus = ifelse(A_HOUR < 6 | A_HOUR > 18, "Night", "Day"))
FinalMerge2$DayStatus <- as.factor(FinalMerge2$DayStatus)

test <- FinalMerge2 %>% select(A_HOUR, DayStatus, A_DAY_WEEK, WeekdayStatus) #6908 observations in total 


#Creating training and test results 
mergeData <- FinalMerge2
n <- nrow(mergeData)
shuffled <- mergeData[sample(n),]
train <- shuffled[1:round(0.7 * n),]
test <- shuffled[(round(0.7 * n) + 1):n,]

logmod <- glm(formula = DriverDrinking ~ Sex + Age + PrevSuspensions + PrevDWIConvictions + PrevSpeeding 
              + ReportedDrugs + VehicleSpeed + DeathSceneStatus + 
                NumFatalities + WeekdayStatus + DayStatus + IncomeToPovRatio + TotalPopulation,
              family=binomial(link='logit'), data = train)
summary(logmod)
prob <- predict(logmod, newdata=test, type="response")
pred <- prediction(prob, test$DriverDrinking)
perf <- performance(pred, measure = "tpr", x.measure = "fpr")
plot(perf)

#Accuracy assessment 
auc <- performance(pred, measure = "auc")
auc <- auc@y.values[[1]]
auc #79% accurate 


set.seed(1000)
modForest <- randomForest(DriverDrinking ~ Sex + Age + PrevSuspensions + PrevDWIConvictions + 
                          PrevSpeeding + ReportedDrugs + VehicleSpeed + DeathSceneStatus + 
                          NumFatalities + WeekdayStatus + DayStatus + IncomeToPovRatio + 
                          TotalPopulation, data = train, ntree = 100, mtry = 4, 
                        keep.forest = FALSE, importance = TRUE)
#Importance plots  
varImpPlot(modForest)
test.forest = predict(modForest, type = "prob", newdata = test)
forestpred = prediction(test.forest[,2], test$DriverDrinking)
forestperf = performance(forestpred, "tpr", "fpr")
plot(perf, main="Random Forest ROC [Accuracy: 0.65]")

#Assessing model accuracy 
modForest1 <- randomForest(DriverDrinking ~ Sex + Age + PrevSuspensions + PrevDWIConvictions + 
                            PrevSpeeding + ReportedDrugs + VehicleSpeed + DeathSceneStatus + 
                            NumFatalities + WeekdayStatus + DayStatus + IncomeToPovRatio + 
                            TotalPopulation, data = train, ntree = 100, mtry = 4, 
                          keep.forest = TRUE, importance = FALSE)
conf <- modForest$confusion
print(sum(diag(conf)) / sum(conf)) #63% model accuracy 


