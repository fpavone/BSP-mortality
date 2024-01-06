# Learning and Forecasting of Age–Specific Period Mortality via B–Spline Processes with Locally–Adaptive Dynamic Coefficients

This repository is associated with the article **"Learning and Forecasting of Age–Specific Period Mortality via B–Spline Processes with Locally–Adaptive Dynamic Coefficients"** and aims at providing detailed materials and codes to implement the **BSP** model presented in the article and to **fully reproduce the results in Sections 4**.

In order to obtain all the results from the paper, run `main.R`. A step-by-step explanation on how to implement and fit the model is given in the notebook `application-countries/BSP_stepbystep.Rmd`.


## Further information

A general overview of the organization of the repository is provided below.

- `main.R` contains the call to all the scripts necessary to reproduce the results in **Section 4** of the paper;
- `data` contains the data as downloaded from the Human Mortality Database;
- `source` contains all the `R` functions required to process the data, fit the model, and make forecasts:
  - `data_processing.R` contains the preprocessing of the data for the countries analyzed in the article;
  - `data_processing_extra.R` contains the preprocessing of the data for additional countries;
  - `setup.R` contains some setting of the model, such as the spline knots and the kernel function;
  - `BSP.R` contains the code to implement and fit the **BSP** model;
  - `BSP_forecast.R` contains the code to implement and fit the **BSP** forecasting model;
  - `helper_fun.R` contains few functions useful to post-process the results and create plot-friendly dataframes.
- `application-countries` contains reproducible code for the application to US, UK, Sweden, and Italy, as described in detail in **Section 4** of the paper;
- `output` all the outputs generated by any of the previous scripts will be save in this folder (for example, the file `ITA_fit.Rdata`is the result of the scripts run in `BSP_stepbystep.Rmd`);

**Note**: for those who want to inspect the implementation of the functions in `source`, they should keep in mind that the notation of the code uses letter `U` referring to parameters $\beta$ of the model in the paper.

The analyses are performed using `R` version **4.0.3** and `KFAS` package version **1.4.6**. Note that, although a seed is set at the beginning of each script, the final output reported in the tables and figures may be subject to slight variations depending on which version of the `R` packages has been used in the implementation of the code. This is due to possible internal changes of certain functions when the package version has been updated. However, the magnitude of these minor variations is negligible and does not affect the final conclusions.
