#' @title TimsTOF data backend
#'
#' @name MsBackendTimsTof
#'
#' @aliases MsBackendTimsTof MsBackendTimsTof-class
#'
#' @description
#'
#' The `MsBackendTimsTof` class supports Bruker TimsTOF data files. New objects
#' are created with the `MsBackendTimsTof` function. To ensure a small memory
#' footprint, only general information is kept in memory (such as number of
#' frames and scans) and all data (specifically the peaks data) is retrieved
#' from the original file on-the-fly.
#'
#' @section Available methods:
#'
#' The following methods are implemented:
#'
#' - `$`: access any of the `spectraVariables` of the backend.
#'
#' - `[`: subset the backend. Only subsetting by element (*row*/`i`) is
#'   allowed. First the `@indices` slot of `object` is subsetted and then the
#'   `frames` and `fileNames` slots are subsetted accordingly. Note that `[`
#'   does not update the values of `frames` variables (such as `"MaxIntensity"`,
#'   `"SummedIntensities"`, `"NumScans"` and `"NumPeaks"`).
#'
#' - `backendInitialize`: initializes `object` (the `MsBackendTimsTof` object)
#'   using TimsTOF data files whose path is specified by `files`. This method
#'   is supposed to be called right after creating a `MsBackendTimsTof` object
#'   with `MsBackendTimsTof` function.
#'
#' - `dataStorage`: gets a `character` of length equal to the number of spectra
#'   in `object` with the names of the '*.d' folders where each spectrum is
#'   stored.
#'
#' - `intensity`: gets the intensity values from the spectra in the backend.
#'   Returns a [NumericList()] of `numeric` vectors (intensity values for each
#'   spectrum). The length of the list is equal to the number of
#'   spectra in `object`.
#'
#' - `msLevel`: gets the spectra MS level. Returns an integer vector (of length
#'    equal to the number of spectra) with the MS level for each spectrum.
#'
#' - `mz`: gets the mass-to-charge ratios (m/z) from the spectra in the backend.
#'   Returns a [NumericList()] of `numeric` vectors (m/z values for each
#'   spectrum). The length of the list is equal to the number of spectra in
#'   `object`.
#'
#' - `peaksData`: gets the peak matrices of the spectra in the backend.
#'   Returns a `list` of `matrix` with columns defined by parameter `columns`
#'   (which defaults to `columns = c("mz", "intensity")`. Use `peaksVariables`
#'   to list all supported and available columns for a backend.
#'   The length of the `list` is equal to the number of spectra in `object`.
#'
#' - `peaksVariables`: gets the supported peak variables (columns) for the
#'   backend.
#'
#' - `rtime`: gets the retention times for each spectrum. Returns a `numeric`
#'   vector (length equal to the number of spectra) with the retention time
#'   for each spectrum.
#'
#' - `spectraData`: gets spectra variables (specified by `columns`) from
#'   `object`.
#'
#' - `spectraVariables`: returns a `character` vector with the spectra variables
#'   names of core spectra variables defined in the Spectra package and other
#'   additional variables contained in `object`. Note that also `"mz"` and
#'   `"intensity"` (which are by default not returned by the
#'   `spectraVariables,Spectra` method) are returned.
#'
#' @param BPPARAM Parameter object defining the parallel processing
#'   setup to import data in parallel. Defaults to `BPPARAM = bpparam()`.
#'   See [bpparam()] for more information.
#'
#' @param columns For `spectraData`: names of the spectra variables to extract
#'   from `object`. For `peaksData`: names of the peak variables to extract.
#'   Defaults to `columns = c("mz", "intensity")`.
#'
#' @param drop For `[`: not considered.
#'
#' @param files `character` specifying TimsTOF ’*.d’ folders names.
#'
#' @param i For `[`: `integer`, `logical` to subset the object.
#'
#' @param j For `[`: not supported.
#'
#' @param name For `$`: the name of the variable to access.
#'
#' @param object `MsBackendTimsTof` object.
#'
#' @param x `MsBackendTimsTof` object.
#'
#' @param ... Additional arguments.
#'
#' @author Andrea Vicini, Johannes Rainer
#'
#' @rdname MsBackendTimsTof
#'
#' @exportClass MsBackendTimsTof
#' 
#' @examples
#'
#' ## Load the opentimsr package to retrieve the required shared library
#' ## from Bruker.
#' so_folder <- tempdir()
#' library(opentimsr)
#' so_file <- download_bruker_proprietary_code(so_folder, method = "wget")
#' setup_bruker_so(so_file)
#' path_d_folder <- system.file("ddaPASEF.d",
#'                              package = "MsBackendTimsTof")
#'
#' ## Define the test file
#' fl <- system.file("ddaPASEF.d", package = "MsBackendTimsTof")
#'
#' ## Create a MsBackend instance for that file
#' be <- backendInitialize(MsBackendTimsTof(), fl)
#' be
#'
#' ## Available spectra variables
#' spectraVariables(be)
#'
#' ## Subset to 10 randomly selected spectra.
#' be_sub <- be[sort(sample(seq_along(be), 10))]
#' rtime(be_sub)
#'
#' pd <- peaksData(be_sub, columns = c("mz", "intensity", "tof", "inv_ion_mobility"))
setClass("MsBackendTimsTof",
         contains = "MsBackend",
         slots = c(frames = "data.frame",
                   indices = "matrix",
                   fileNames = "integer"),
         prototype = prototype(frames = data.frame(),
                               indices = matrix(nrow = 0, ncol = 3,
                                                dimnames = list(NULL,
                                                                c("frame",
                                                                  "scan",
                                                                  "file"))),
                               fileNames = integer(),
                               readonly = TRUE,
                               version = "0.1"))

