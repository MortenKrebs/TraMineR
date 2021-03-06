# Author for TraMineR 2: Pierre-Alexandre Fonta (2016-2017)

seqdist <- function(seqdata, method, refseq = NULL, norm = "none", indel = 1.0,
  sm = NULL, with.missing = FALSE, full.matrix = TRUE,
  kweights = rep(1.0, ncol(seqdata)), tpow = 1.0, expcost = 0.5, context,
  link = "mean", h = 0.5, nu, transindel = "constant", otto,
  previous = FALSE, add.column = TRUE, breaks = NULL, step = 1, overlap = FALSE,
  weighted = TRUE, prox = NULL) {

  gc(FALSE)
  ptime.begin <- proc.time()
  tol <- .Machine$double.eps^0.5 # Precision

  #### Check arguments with deprecated values ####

  # method
  # TODO Deprecated: remove in future versions.
  deprecated.methods <- c("OMopt", "LCSopt")
  if (method %in% deprecated.methods) {
    msg.warn(method, "is deprecated")
    if (method == "OMopt") {
      method <- "OM"
      msg("'method' is set to \"OM\" which is equivalent")
    } else if (method == "LCSopt") {
      method <- "LCS"
      msg("'method' is set to \"LCS\" which is equivalent")
    }
  }

  # norm
  if (is.logical(norm)) {
    norm <- if (isTRUE(norm)) "auto" else "none"
    msg.warn("'norm' has a deprecated value, TRUE changed into \"auto\", FALSE into \"none\"")
  }

  #### Check for arguments that need to be defined ####

  # method
  if (missing(method))
    msg.stop.miss("method")

  #### Check argument types ####

  # seqdata
  if (!inherits(seqdata, "stslist"))
    msg.stop("'seqdata' must be a state sequence object created with seqdef()")

  nseqs <- nrow(seqdata)
  alphabet <- alphabet(seqdata)
  nstates <- length(alphabet)
  seqs.dlens <- unique(seqlength(seqdata))
  seqdata.nr <- attr(seqdata, "nr")

  # method
  # Add here new method names
  om.methods <- c("OM", "OMloc", "OMslen", "OMspell", "OMstran")
  methods <- c(om.methods, "HAM", "DHD", "CHI2", "EUCLID", "LCS", "LCP",
    "RLCP", "NMS", "NMSMST", "SVRspell", "TWED")
  if (! method %in% methods)
    msg.stop.in("method", methods)

  # refseq
  # refseq.type: "none", "sequence", "most frequent", "index"
  if (!is.null(refseq)) {
    if (inherits(refseq, "stslist")) {
      if (nrow(refseq) != 1)
        msg.stop("'refseq' must contain a (single) sequence")
      if (!identical(alphabet(refseq), alphabet))
        msg.stop("'refseq' and 'seqdata' must have the same alphabet")
      refseq.nr <- attr(refseq, "nr")
      if (!identical(seqdata.nr, refseq.nr))
        msg.stop("'refseq' and 'seqdata' must have the same code for missing values")
      refseq.type <- "sequence"
    } else if (is.a.positive.integer(refseq)) {
      if (refseq > nseqs)
        msg.stop("'refseq' must be less than the number of sequences in 'seqdata'")
      refseq.type <- if (refseq == 0) "most frequent" else "index"
    } else {
      msg.stop.na("refseq")
    }
  } else {
    refseq.type <- "none"
  }

  # with.missing
  has.seqdata.missings <- any(seqdata == seqdata.nr)
  has.refseq.missings <- if (refseq.type == "sequence" && any(refseq == refseq.nr)) TRUE else FALSE
  if (isTRUE(with.missing) && !has.seqdata.missings && !has.refseq.missings) {
    with.missing <- FALSE
    msg.warn("'with.missing' set to FALSE as 'seqdata' doesn't contain missing values")
  }
  if (!isTRUE(with.missing) && (has.seqdata.missings || has.refseq.missings))
    msg.stop("'with.missing' must be TRUE when 'seqdata' or 'refseq' contains missing values")

  if (isTRUE(with.missing)) {
    nstates <- nstates + 1
    msg("including missing values as an additional state")
  }
  msg(nseqs, "sequences with", nstates, "distinct states")

  # norm
  # "auto" must be the first element
  # Add here new normalization method names
  norms <- c("auto", "none", "maxlength", "gmean", "maxdist", "YujianBo")
  if (! norm %in% norms)
    msg.stop.in("norm", norms)

  # indel
  # indel.type: "number", "vector"
  # Must be after including missing values as an additional state (nstates)
  if (is.a.number(indel)) {
    indel.type <- "number"
  } else if (is.vector(indel, mode = "numeric")) {
    if (length(indel) != nstates)
      msg.stop("'indel' must contain a cost for each states")
    indel.type <- "vector"
  } else {
    msg.stop.na("indel")
  }

  # sm
  # Must be after sanity checks on 'indel'
  # Add here new seqcost() method names
  sm.methods <- c("TRATE", "CONSTANT", "INDELS", "INDELSLOG")
  # sm.type: "none", "matrix", "array", "method"
  if (!is.null(sm)) {
    if (is.matrix(sm)) {
      sm.type <- "matrix"
    } else if (is.array(sm)) {
      sm.type <- "array"
    } else if (is.character(sm)) {
      if (! sm %in% sm.methods)
        msg.stop.in("sm", sm.methods)
      sm.type <- "method"
    } else {
      msg.stop.na("sm")
    }
  } else {
    sm.type <- "none"
  }

  # prox
  # prox.type: "none", "matrix"
  if (!is.null(prox)) {
    if (is.matrix(prox)) {
      prox.type <- "matrix"
    } else {
      msg.stop.na("prox")
    }
  } else {
    prox.type <- "none"
  }

  # link
  # Add here new link method names
  links <- c("none", "mean", "gmean")
  if (! link %in% links)
    msg.stop.in("link", links)

  # step
  if (!is.a.positive.integer(step))
    msg.stop("'step' must be a positive integer")

  #### Check arguments not yet implemented ####

  # method
  if (sm.type == "method" && sm %in% c("INDELS", "INDELSLOG") && method == "DHD")
    msg.stop.impl("sm", method, values = c("INDELS", "INDELSLOG")) # See seqcost()

  # refseq
  if (refseq.type != "none" && method %in% c("OMstran", "CHI2", "EUCLID"))
    msg.stop.impl("refseq", method)
  if (refseq.type == "sequence" && ! method %in% c("OM", "HAM", "DHD", "LCS", "LCP", "RLCP"))
    msg.stop.impl("refseq", method, when = "it's an external sequence object")

  # norm
  if (norm != "none" && ! method %in% c("OM", "HAM", "DHD", "CHI2", "EUCLID", "LCS", "LCP", "RLCP"))
    msg.stop.impl("norm", method)

  #### Check method specific arguments ####

  # OMloc, OMspell
  if (method %in% c("OMloc", "OMspell") && expcost < 0)
    msg.stop("'expcost' must be positive")

  # OMloc
  if (method == "OMloc") {
    if (missing(context)) {
      context <- 1 - 2 * expcost # Does not work in the function declaration
      msg("context set to 1 - 2 * expcost =", context)
    }
    if (context < 0)
      msg.stop("'context' must be positive ('expcost' must be in [0, 0.5])")
    msg("2 * expcost + context =", 2 * expcost + context)
  }
  # OMslen
  else if (method == "OMslen") {
    if (isTRUE(with.missing))
      msg.stop("'with.missing' is not supported for OMslen")
    if (link == "none")
      msg.stop.miss("link")
    if (! link %in% c("mean", "gmean"))
      msg.stop.na("link")
    # According to Marteau, we should have h >= 0
    if (!is.a.number(h) || h < 0)
      msg.stop("'h' must be a number greater than or equal to 0")
  }
  # OMstran
  else if (method == "OMstran") {
    if (isTRUE(with.missing))
      msg.stop("'with.missing' is not supported for OMstran")
    if (missing(otto))
      msg.stop.miss("otto")
    else if (!is.a.number(otto) || otto < 0 || otto > 1)
      msg.stop("'otto' must be a number in [0, 1]")
    # TODO Implement in future versions
    if (length(seqs.dlens) > 1)
      msg.stop(method, "currently works only with sequences of equal length")
  }
  # DHD
  else if (method == "DHD") {
    if (sm.type == "method" && sm == "CONSTANT")
      msg.stop("'sm = \"CONSTANT\"' isn't relevant for DHD, consider HAM instead")
  }
  # CHI2 + EUCLID
  else if (method %in% c("CHI2", "EUCLID")) {
    if (! norm %in% c("auto", "none"))
      msg.stop.na("norm")
    if (!is.null(breaks)) {
      msg.warn.ign2("step", "breaks")
      msg.warn.ign2("overlap", "breaks")
    } else if (isTRUE(overlap) && step %% 2 != 0) {
      msg.stop("'step' must be even when 'overlap = TRUE'")
    }
  }
  # NMS + NMSMST + SVRspell
  else if (method %in% c("NMS", "NMSMST", "SVRspell")) {
    if (!is.vector(kweights, mode = "numeric") || any(kweights < 0))
      msg.stop("'kweights' must be a vector of positive numbers")
  }
  # TWED
  else if (method == "TWED") {
    if (missing(nu))
      msg.stop.miss("nu")
    # According to Marteau, we should have h >= 0 and nu > 0
    if (!is.a.number(h) || h < 0)
      msg.stop("'h' must be a number greater than or equal to 0")
    if (!is.a.number(nu) || nu <= 0)
      msg.stop("'nu' must be a number strictly greater than 0")
  }

  # HAM, DHD
  if (method %in% c("HAM", "DHD")) {
    if (length(seqs.dlens) > 1)
      msg.stop(method, "is not defined for sequence of different length")
  }

  # NMS, SVRspell
  if (method %in% c("NMS", "SVRspell") && sm.type != "none")
    msg.stop("use 'prox' instead of 'sm'")

  # OMloc, OMslen, OMspell, HAM, DHD, CHI2, EUCLID, LCS, LCP, RLCP, NMS, NMSMST, SVRspell, TWED
  if (! method %in% c("OM", "OMstran") && indel.type == "vector")
    msg.stop("'indel' must be a single state-independent indel cost")

  #### Configure norm ####

  if (norm == "auto") {
    if (method %in% c("OM", "HAM", "DHD"))
      norm <- "maxlength"
    else if (method %in% c("LCS", "LCP", "RLCP"))
      norm <- "gmean"
    else if (! method %in% c("CHI2", "EUCLID"))
      msg.stop.ie("no known normalization method to select automatically for", method)
  }

  # Must be after checking the valid values of norm for CHI2 and EUCLID
  if (method %in% c("CHI2", "EUCLID"))
    norm.chi2euclid <- switch(norm, auto = TRUE, none = FALSE)

  #### Configure prox ####

  # NMS, SVRspell
  if (method %in% c("NMS", "SVRspell")) {
    if (prox.type == "matrix") {
      if (nrow(prox) != nstates || ncol(prox) != nstates)
        msg.stop("'prox' must be of size", nstates, "x", nstates)
      eg <- eigen(prox)
      if (any(eg$values < -tol))
        msg.warn("'prox' is not positive semi-definite. Eigen values: ",
          paste(round(eg$values, 3), collapse = " "))
      rm(eg)
    } else if (prox.type == "none") {
      if (method == "SVRspell") {
        # Autogenerate prox (neutral)
        msg("creating a neutral 'prox' (identity matrix)")
        prox.type <- "matrix"
        prox <- diag(nstates)
      }
    } else {
      msg.stop.miss("prox")
    }
  }

  #### Configure sm ####

  # LCS
  if (method == "LCS") {
    # Autogenerate sm
    msg("creating a 'sm' with a substitution cost of 2")
    sm.type <- "matrix"
    sm <- seqsubm(seqdata, "CONSTANT", with.missing, cval = 2, miss.cost = 2)
  }
  # OM, OMloc, OMslen, OMspell, OMstran, HAM, DHD, TWED
  else if (method %in% c(om.methods, "HAM", "DHD", "TWED")) {
    # matrix
    if (sm.type == "matrix") {
      if (method %in% c(om.methods, "TWED"))
        checkcost(sm, seqdata, with.missing, indel)
      else if (method == "HAM")
        checkcost(sm, seqdata, with.missing)
      else
        msg.stop.na("sm")
    }
    # array
    else if (sm.type == "array") {
      if (method == "DHD")
        checkcost(sm, seqdata, with.missing)
      else
        msg.stop.na("sm")
    }
    # method
    else if (sm.type == "method") {
      if (sm %in% c("INDELS", "INDELSLOG")) {
        cost <- NULL
        tv <- FALSE
      } else if (sm == "TRATE") {
        if (method == "OM") {
          cost <- 2
          tv <- FALSE
        } else if (method == "HAM") {
          cost <- 2
          tv <- FALSE
        } else if (method == "DHD") {
          cost <- 4
          tv <- TRUE
          #sm.type <- "array" # Not used. Should be here if it changes.
        } else {
          msg.stop.na("sm")
        }
      } else if (sm == "CONSTANT") {
        if (method == "OM") {
          cost <- 2
          tv <- FALSE
        } else if (method == "HAM") {
          cost <- 1
          tv <- FALSE
        } else {
          msg.stop.na("sm")
        }
      } else {
        msg.stop.na("sm")
      }
      sm <- seqsubm(seqdata, sm, with.missing, cval = cost, miss.cost = cost, time.varying = tv)
      rm(cost)
      rm(tv)
    }
    # none
    else {
      if (method == "HAM") {
        # Autogenerate sm
        msg("creating a 'sm' with a single substitution cost of 1")
        sm <- seqsubm(seqdata, "CONSTANT", with.missing, cval = 1, miss.cost = 1)
      } else if (method == "DHD") {
        # Autogenerate sm
        msg("creating a 'sm' with the costs derived from the transition rates")
        #sm.type <- "array" # Not used. Should be here if it changes.
        sm <- seqsubm(seqdata, "TRATE", with.missing, cval = 4, miss.cost = 4, time.varying = TRUE)
      } else {
        msg.stop.miss("sm")
      }
    }
  } # CHI2, EUCLID, LCP, RLCP, NMS, NMSMST, SVRspell do not use sm
  else if (! method %in% c("CHI2", "EUCLID", "LCP", "RLCP", "NMS", "NMSMST", "SVRspell")) {
    msg.stop.ie("no known 'sm' preparation for", method)
  }

  #### Pre-process data (part 1/2) ####

  # TODO Temporary fix because seqdist2 C++ code use a sequence index, not a sequence object!
  if (refseq.type == "sequence") {
    seqs.lens.max <- max(seqs.dlens)
    refseq.len <- seqlength(refseq)[1, 1]
    refseq.mat <- as.matrix(refseq)
    if (refseq.len > seqs.lens.max)
      msg.stop("'refseq' must have a length less than or equal to the maximum 'seqdata' sequences length")
    if (refseq.len < seqs.lens.max) {
      void <- attr(seqdata, "void")
      refseq.mat.ext <- matrix(void, nrow = 1, ncol = seqs.lens.max)
      for (i in 1:refseq.len)
        refseq.mat.ext[i] <- refseq.mat[i]
      refseq.mat <- refseq.mat.ext
    }
    # Tell seqdef() that the seqdata.nr/refseq.nr code is the one for missing values
    seqdata <- suppressMessages(seqdef(rbind(as.matrix(seqdata), refseq.mat), alphabet=alphabet(seqdata), missing = seqdata.nr))
  }

  # Transform the alphabet into numbers
  seqdata.num <- seqnum(seqdata, with.missing)

  # Keep only distinct sequences
  dseqs.num <- unique(seqdata.num)
  # Check that dseqs.num does not exceed the max allowed
  max.allowed.seq <- floor(sqrt(.Machine$integer.max))
  if (nrow(dseqs.num) > max.allowed.seq){
    msg.stop(nrow(dseqs.num), " unique sequences exceeds max allowed of ", max.allowed.seq)
  }

  #### Handle reference sequence ####

  # Find the index of the corresponding representative (distinct) sequence
  # Note: Must be before dseqs.num modification for OMspell, NMSMST, SVRspell
  seqdata.didxs <- match(seqconc(seqdata.num), seqconc(dseqs.num))

  if (refseq.type != "none") {
    # sequence
    if (refseq.type == "sequence") {
      # TODO Temporary fix because seqdist2 C++ code use a sequence index, not a sequence object!
      refseq.raw <- refseq
      refseq.id <- seqdata.didxs[nseqs + 1]
    }
    # most frequent
    else if (refseq.type == "most frequent") {
      mfseq.freq <- seqtab(seqdata.num, idxs = 1)
      mfseq.idxs <- suppressMessages(seqfind(mfseq.freq, seqdata.num))
      msg("the most frequent sequence appears", length(mfseq.idxs), "time(s)")
      mfseq.idx <- mfseq.idxs[1]
      refseq.raw <- seqdata[mfseq.idx, ]
      refseq.id <- seqdata.didxs[mfseq.idx]
      rm(mfseq.freq)
      rm(mfseq.idxs)
      rm(mfseq.idx)
    }
    # index
    else if (refseq.type == "index") {
      refseq.raw <- seqdata[refseq, ]
      refseq.id <- seqdata.didxs[refseq]
    }
    else {
      msg.stop.ie("no known preparation for this 'refseq' type")
    }
    refseq.sps <- suppressMessages(seqformat(refseq.raw, from = "STS", to = "SPS", compress = TRUE))
    msg("using reference sequence", refseq.sps)
    rm(refseq.raw)
    rm(refseq.sps)
  }

  #### Compute method specific values ####

  # OMslen
  if (method == "OMslen") {
    dseqs.dur <- seqdur(dseqs.num)
    dur.mat <- matrix(0, nrow = nrow(dseqs.num), ncol = ncol(dseqs.num))
    for (i in 1:nrow(dseqs.num)) {
      y <- dseqs.dur[i, !is.na(dseqs.dur[i, ])]
      dur.mat[i, 1:sum(y)] <- rep(y, times = y)
    }
    dur.mat <- dur.mat ^ (-1 * h)
    rm(dseqs.dur)
    rm(y)
  }
  # OMspell, NMSMST (part 1/2), SVRspell (part 1/2)
  # Redefined dseqs.num
  else if (method %in% c("OMspell", "NMSMST", "SVRspell")) {
    dseqs.dur <- seqdur(seqdata, with.missing) ^ tpow # Do not use dseqs.num
    dseqs.oidxs <- match(seqconc(dseqs.num), seqconc(seqdata.num))
    c <- if (method == "OMspell") 1 else 0
    dseqs.dur <- dseqs.dur[dseqs.oidxs, ] - c
    seqdata.dss <- seqdss(seqdata, with.missing)
    dseqs.num <- seqnum(seqdata.dss[dseqs.oidxs, ], with.missing)
    rm(dseqs.oidxs)
    rm(c)
    rm(seqdata.dss)
  }
  # HAM, DHD
  else if (method %in% c("HAM", "DHD")) {
    if (method == "HAM")
      #sm.type <- "array" # Not used. Should be here if it changes.
      sm <- adaptSmForHAM(sm, nstates, ncol(seqdata))
    # Maximum possible cost of the Hamming distance
    max.cost <- 0
    for (i in 1:max(seqs.dlens))
      max.cost <- max.cost + max(sm[, , i])
  }

  # NMS, NMSMST (part 2/2), SVRspell (part 2/2)
  # Modified dseqs.num for NMSMST and SVRspell
  if (method %in% c("NMS", "NMSMST", "SVRspell")) {
    ncols <- ncol(dseqs.num)
    nmin <- min(ncols, length(kweights))
    kweights2 <- double(ncols)
    kweights2[1:nmin] <- kweights[1:nmin]
    rm(ncols)
    rm(nmin)
  }

  rm(seqdata.num)

  #### Pre-process data (part 2/2) ####

  # Modified dseqs.num for OMspell, NMSMST, SVRspell
  dn <- nrow(dseqs.num)
  # TODO Temporary fix because seqdist2 C++ code use a sequence index, not a sequence object!
  ndn <- if (refseq.type == "sequence") dn-1 else dn
  seq.or.spell <- if (method %in% c("OMspell", "SVRspell")) "spells" else "sequences"
  msg(ndn, "distinct", seq.or.spell)
  rm(dn)
  rm(ndn)
  rm(seq.or.spell)

  # Compute the sequence lengths
  # Modified dseqs.num for OMspell, NMSMST, SVRspell
  dseqs.lens <- seqlength(dseqs.num)
  ds <- if (method %in% c("OMspell", "NMSMST", "SVRspell")) "distinct states " else ""
  # TODO Temporary fix because seqdist2 C++ code use a sequence index, not a sequence object!
  dl <- if (refseq.type == "sequence") dseqs.lens[-length(dseqs.lens)] else dseqs.lens
  msg0("min/max ", ds, "sequence length: ", min(dl), "/", max(dl))
  rm(ds)
  rm(dl)

  #### Configure params ####

  params <- list()
  nstates <- as.integer(nstates)

  # OM
  if (method == "OM") {
    params[["alphasize"]] <- nstates
    params[["scost"]] <- sm

    if (indel.type == "number") {
      params[["indel"]] <- indel
    } else if (indel.type == "vector") {
      # Also executed when 'method = "OMstran"' (no matter the type of 'indel')
      params[["indels"]] <- indel
      params[["indelmethod"]] <- as.integer(0)
      params[["indel"]] <- 0 # TODO Remove from C++ code. Not used. Avoid a NPE.
    } else {
      msg.stop.ie("no known configuration for this 'indel' type for OM")
    }
  }
  # OMloc
  else if (method == "OMloc") {
    params[["alphasize"]] <- nstates
    params[["indel"]] <- max(sm) * (expcost + context)
    params[["indelmethod"]] <- as.integer(1)
    params[["scost"]] <- sm
    params[["localcost"]] <- context
    params[["timecost"]] <- expcost
  }
  # OMslen
  else if (method == "OMslen") {
    params[["alphasize"]] <- nstates
    params[["indel"]] <- indel
    params[["seqdur"]] <- as.double(dur.mat)

    if (link == "mean") {
      params[["scost"]] <- sm / 2
      params[["sublink"]] <- as.integer(1)
    } else if (link == "gmean") {
      params[["scost"]] <- sm
      params[["sublink"]] <- as.integer(0)
    } else {
      msg.stop.ie("no known configuration for this 'link' value for OMslen")
    }

    rm(dur.mat)
  }
  # OMspell
  else if (method == "OMspell") {
    params[["alphasize"]] <- nstates
    params[["indel"]] <- indel
    params[["scost"]] <- sm
    params[["seqdur"]] <- as.double(dseqs.dur)
    params[["timecost"]] <- expcost
    rm(dseqs.dur)
  }
  # HAM + DHD
  else if (method %in% c("HAM", "DHD")) {
    params[["alphasize"]] <- nstates
    params[["maxdist"]] <- max.cost
    params[["scost"]] <- sm
    rm(max.cost)
  }
  # LCS
  else if (method == "LCS") {
    params[["alphasize"]] <- nstates
    params[["indel"]] <- 1
    params[["scost"]] <- sm
  }
  # LCP
  else if (method == "LCP") {
    params[["sign"]] <- as.integer(1)
  }
  # RLCP
  else if (method == "RLCP") {
    params[["sign"]] <- as.integer(-1)
  }
  # NMS + NMSMST + SVRspell
  else if (method %in% c("NMS", "NMSMST", "SVRspell")) {
    params[["distMethod"]] <- as.integer(2)
    params[["distTransform"]] <- as.integer(0) # TODO Remove from C++ code
    params[["kweights"]] <- as.double(kweights2)

    if (method != "NMS") {
      params[["seqdur"]] <- as.double(dseqs.dur)
      rm(dseqs.dur)
    }

    if (method != "NMSMST" && prox.type == "matrix") {
      params[["alphasize"]] <- nstates
      params[["softmatch"]] <- prox
    }
  }
  # TWED
  else if (method == "TWED") {
    params[["alphasize"]] <- nstates
    params[["indel"]] <- indel
    params[["lambda"]] <- h
    params[["nu"]] <- nu
    params[["scost"]] <- sm
  }

  #### Configure method.num ####

  # TODO Assign a number after integration with C++ code for OMstran, CHI2, EUCLID
  method.num <-
    switch(method,
      OM = if (indel.type == "vector") 7 else 1, # TODO Align C++ logic with the theory
      OMloc = 7,
      OMslen = 10,
      OMspell = 8,
      #OMstran = ,
      HAM = 4,
      DHD = 4,
      #CHI2 = ,
      #EUCLID = ,
      LCS = 1,
      LCP = 2,
      RLCP = 2,
      NMS = if (prox.type == "matrix") 12 else 5,
      NMSMST = 6,
      SVRspell = 13,
      TWED = 14)

  # Transform the sequence object into a matrix
  # Modified dseqs.num for OMspell, NMSMST, SVRspell
  dseqs.mat <- seqasnum(dseqs.num, with.missing)

  rm(dseqs.num)

  #### Compute distances ####

  nm <- if (norm != "none") " normalized" else ""
  msg0("computing distances using the ", method, nm, " metric")
  rm(nm)

  # CHI2, EUCLID
  if (method %in% c("CHI2", "EUCLID")) {
    # TODO Integrate into C++ code instead of using CHI2()
    is.EUCLID <- if (method == "EUCLID") TRUE else FALSE
    distances <- CHI2(seqdata, breaks = breaks, step = step,
      with.missing = with.missing, norm = norm.chi2euclid,  weighted = weighted,
      overlap = overlap, euclid = is.EUCLID)
    result <- if (full.matrix) dist2matrix(distances) else distances
  }
  # OMstran
  else if (method == "OMstran") {
    # TODO Integrate into C++ code instead of using OMstran()
    # OMstran() calls seqdist() with 'method = "OM"'
    distances <- OMstran(seqdata, indel = indel, sm = sm,
      full.matrix = full.matrix, transindel = transindel, otto = otto,
      previous = previous, add.column = add.column, weighted = weighted)
    result <- distances
  }
  # Other methods
  else {
    #  Preparation for C code
    method.num <- as.integer(method.num)
    norm.num <- as.integer(match(norm, norms[-1]) - 1) # Starts at zero
    dseqs.mat.vect <- as.integer(dseqs.mat)
    dseqs.mat.dim <- as.integer(dim(dseqs.mat))
    dseqs.lens.vect <- as.integer(dseqs.lens)

    # Dissimilarities with a reference sequence
    if (refseq.type != "none") {
      distances <- .Call(C_cstringrefseqdistance, dseqs.mat.vect, dseqs.mat.dim,
        dseqs.lens.vect, params, norm.num, method.num, as.integer(refseq.id))

      result <- distances[seqdata.didxs]
      names(result) <- NULL

      # TODO Temporary fix because seqdist2 C++ code use a sequence index, not a sequence object!
      if (refseq.type == "sequence")
        result <- result[-length(result)]
    }
    # Pairwise dissimilarities between sequences
    else {
      magic.idxs <- as.integer(c(unique(rank(seqdata.didxs, ties.method = "min")) - 1, nseqs))
      magic.seqs <- as.integer(order(seqdata.didxs))

      distances <- .Call(C_cstringdistance, dseqs.mat.vect, dseqs.mat.dim,
        dseqs.lens.vect, params, norm.num, magic.idxs, magic.seqs, method.num)

      # TODO Integrate into C++ code
      if (method %in% c("NMS", "NMSMST", "SVRspell"))
        distances <- sqrt(distances)

      # Attributes for the dist object
      class(distances) <- "dist"
      attr(distances, "Size") <- length(magic.seqs)
      attr(distances, "Labels") <- dimnames(seqdata)[[1]]
      attr(distances, "Diag") <- FALSE
      attr(distances, "Upper") <- FALSE
      attr(distances, "method") <- method

      result <- if (full.matrix) dist2matrix(distances) else distances
    }
  }

  #### Display elaspsed time ####

  ptime.end <- proc.time()
  time.begin <- as.POSIXct(sum(ptime.begin[1:2]), origin = "1960-01-01")
  time.end <- as.POSIXct(sum(ptime.end[1:2]), origin = "1960-01-01")
  time.elapsed <- format(round(difftime(time.end, time.begin), 3))

  msg("elapsed time:", time.elapsed)

  return(result)
}



# Adapt 'sm' for HAM (implementation requirement).
adaptSmForHAM <- function(sm, nstates, ncols) {
  costs <- array(0, dim = c(nstates, nstates, ncols))
  for (i in 1:ncols)
    costs[, , i] <- sm
  return(costs)
}
