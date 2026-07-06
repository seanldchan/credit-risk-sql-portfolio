# Credit Risk SQL portfolio

https://www.kaggle.com/datasets/laotse/credit-risk-dataset/code

## Setup
1. Download the dataset from the Kaggle link above
2. Create a MySQL database and import the CSV as a table named `credit_risk_dataset_2`
3. Run scripts in order: 00, 01

## Limitations
- LGD fixed at 45% (the Basel II floor for unsecured retail exposures). There is no  recovery data to model this directly.

## Related project

Companion Python logistic regression scorecard: https://github.com/seanldchan/Credit_Risk_Analysis_Project — takes the strongest 
predictors identified in segment analysis and turns them into a modelled, 
forward-looking PD.