#' @importFrom methods validObject
setValidity("MsBackendTimsTof", function(object) {
    msg <- .valid_fileNames(object@fileNames)
    msg <- c(msg, .valid_frames(object@frames))
    msg <- c(msg, .valid_indices(object))
    if (length(msg)) msg
    else TRUE
})

#' @importFrom BiocParallel bplapply
#'
#' @importMethodsFrom Spectra backendInitialize
#'
#' @rdname MsBackendTimsTof
setMethod("backendInitialize", signature = "MsBackendTimsTof",
          function(object, files, ..., BPPARAM = bpparam()) {
              if (missing(files) || !length(files))
                  stop("Parameter 'files' is mandatory for 'MsBackendMzR'")
              if (!is.character(files))
                  stop("Parameter 'files' is expected to be a character vector",
                       " with the files names from where data should be",
                       " imported")
              files <- normalizePath(files, mustWork = FALSE)
              msg <- Spectra:::.valid_ms_backend_files_exist(files)
              if (length(msg))
                  stop(msg)
              object <- .initialize(object, files, BPPARAM)
              validObject(object)
              object
          })

#' @exportMethod length
#'
#' @rdname MsBackendTimsTof
setMethod("length", "MsBackendTimsTof", function(x) {
    nrow(x@indices)
})

#' @rdname MsBackendTimsTof
setMethod(
    "peaksData", "MsBackendTimsTof",
    function(object, columns = c("mz", "intensity")) {
        .get_tims_columns(object, columns)
})

#' @rdname MsBackendTimsTof
#'
#' @importMethodsFrom Spectra peaksVariables
setMethod(
    "peaksVariables", "MsBackendTimsTof",
    function(object) {
        if (length(object@fileNames)) {
            .list_tims_columns(names(object@fileNames)[1L])
        } else c("mz", "intensity")
})

#' @importFrom IRanges NumericList
#'
#' @rdname MsBackendTimsTof
setMethod("mz", "MsBackendTimsTof", function(object) {
    NumericList(.get_tims_columns(object, "mz"), compress = FALSE)
})

#' @importFrom IRanges NumericList
#'
#' @rdname MsBackendTimsTof
setMethod("intensity", "MsBackendTimsTof", function(object) {
    NumericList(.get_tims_columns(object, "intensity"), compress = FALSE)
})

#' @rdname MsBackendTimsTof
setMethod("rtime", "MsBackendTimsTof", function(object) {
    .get_frame_columns(object, "rtime")
})

#' @importFrom methods slot<-
#'
#' @importFrom MsCoreUtils i2index
#'
#' @rdname MsBackendTimsTof
setMethod("[", "MsBackendTimsTof", function(x, i, j, ..., drop = FALSE) {
    if (missing(i))
        return(x)
    i <- i2index(i, length(x))
    slot(x, "indices", check = FALSE) <- x@indices[i, , drop = FALSE]
    ff_indices <- paste(x@indices[, "frame"], x@indices[, "file"])
    slot(x, "frames", check = FALSE) <-
        x@frames[match(unique(ff_indices),
                       paste(x@frames$frameId, x@frames$file)), , drop = FALSE]
    slot(x, "fileNames", check = FALSE) <-
        x@fileNames[x@fileNames %in% unique(x@frames$file)]
    x
})

