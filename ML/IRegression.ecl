﻿// Define the Regression interface for various regression implementation.
//
IMPORT ML;
IMPORT ML.Types;
IMPORT ML.Mat AS Mat;
IMPORT PBblas.Types AS DMatTypes;
IMPORT ML.Mat.Types AS MatTypes;
NumericField := Types.NumericField;
/*
  The object of the regression module is to generate a regression model.
  A regression model relates the dependent variable Y to a function of
  the independent variables X, and a vector of unknown parameters Beta.
    Y = f(X,Beta)
  A regression model is an algorithm that estimates the unknown parameters
  Beta so that a regression function Y = f(X,Beta) can be constructed
*/

EXPORT IRegression := MODULE,VIRTUAL
  EXPORT CoRec := RECORD
    Types.t_fieldnumber number;
    Types.t_fieldreal   RSquared;
  END;
  // The inputs in a standard form
  SHARED DATASET(NumericField) Independents;
  SHARED DATASET(NumericField) Dependents;
  // The model parameter estimates
  EXPORT DATASET(NumericField) betas;
  // The predicted values of Y
  EXPORT DATASET(NumericField) modelY;
  // Extrapolated (interpolated) values of Y based upon provided X values
  EXPORT DATASET(NumericField) Extrapolated(DATASET(NumericField) newX);
  // The R Squared values for the parameters
  EXPORT DATASET(CoRec)  RSquared;
  // Produce an Analysis of Variance report
  K := COUNT(ML.FieldAggregates(Independents).Cardinality);
  Singles := ML.FieldAggregates(Dependents).Simple;
  tmpRec := RECORD
    RECORDOF(Singles);
    Types.t_fieldreal  RSquared;
  END;

  Singles1 := JOIN(Singles, RSquared, LEFT.number=RIGHT.number,
          TRANSFORM(tmpRec,  SELF.RSquared := RIGHT.RSquared, SELF := LEFT));

  AnovaRec := RECORD
    Types.t_fieldnumber   number;
    Types.t_RecordID      Model_DF; // Degrees of Freedom
    Types.t_fieldreal      Model_SS; // Sum of Squares
    Types.t_fieldreal      Model_MS; // Mean Square
    Types.t_fieldreal      Model_F;  // F-value
		Types.t_fieldreal			Model_pValue;
    Types.t_RecordID      Error_DF; // Degrees of Freedom
    Types.t_fieldreal      Error_SS;
    Types.t_fieldreal      Error_MS;
    Types.t_RecordID      Total_DF; // Degrees of Freedom
    Types.t_fieldreal      Total_SS;  // Sum of Squares
  END;

  AnovaRec getResult(tmpRec le) :=TRANSFORM
    SST := le.var*le.countval;
    SSM := SST*le.RSquared;

    SELF.number := le.number;
    SELF.Total_SS := SST;
    SELF.Model_SS := SSM;
    SELF.Error_SS := SST - SSM;
    SELF.Model_DF := k;
    SELF.Error_DF := le.countval-k-1;
    SELF.Total_DF := le.countval-1;
    SELF.Model_MS := SSM/k;
    SELF.Error_MS := (SST - SSM)/(le.countval-k-1);
    SELF.Model_F := (SSM/k)/((SST - SSM)/(le.countval-k-1));
		
		dist := ML.Distribution.FDist(SELF.Model_DF, SELF.Error_DF, 100000);
		SELF.Model_pValue := 1 - dist.cumulative(SELF.Model_F);
  END;

  //http://www.stat.yale.edu/Courses/1997-98/101/anovareg.htm
  //Tested using the "Healthy Breakfast" dataset	
	EXPORT Anova := PROJECT(Singles1, getResult(LEFT));
	
	EXPORT Dataset(NumericField) var_covar;
	
	NumericField sErr(NumericField b) :=TRANSFORM
		SELF.value := sqrt(var_covar(id = b.number + 1 AND number = b.number + 1)[1].value);
		SELF.id := b.id;
		SELF.number := b.number;
	END;
	
	EXPORT DATASET(NumericField) SE := PROJECT(betas, sErr(LEFT));
	
	NumericField tStat_transform(NumericField b) := TRANSFORM
		SELF.value := b.value / SE(id = b.id AND number = b.number)[1].value;
		SELF := b;
	END;
	
	EXPORT tStat := PROJECT(betas, tStat_transform(LEFT));
	
	EXPORT dist := ML.Distribution.StudentT(Anova[1].Error_DF, 100000);
	
	NumericField pVal_transform(NumericField b) := TRANSFORM 
		SELF.value := 2 * ( 1 - dist.Cumulative(ABS(b.value))); 
		SELF := b;
	END;
	
	EXPORT pVal := PROJECT(tStat, pVal_transform(LEFT));
  EXPORT Dataset(CoRec) AdjRSquared := PROJECT(RSquared, TRANSFORM(CoRec, 
																SELF.RSquared := 1 - ( 1 - LEFT.RSquared ) * ( Anova[1].Total_DF/Anova[1].Error_DF); 
																SELF := LEFT));
		
	confintRec := RECORD
		Types.t_RecordID id;
		Types.t_FieldNumber number;
		Types.t_Fieldreal LowerInt;
		Types.t_Fieldreal UpperInt;
	END;
	
	confintRec confint_transform(NumericField b, REAL Margin) := TRANSFORM
		SELF.UpperInt := b.value + Margin * SE(id = b.id AND number = b.number)[1].value;
		SELF.LowerInt := b.value - Margin * SE(id = b.id AND number = b.number)[1].value;
		SELF := b;
	END;
																
  EXPORT ConfInt(Types.t_fieldReal level) := FUNCTION
		newlevel := 100 - (100 - level)/2;
		Margin := dist.NTile(newlevel);
		RETURN PROJECT(betas, confint_transform(LEFT, Margin));
	END;
	
	
	
END;