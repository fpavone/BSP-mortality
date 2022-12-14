# This script is mostly designed for the increasing sample size
# forecasting esperiment implemented in the paper.
# However, user can find useful functions optim_rwd()
# and fitandforecast() as they can be used 
# in more general settings.

require(mvtnorm)

###############################################
## Log-likelihood of random walk plus drift  ##
###############################################
#
#   u0 ~ N(mu0,Q0)
#   ut | u_t-1 ~ N(u_t-1 + Tt*drift, Qt)
#   par is omega_w
#   u is list of smoothing mean
#   
optim_rwd <- function(pars, 
                      u, 
                      mu0, 
                      Tt, 
                      drift, 
                      kernel, 
                      ages_max, 
                      K) {
  sigma2_u <- exp(pars[1])
  # Build Qt
  Qt <- diag(K+1) * sigma2_u
  for(I in 1:(K+1-1)){
    for(J in (I+1):(K+1)){
      rho_u <- kernel(x = abs(ages_max[J]-ages_max[I]))
      Qt[I,J] <- Qt[J,I] <- sigma2_u * rho_u
    }
  }
  loglik <- dmvnorm(u[1,], mean = mu0, sigma = 10*diag(K+1), log = TRUE)
  for(i in 2:nrow(u)){
    loglik <- loglik + 
      dmvnorm(u[i,], mean = u[i-1,] + Tt%*%drift, sigma = Qt, log = TRUE)
  }
  return(-loglik)
}


###############################################
## Fit and h-step-ahead forecast  #############
###############################################
#
# INPUT:
#   - model: BSP model to estimate (result of bsp.model)
#   - h: how many step-ahead to forecast
#   - Z: maximum age
#   - rep: how many time to repeat optimization
#   - n_for: how many years to use in the trainig data
#           to estimate the rw+drift model
#   - method: optimization method
#   - parallel: parallelization
#   - maxcl: maximum number of cluster ofr the parallelization
#
# OUTPUT:
#   - pred: forecasts
#
fitandforecast <- function(model, 
                           h, 
                           Z, 
                           rep, 
                           n_for, 
                           method = 'Nelder-Mead', 
                           parallel = TRUE, 
                           maxcl = 30) {
  fit <- bsp.fit(model, 
                 rep = rep, 
                 method = 'Nelder-Mead', 
                 parallel = parallel, 
                 maxcl = 30)
  K <- fit$info$K
  ## Fitting random-walk with drif for prediction
  # Smoothing distribution
  smooth <- KFS(fit$fit, smoothing = c('state','signal'))
  # Extracting info on U and dU from BSP model
  U_m <- smooth$alphahat[, paste('U', 0:K, sep = '')][train - n_for + 1,]
  U <- smooth$alphahat[, paste('U', 0:K, sep = '')] %>% 
    tail(n = n_for, k = 1) # selecting last n_for years
  dU <- apply(smooth$alphahat[, paste('dU', 0:K, sep = '')] %>%
                tail(n = n_for, k = 1), # selecting last n_for years
              MARGIN = 2, median)
  ## Creating random walk + dirft model
  Tt_pred <- fit$fit$T[1,2,1] # lambda*delta
  kernel <- fit$info$kernel
  ages_max <- fit$info$ages_max
  # Estimation of rw + drift
  rep_pred <- 5
  starting_values <- log(runif(rep_pred, min = 1e-2, max = 2))
  fit_rw_list <- lapply(starting_values, 
                        function(init){
                          try(optim(par = init,
                                    fn = optim_rwd,
                                    method = "L-BFGS-B",
                                    control = list(maxit = 1e6),
                                    u = U, 
                                    mu0 = U_m,
                                    Tt = Tt_pred,
                                    drift = dU,
                                    kernel = fit$info$kernel,
                                    ages_max = fit$info$ages_max,
                                    K = K), TRUE)
                        })
  # Checking failed optim
  fit_rw_list_clean <- discard(fit_rw_list, 
                               . %>% inherits(., 'try-error'))
  print(paste('Number of failed optim attempt:', 
              length(fit_rw_list) - length(fit_rw_list_clean)))
  if(length(fit_rw_list_clean) == 0){
    print('All optimization attempts failed..')
    return(-1)
  }
  # Extracting best fit
  best_fit_rw <- which.min(sapply(fit_rw_list_clean, . %>% `$`(.,value)))
  fit_rw <- fit_rw_list_clean[[best_fit_rw]]
  
  ## Composing rw + drift with estimated sigma2_u
  sigma2_u <- exp(fit_rw$par)
  Qt_pred <- diag(K+1) * sigma2_u
  for(I in 1:(K+1-1)){
    for(J in (I+1):(K+1)){
      rho_u <- kernel(x = abs(ages_max[J]-ages_max[I]))
      Qt_pred[I,J] <- Qt_pred[J,I] <- sigma2_u * rho_u
    }
  }
  Zt_pred <- fit$fit$Z[, seq(1, 3*(K+1), by = 3), ]
  a1_pred <- tail(U, n = 1 ,k = 1) # last year of training
  P1_pred <- smooth$V %>%
    tail(n = c(3*(K+1), 3*(K+1), 1)) %>% # selecting last year 
    # extracting only var(u) components
    `[`(seq(1, 3*(K+1), by = 3), seq(1, 3*(K+1), by = 3), ) 
  U_var_mean <- smooth$V %>%
    tail(n = c(3*(K+1), 3*(K+1), n_for)) %>% # selecting last n_for years
    `[`(seq(1, 3*(K+1), by = 3), seq(1, 3*(K+1), by = 3), ) %>%
    apply(MARGIN = c(1,2), mean)
  Ht <- fit$fit$H[,,1] # observational variance
  # Prediction h-step ahead
  U_pred <- matrix(NA, nrow = h, ncol = K+1)
  varU_pred <- array(NA, dim = c(K+1, K+1, h))
  f_pred <- matrix(NA, nrow = h, ncol = Z)
  varf_pred <- array(NA, dim = c(Z, Z, h))
  for(tt in 1:h){
    if(tt == 1){
      U_pred[1,] <- as.numeric(a1_pred) + Tt_pred%*%dU
      varU_pred[,,1] <- P1_pred + Qt_pred + U_var_mean
      f_pred[1,] <- Zt_pred%*%U_pred[1,]
      varf_pred[,,1] <- Ht + 
        Zt_pred %*% varU_pred[,,1] %*% t(Zt_pred)
    } else {
      U_pred[tt,] <- U_pred[tt-1,] + Tt_pred%*%dU
      varU_pred[,,tt] <- varU_pred[,,tt-1] + Qt_pred + U_var_mean
      f_pred[tt,] <- Zt_pred%*%U_pred[tt,]
      varf_pred[,,tt] <- Ht + 
        Zt_pred %*% varU_pred[,,tt] %*% t(Zt_pred)
    }
  }
  pred <- list()
  for(zz in 1:Z){
    pred <- c(pred,
              list(tibble(fit = f_pred[,zz],
                          upr = qnorm(p = 0.975,
                                      mean = f_pred[,zz],
                                      sd = sqrt(varf_pred[zz,zz,])),
                          lwr = qnorm(p = 0.025,
                                      mean = f_pred[,zz],
                                      sd = sqrt(varf_pred[zz,zz,])))))
  }
  names(pred) <- as.character(0:(Z-1))
  
  return(pred)
}