#' @importMethodsFrom Spectra dataStorage
#'
#' @rdname MsBackendTimsTof
setMethod("dataStorage", "MsBackendTimsTof", function(object) {
    if("file" %in% colnames(object@indices) && length(object@fileNames))
        return(names(object@fileNames[match(object@indices[, "file"],
                                            object@fileNames)]))
    character(0)
})

#' @importMethodsFrom Spectra spectraVariables
#'
#' @importFrom Spectra coreSpectraVariables
#'
#' @rdname MsBackendTimsTof
setMethod("spectraVariables", "MsBackendTimsTof", function(object) {
    unique(c(names(coreSpectraVariables()), .TIMSTOF_COLUMNS,
             colnames(object@frames)))
})

#' @importMethodsFrom Spectra spectraData
#'
#' @rdname MsBackendTimsTof
setMethod("spectraData", "MsBackendTimsTof",
          function(object, columns = spectraVariables(object)) {
              .spectra_data(object, columns)
          })

#' @importFrom utils capture.output
#'
#' @rdname MsBackendTimsTof
setMethod("show", "MsBackendTimsTof", function(object) {
    n <- length(object)
    cat(class(object), "with", n, "spectra\n")
    if (n) {
        idx <- unique(c(1L:min(6L, n), max(1L, n-5L):n))
        spd <- spectraData(object[idx, ],
                           c("msLevel", "precursorMz", "polarity"))
        if (!length(rownames(spd)))
            rownames(spd) <- idx
        txt <- capture.output(print(spd))
        cat(txt[-1], sep = "\n")
        sp_cols <- spectraVariables(object)
        cat(" ...", length(sp_cols) - 3, "more variables/columns.\n", "Use ",
            "'spectraVariables' to list all of them.\n")
    }
})

#' @importMethodsFrom Spectra msLevel
#'
#' @rdname MsBackendTimsTof
setMethod("msLevel", "MsBackendTimsTof", function(object, ...) {
    .get_msLevel(object)
})

#' @importMethodsFrom Spectra precursorMz
#'
#' @rdname MsBackendTimsTof
setMethod("precursorMz", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object, columns = "precursorMz")[[1]]
})

#' @importMethodsFrom Spectra precursorCharge
#'
#' @rdname MsBackendTimsTof
setMethod("precursorCharge", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object,
                                    columns = "precursorCharge")[[1]] |>
    as.integer()
})

#' @importMethodsFrom Spectra precursorIntensity
#'
#' @rdname MsBackendTimsTof
setMethod("precursorIntensity", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object,
                                    columns = "precursorIntensity")[[1]]
})

#' @importMethodsFrom Spectra collisionEnergy
#'
#' @rdname MsBackendTimsTof
setMethod("collisionEnergy", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object, columns = "collisionEnergy")[[1]]
})

#' @importMethodsFrom Spectra isolationWindowLowerMz
#'
#' @rdname MsBackendTimsTof
setMethod("isolationWindowLowerMz", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object, 
                                    columns = "isolationWindowLowerMz")[[1]]
})

#' @importMethodsFrom Spectra isolationWindowTargetMz
#'
#' @rdname MsBackendTimsTof
setMethod("isolationWindowTargetMz", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object, 
                                    columns = "isolationWindowTargetMz")[[1]]
})

#' @importMethodsFrom Spectra isolationWindowUpperMz
#'
#' @rdname MsBackendTimsTof
setMethod("isolationWindowUpperMz", "MsBackendTimsTof", function(object, ...) {
    .calculate_core_ms2_information(object,
                                    columns = "isolationWindowUpperMz")[[1]]
})

#' @rdname MsBackendTimsTof
setMethod("$", "MsBackendTimsTof", function(x, name) {
    if (!any(spectraVariables(x) == name))
        stop("spectra variable '", name, "' not available")
    if (name == "inv_ion_mobility")
        .inv_ion_mobility(x)
    else
        spectraData(x, name)[, 1L]
})

