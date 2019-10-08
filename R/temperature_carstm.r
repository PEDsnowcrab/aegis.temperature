
temperature_carstm = function( p=NULL, DS=NULL, sppoly=NULL, redo=FALSE, ... ) {

  #\\ Note inverted convention: depths are positive valued
  #\\ i.e., negative valued for above sea level and positive valued for below sea level

  # deal with additional passed parameters
  if ( is.null(p) ) p=list()
  p_add = list(...)
  if (length(p_add) > 0 ) p = c(p, p_add)
  i = which(duplicated(names(p), fromLast = TRUE ))
  if ( length(i) > 0 ) p = p[-i] # give any passed parameters a higher priority, overwriting pre-existing variable


  # -----------------------


  if ( DS=="carstm_inputs") {

    fn = file.path( p$modeldir, paste( "temperature", "carstm_inputs", p$auid,
      p$inputdata_spatial_discretization_planar_km,
      round(p$inputdata_temporal_discretization_yr, 6),
      "rdata", sep=".") )

    if (!redo)  {
      if (file.exists(fn)) {
        load( fn)
        return( M )
      }
    }
    message( "Generating carstm_inputs ... ")

    # prediction surface
    sppoly = areal_units( p=p )  # will redo if not found

    crs_lonlat = sp::CRS(projection_proj4string("lonlat_wgs84"))

    # do this immediately to reduce storage for sppoly (before adding other variables)
    M = temperature.db( p=p, DS="aggregated_data"  )  # will redo if not found .. not used here but used for data matching/lookup in other aegis projects that use bathymetry

    # reduce size
    M = M[ which( M$lon > p$corners$lon[1] & M$lon < p$corners$lon[2]  & M$lat > p$corners$lat[1] & M$lat < p$corners$lat[2] ), ]
    # levelplot(z.mean~plon+plat, data=M, aspect="iso")

    M$StrataID = over( SpatialPoints( M[, c("lon", "lat")], crs_lonlat ), spTransform(sppoly, crs_lonlat ) )$StrataID # match each datum to an area
    M$lon = NULL
    M$lat = NULL
    M$plon = NULL
    M$plat = NULL
    M = M[ which(is.finite(M$StrataID)),]
    M$StrataID = as.character( M$StrataID )  # match each datum to an area

    M$t = M$temperature.mean
    M$tag = "observations"

    APS = as.data.frame(sppoly)
    APS$StrataID = as.character( APS$StrataID )
    APS$tag ="predictions"
    APS$t = NA
    APS$z = NA

    pb = aegis.bathymetry::bathymetry_parameters( p=p, project_class="carstm_auid" ) # transcribes relevant parts of p to load bathymetry
    BI = bathymetry_carstm ( p=pb, DS="carstm_modelled" )  # unmodeled!
    jj = match( as.character( APS$StrataID), as.character( BI$StrataID) )
    APS$z = BI$z.predicted[jj]
    jj =NULL
    BI = NULL

    vn = c("t", "tag", "StrataID", "z")
    APS = APS[, vn]

    # expand APS to all time slices
    n_aps = nrow(APS)
    APS = cbind( APS[ rep.int(1:n_aps, p$nt), ], rep.int( p$prediction_ts, rep(n_aps, p$nt )) )
    names(APS) = c(vn, "tiyr")

    M$temperature = M$temperature.mean
    M$tiyr = M$yr + M$dyear
    M = rbind( M[, names(APS)], APS )
    APS = NULL

    M$StrataID  = factor( as.character(M$StrataID), levels=levels( sppoly$StrataID ) ) # revert to factors
    sppoly = NULL

    save( M, file=fn, compress=TRUE )
    return( M )
  }


  # ------------



  if ( DS=="carstm_modelled") {

    auids = paste(  p$auid, p$inputdata_spatial_discretization_planar_km,
      round(p$inputdata_temporal_discretization_yr, 6),   sep="_" )

    fn = file.path( p$modeldir, paste("temperature", "carstm_modelled", p$carstm_modelengine, auids, "rdata", sep="." ) )
    fn_fit = file.path( p$modeldir, paste( "temperature", "carstm_modelled_fit", p$carstm_modelengine, auids,  "rdata", sep=".") )

    if (!redo)  {
         if (file.exists(fn)) {
        load( fn)
        return( res )
      }
      if (DS=="carstm_modelled_fit") {
        if (file.exists(fn_fit)) {
          load( fn_fit )
          return( fit )
        }
      }
    }

    # prediction surface
    sppoly = areal_units( p=p )  # will redo if not found
    res = sppoly@data["StrataID"]  # init results data frame

    M = temperature_carstm ( p=p, DS="carstm_inputs" )  # 16 GB in RAM just to store!

    fit  = NULL

    if ( grepl("glm", p$carstm_modelengine) ) {
      assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
      if (is.null(fit)) error("model fit error")
      if ("try-error" %in% class(fit) ) error("model fit error")
      save( fit, file=fn_fit, compress=TRUE )
      ii = which( M$tag=="predictions" & M$StrataID %in% M[ which(M$tag=="observations"), "StrataID"] )
      jj = match( M$StrataID[ii], res$StrataID )
      preds = predict( fit, newdata=M[ii,], type="link", na.action=na.omit, se.fit=TRUE )  # no/km2
      res[,"temperature.predicted"] = exp( preds$fit[jj])
      res[,"temperature.predicted_se"] = exp( preds$se.fit[jj])
      res[,"temperature.predicted_lb"] = exp( preds$fit[jj] - preds$se.fit[jj] )
      res[,"temperature.predicted_ub"] = exp( preds$fit[jj] + preds$se.fit[jj] )
      save( res, file=fn, compress=TRUE )
    }

    if ( grepl("gam", p$carstm_modelengine) ) {
      assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
      if (is.null(fit)) error("model fit error")
      if ("try-error" %in% class(fit) ) error("model fit error")
      save( fit, file=fn_fit, compress=TRUE )
      ii = which( M$tag=="predictions" & M$StrataID %in% M[ which(M$tag=="observations"), "StrataID"] )
      jj = match( M$StrataID[ii], res$StrataID )
      preds = predict( fit, newdata=M[ii,], type="link", na.action=na.omit, se.fit=TRUE )  # no/km2
      res[,"temperature.predicted"] = exp( preds$fit[jj])
      res[,"temperature.predicted_se"] = exp( preds$se.fit[jj])
      res[,"temperature.predicted_lb"] = exp( preds$fit[jj] - preds$se.fit[jj] )
      res[,"temperature.predicted_ub"] = exp( preds$fit[jj] + preds$se.fit[jj] )
      save( res, file=fn, compress=TRUE )
    }


    if ( grepl("inla", p$carstm_modelengine) ) {
      H = carstm_hyperparameters( sd(M$temperature, na.rm=TRUE), alpha=0.5, median( M$temperature, na.rm=TRUE) )
      M$zi = discretize_data( M$z, p$discretization$z )
      M$tiyr2 = M$tiyr  # use a copy for "seasonal" models
      M$year = floor(M$tiyr)
      M$dyear  =  M$tiyr - M$year
      M$strata  = as.numeric( M$StrataID)
      M$iid_error = 1:nrow(M) # for inla indexing for set level variation
      assign("fit", eval(parse(text=paste( "try(", p$carstm_modelcall, ")" ) ) ))
      if (is.null(fit)) error("model fit error")
      if ("try-error" %in% class(fit) ) error("model fit error")
      save( fit, file=fn_fit, compress=TRUE )
      # reformat predictions into matrix form
      ii = which(M$tag=="predictions")
      res = list()

      # res[ res>1e10] = NA

      res$temperature.predicted = reformat_to_array(
        input = fit$summary.fitted.values[ ii, "mean" ],
        matchfrom = list( StrataID=M$StrataID[ii], yr_factor=M$yr_factor[ii], dyear=M$dyear[ii] ),
        matchto   = list( StrataID=res$StrataID, yr_factor=factor(p$yrs), dyear=p$dyears )
      )

      res$temperature.predicted_lb = reformat_to_array(
        input = fit$summary.fitted.values[ ii, "0.025quant" ],
        matchfrom = list( StrataID=M$StrataID[ii], yr_factor=M$yr_factor[ii], dyear=M$dyear[ii] ),
        matchto   = list( StrataID=res$StrataID, yr_factor=factor(p$yrs), dyear=p$dyears )
      )

      res$temperature.predicted_lb = exp( fit$summary.fitted.values[ ii[jj], "0.025quant" ])
      res$temperature.predicted_ub = exp( fit$summary.fitted.values[ ii[jj], "0.975quant" ])
      res$temperature.random_strata_nonspatial = exp( fit$summary.random$strata[ jj, "mean" ])
      res$temperature.random_strata_spatial = exp( fit$summary.random$strata[ jj+max(jj), "mean" ])
      res$temperature.random_sample_iid = exp( fit$summary.random$iid_error[ ii[jj], "mean" ])
      save( res, file=fn, compress=TRUE )
    }

    return( res )
  }

}