###############################################
## Helper function to fit with increasing     #
##??sample size (interal use)                  #
###############################################
#
rolling <- function(cg, n_for = 25){
  # Loading the data corrisponding to country cg
  country <- sub("_.*", "", cg)
  gender <- sub(".*_", "", cg)
  print(paste('Doing', country, gender))
  Y <- eval(parse(text = paste('Y', country, gender, sep = '_')))
  N <- eval(parse(text = paste('N', country, gender, sep = '_')))
  Tmax <- nrow(Y)
  Z <- ncol(Y)
  
  # Creating increasing sample size datasets
  data_list <- lapply(train:(Tmax - h_step),
                      function(t){
                        Y[1:t,]/N[1:t,]
                        })
  model_list <- lapply(data_list, . %>% bsp.model(.,
                                                   delta = delta,
                                                   age_knots = age_knots,
                                                   kernel = matern_kernel))
  # Fit and forecast
  fitandfor_list <- lapply(model_list,
                           . %>% fitandforecast(.,
                                                h = h_step,
                                                Z = Z,
                                                rep = rep,
                                                n_for = n_for,
                                                method = 'Nelder-Mead',
                                                parallel = TRUE,
                                                maxcl = 50))
  # Postprocessing of forecast list
  forecast_list <- try(fitandfor_list %>%
                         modify(. %>% imap_dfr(.f = ~ (as_tibble(.) %>%
                                                         mutate(h_ahead = 1:h_step)),
                                               .id = 'age')) %>%
                         imap_dfr(.f = ~ ., .id='t') %>%
                         mutate_at(vars(t), as.numeric) %>%
                         mutate(country = country,
                                gender = gender))
  return(forecast_list)
}