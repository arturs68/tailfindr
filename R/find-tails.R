#' Finds poly(A)/(T) tail lengths in Oxford Nanopore RNA and DNA reads
#'
#' This function estimates poly(A) tail length in RNA reads, and both poly(A)
#' and poly(T) tail lengths in DNA reads. It can operate on base called
#' files generated from any version of Albacore and Guppy using either the
#' standard or the newest flip-flop model.
#'
#'
#'
#' The function can handle reads that
#' have been basecalled using the standard model or the flip-flop model.
#' Furthermore, it can also single and multi-fast5 files generated from all
#' versions of Albacore or Guppy. The function saves a CSV file containing all
#' the tail information, and also returns a tibble containing the same
#' information for further processing by the end-user. Currently, the algorithm
#' works only on 1D reads.
#'
#'
#'
#' @param fast5_dir character string. Full path of the directory to search the
#' fast5 files in. The direcotry is searched recursively.
#'
#' @param save_dir character string. Full path of the directory where the CSV
#' file containing the tail lengths should be stored. If save_plots is set to
#' \code{TRUE}, then plots showing the poly(A)/(T) tails are stored within the
#' \code{plots} directory within the \code{save_dir}. This \code{plots}
#' directory is created automatically.
#'
#' @param csv_filename character string [\code{"tails.csv"}]. Filename of the
#' CSV file in which to store the tail length data
#'
#' @param num_cores numeric [1]. Num of phyiscal cores to use in processing
#' the data. If you have 4 physical cores in the computer that you are using
#' tailfinder on, then use 3 for \code{num_cores}. Always use 1 less than the
#' number of cores at your disposal.
#'
#' @param save_plots logical [\code{FALSE}]. If set to \code{TRUE}, a plots
#' directory will be created within the save_dir, and plots showing poly(A) and
#' poly(T) tails on the raw squiggle will be saved in this \code{plots}
#' directory. Creating plots and saving them to the disk is a slow process. So
#' we recommend that you keep this option set to \code{FALSE}. If you still want
#' to create plots, we recommend that you run tailfinder on a subset of reads
#' with \code{save_plots} set to \code{TRUE}. Plots are automatically named by
#' concatenating read ID with the name of the Fast5 file containing this read;
#' the read ID and fast5 file name are separated by two underscores (__).
#'
#' @param plot_debug_traces logical [\code{FALSE}]. If set to \code{TRUE},
#' then we will plot debugging information in the plots as well, such as the
#' mean signal, the slope signal, the thresholds, the smoothened signal, etc.
#' We use this option internally to debug our algorithm. This option works only
#' if \code{save_plots} option is also set to \code{TRUE}.
#'
#' @param plotting_library character string [\code{"rbokeh"}]. \code{rbokeh}
#' is the default plotting library that we will use if \code{save_plots} is set
#' to \code{TRUE}. The plots will be saved as HTML files in
#' the \code{/save_dir/plots} directory. You can open these HTLM files in any
#' web-browser and interactively view the plots showing the tail region in the
#' raw squiggle. If this option is set to \code{'ggplot2'}, then the polts will
#' be saved as \code{.png} files.
#'
#' @param ... list. A list of optional parameters. This is currently, reserved
#' for internal use only. By default, DNA reads are assumed to be from a direct
#' cDNA or an amplified cDNA library. However, if the data is from a PCR DNA
#' library, then an additional parameter named \code{dna_datatype} should be
#' passed with its value set to \code{'pcr-dna'}. This will ensure that the
#' algorithm uses the correct adaptor sequences for the PCR DNA protocol.
#'
#' @return A data tibble is returned containing all the information
#' about the tails found. Always save this returned tibble in a variable (see
#' examples below), otherwise the very long tibble will be printed to the
#' console, which may hang up your R session.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' library(tailfinder)
#'
#' # 1. Suppose you have 11 cores at your disposal, then you should run tailfinder
#' # on your data as following:
#' df <- find_tails(fast5_dir = '/path/to/fast5/folder/',
#'                  save_dir = '/path/to/a/folder/where/results/are/to/be/stored/',
#'                  csv_filename = 'tails.csv',
#'                  num_cores = 10)
#'
#' # 2. If you also want to save the plots showing the tail on the raw
#' # squiggle using ggplot2 (plots will be save as .png files),
#' # then you should run tailfinder as following:
#' df <- find_tails(fast5_dir = '/path/to/fast5/folder/',
#'                  save_dir = '/path/to/a/folder/where/results/are/to/be/stored/',
#'                  csv_filename = 'tails.csv',
#'                  num_cores = 10,
#'                  save_plots = TRUE,
#'                  plotting_library = 'ggplot2')
#'
#' # 3. If you want to save interactive HTML plots using rbokeh,
#' # then you should run tailfinder as following:
#' df <- find_tails(fast5_dir = '/path/to/fast5/folder/',
#'                  save_dir = '/path/to/a/folder/where/results/are/to/be/stored/',
#'                  csv_filename = 'tails.csv',
#'                  num_cores = 10,
#'                  save_plots = TRUE,
#'                  plotting_library = 'rbokeh')
#'
#' # 4. If you also want to plot debug traces, then you should run tailfinder as
#' # below:
#' df <- find_tails(fast5_dir = '/path/to/fast5/folder/',
#'                  save_dir = '/path/to/a/folder/where/results/are/to/be/stored/',
#'                  csv_filename = 'tails.csv',
#'                  num_cores = 10,
#'                  save_plots = TRUE,
#'                  plot_debug_traces = TRUE,
#'                  plotting_library = 'rbokeh')
#'
#' # N.B.: Making and saving plots is a computationally slow process.
#' # Only generate plots by running tailfinder on a small subset of your reads.
#' }
#'
find_tails <- function(fast5_dir,
                       save_dir,
                       csv_filename = 'tails.csv',
                       num_cores = 1,
                       save_plots = FALSE,
                       plot_debug_traces = FALSE,
                       plotting_library = 'rbokeh',
                       ...) {

    plot_debug <- plot_debug_traces
    if (save_plots == FALSE) {
        plot_debug <- FALSE
    }
    # Taking out these parameter from the function parameters list
    # as they may be dangerous for normal users
    show_plots <- FALSE
    if (length(list(...)) > 0) {
        if ("dna_datatype" %in% names(...)) {
            dna_datatype <- ...$dna_datatype
        } else {
            # data parameter is used only when the experiment_type is dna
            dna_datatype <- 'cdna'
        }
    } else {
        dna_datatype <- 'cdna'
    }

    # start a log file
    if (dir.exists(file.path(save_dir))) {
        logfile_name <- paste(format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), "_tailfinder.log", sep = "")
        logfile_path <- file.path(save_dir, logfile_name, fsep = .Platform$file.sep)
        con <- file(logfile_path, open = "a")
        sink(con, append=TRUE, split = TRUE, type='output')
        on.exit(sink(file=NULL, type = 'output'))
    }

    # display console messages
    version <- packageDescription("tailfinder")$Version
    cat(cli::rule(left=''), '\n', sep = "")
    cat(cli::rule(left=paste("Started tailfinder ", '(version ', version, ')', sep='')), '\n', sep = "")
    cat(cli::rule(left=''), '\n',  sep = "")

    # display the user-specified parameters
    cat(paste(clisymbols::symbol$menu, ' You have configured tailfinder as following:', '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' fast5_dir:         ', fast5_dir, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' save_dir:          ', save_dir, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' csv_filename:      ', csv_filename, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' num_cores:         ', num_cores, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' save_plots:        ', save_plots, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' plot_debug_traces: ', plot_debug_traces, '\n', sep=''))
    cat(paste(clisymbols::symbol$pointer, ' plotting_library:  ', plotting_library, '\n', sep=''))
    if (dna_datatype == 'pcr-dna'){
        cat(paste(clisymbols::symbol$pointer, ' dna_datatype:      ', dna_datatype, '\n', sep=''))
    }

    cat(cli::rule(left=paste('Processing started at ', Sys.time(), sep = '')), '\n', sep = "")

    # Try to create the save directory
    if (!dir.exists(file.path(save_dir))) {
        cat(paste(clisymbols::symbol$bullet, ' Save dir does not exist. Trying to create it...\n', sep=''))
        tryCatch({
            dir.create(file.path(save_dir, fsep = .Platform$file.sep))
            cat('  Done!\n')
        },
        error=function(e){
            cat(paste(clisymbols::symbol$bullet, ' Failed to create the save dir. Results will be stored in the "~/" directory instead.\n', sep=''))
            save_dir <- '~/'
        })
        logfile_name <- paste(format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), "_tailfinder.log", sep = "")
        logfile_path <- file.path(save_dir, logfile_name, fsep = .Platform$file.sep)
        con <- file(logfile_path, open = "a")
        sink(con, append=TRUE, split = TRUE, type='output')
        on.exit(sink(file=NULL, type = 'output'))
    }

    # Create a sub-direcotry to save all the plots
    plots_dir <- file.path(save_dir, 'plots', fsep = .Platform$file.sep)
    if (save_plots & !dir.exists(file.path(plots_dir))){
        cat(paste(clisymbols::symbol$bullet, ' Creating a sub-directory to save the plots in.\n', sep=''))
        dir.create(plots_dir)
        cat('  Done! All plots will be saved in the following direcotry:\n')
        cat(paste('  ', file.path(save_dir, 'plots', fsep = .Platform$file.sep), '\n', sep = ''))
    }

    # search for all the fast5 files in the user-specified directory
    cat(paste(clisymbols::symbol$bullet,' Searching for all Fast5 files...\n', sep=''))
    fast5_files_list <- list.files(path = fast5_dir,
                                   pattern = "\\.fast5$",
                                   recursive = TRUE,
                                   full.names = TRUE)
    num_files <- length(fast5_files_list)
    cat(paste0('  Done! Found ', num_files, ' Fast5 files.\n'))

    # read the first read in the list of reads,
    # and determine all the properties of the data
    cat(paste(clisymbols::symbol$bullet,' Analyzing a single Fast5 file to assess if your data \n', sep=''))
    cat('  is in an acceptable format...\n')

    type_info <- explore_basecaller_and_fast5type(fast5_files_list[1])
    basecalled_with <- type_info$basecalled_with
    multifast5 <- ifelse(type_info$fast5type == 'multi', TRUE, FALSE)
    experiment_type <- type_info$experiment_type
    read_is_1d <- type_info$read_is_1d
    model <- type_info$model
    if (basecalled_with == 'albacore'){
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The data has been basecalled using Albacore.\n', sep=''))
    } else {
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The data has been basecalled using Guppy.\n', sep=''))
    }
    if (model == 'flipflop'){
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' Flipflop model was used during basecalling.\n', sep=''))
    } else {
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' Standard model was used during basecalling.\n', sep=''))
    }
    if (multifast5){
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The reads are packed in multi-fast5 file(s).\n', sep=''))
    } else {
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' Every read is in a single fast5 file of its own.\n', sep=''))
    }
    if (experiment_type == 'rna'){
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The experiment type is RNA, so we will search\n', sep=''))
        cat('    for poly(A) tails.\n')
    } else {
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The experiment type is DNA, so we will search\n', sep=''))
        cat('    for both poly(A) and poly(T) tails.\n')
    }
    if (read_is_1d == TRUE){
        cat(paste('  ', crayon::green(clisymbols::symbol$tick),
                  ' The reads are 1D reads.\n', sep=''))
    } else {
        cat(paste('  ', crayon::red(clisymbols::symbol$cross),
                  ' The reads are not 1D. Currently, we only support\n', sep=''))
        cat('    1D reads. If you believe your reads are 1D, and you are\n')
        cat('    getting this cat erroneously, please feel free\n')
        cat('    to contact us at adnan.niazi@uib.no. Do not forget to\n')
        cat('    send us one of the problematic reads so that we can\n')
        cat('    debug our software, and send you a patch.\n')
        cat(paste('  ', crayon::red(clisymbols::symbol$cross),'
                  Finished because of the error!\n', sep=''))
        cat(cli::rule(left=paste('tailfinder finished with a fatal error at ',
                                 Sys.time(), sep = '')), '\n', sep = "")
        return(0)
    }

    # Make a computer cluster
    cat(paste(clisymbols::symbol$bullet,' Starting a parallel compute cluster...\n', sep=''))
    #cl <- parallel::makeCluster(num_cores, outfile='')
    cl <- parallel::makeCluster(num_cores)
    on.exit(parallel::stopCluster(cl))

    doSNOW::registerDoSNOW(cl)
    `%dopar%` <- foreach::`%dopar%`
    `%do%` <- foreach::`%do%`
    cat('  Done!\n')
    mcoptions <- list(preschedule = TRUE, set.seed = FALSE, cleanup = FALSE)

    # if the data is DNA then make a substitution matrix
    if (experiment_type == 'dna') {
        match <- 1
        mismatch <- -1
        type <-'local'
        gapOpening <- 0
        gapExtension <- 1
        submat <- Biostrings::nucleotideSubstitutionMatrix(match = match,
                                                           mismatch = mismatch,
                                                           baseOnly = TRUE)
        dna_opts <- list(match = match,
                         mismatch = mismatch,
                         type = type,
                         gapOpening = gapOpening,
                         gapExtension = gapExtension,
                         submat = submat)
    }

    # If the fast5 are multifast5, then build an index of all the reads within these files
    remove_last_duplicate_read <- FALSE
    if (multifast5) {
        cat(paste(clisymbols::symbol$bullet, ' Discovering reads in the ',
                  num_files, ' multifast5 files...\n', sep=''))
        read_id_fast5_file <- dplyr::tibble(read_id = character(),
                                            fast5_file = character())
        for (fast5_file in fast5_files_list) {
            f5_obj <- hdf5r::H5File$new(fast5_file, mode = 'r')
            f5_tree <- f5_obj$ls(recursive = F)
            f5_tree <- f5_tree$name
            f5_tree <- dplyr::mutate(dplyr::tbl_df(f5_tree), fast5_file = fast5_file)
            f5_tree <- dplyr::rename(f5_tree, read_id = value)
            read_id_fast5_file <- rbind(read_id_fast5_file, f5_tree)
            f5_obj$close_all()
        }
        cat(paste0('  Done! Found ', nrow(read_id_fast5_file), ' reads\n'))
        # convert the data frame to list with rows as elements of the list
        read_id_fast5_file <- split(read_id_fast5_file, seq(nrow(read_id_fast5_file)))

        # Split the data into chunks
        files_per_chunk <- 4000
        total_files <- length(read_id_fast5_file)
        total_chunks <- ceiling(total_files/files_per_chunk)

        #loop
        if (experiment_type == 'dna') {
            cat(paste(clisymbols::symbol$bullet,
                      ' Searching for Poly(A) and Poly(T) tails...\n', sep=''))
        } else {
            cat(paste(clisymbols::symbol$bullet,
                      ' Searching for Poly(A) tails...\n', sep=''))
        }
        counter <- 0
        result <- list()
        for(chunk in c(1:total_chunks)){
            # divide data in chunks
            if(chunk == total_chunks) {
                read_id_fast5_file_subset <-
                    read_id_fast5_file[((counter*files_per_chunk)+1):total_files]
                # if the last chunk has only one read then just duplicate this
                # one read so that the progressbar works, and does not throw an error
                if (length(read_id_fast5_file_subset) == 1) {
                    read_id_fast5_file_subset[[2]] <- read_id_fast5_file_subset
                    remove_last_duplicate_read <- TRUE
                }
            } else {
                read_id_fast5_file_subset <-
                    read_id_fast5_file[((counter*files_per_chunk)+1):((counter+1)*files_per_chunk)]
            }
            counter <- counter + 1
            cat(paste('  Processing chunk ', chunk, ' of ', total_chunks, '\n', sep = ''))

            # progress bar
            pb <- txtProgressBar(min = 1,
                                 max = length(read_id_fast5_file_subset),
                                 style = 3)
            progress <- function(n) setTxtProgressBar(pb, n)
            opts <- list(progress = progress)

            # foreach loop
            sink(file=NULL, type = 'output')
            if (experiment_type == 'dna') {
                data_list <- foreach::foreach(riff = read_id_fast5_file_subset,
                                              .combine = 'rbind',
                                              .inorder = FALSE,
                                              .errorhandling = 'pass',
                                              .options.snow = opts,
                                              .options.multicore = mcoptions) %dopar% {
                                                  tryCatch({
                                                      find_dna_tail_per_read(read_id_fast5_file = riff,
                                                                             file_path = NA,
                                                                             dna_datatype = dna_datatype,
                                                                             save_plots = save_plots,
                                                                             show_plots = show_plots,
                                                                             plot_debug = plot_debug,
                                                                             save_dir = save_dir,
                                                                             plotting_library = plotting_library,
                                                                             multifast5 = multifast5,
                                                                             basecalled_with = basecalled_with,
                                                                             model = model,
                                                                             dna_opts = dna_opts)
                                                  },
                                                  error=function(e){
                                                      ls <- list(read_id = riff$read_id,
                                                                 read_type = NA,
                                                                 tail_is_valid = NA,
                                                                 tail_start = NA,
                                                                 tail_end = NA,
                                                                 samples_per_nt = NA,
                                                                 tail_length = NA,
                                                                 file_path = riff$fast5_file,
                                                                 has_precise_boundary = NA)
                                                  })
                                              }
            } else {
                data_list <- foreach::foreach(riff = read_id_fast5_file_subset,
                                              .combine = 'rbind',
                                              .inorder = FALSE,
                                              .errorhandling = 'pass',
                                              .options.snow = opts,
                                              .options.multicore = mcoptions) %dopar% {
                                                  tryCatch({
                                                      find_rna_polya_tail_per_read(file_path = NA,
                                                                                   read_id_fast5_file = riff,
                                                                                   multifast5 = multifast5,
                                                                                   basecalled_with = basecalled_with,
                                                                                   model = model,
                                                                                   save_plots = save_plots,
                                                                                   show_plots = show_plots,
                                                                                   save_dir = save_dir,
                                                                                   plotting_library = plotting_library,
                                                                                   plot_debug = plot_debug)
                                                  },
                                                  error=function(e){
                                                      ls <- list(read_id = NA,
                                                                 tail_start = NA,
                                                                 tail_end = NA,
                                                                 samples_per_nt = NA,
                                                                 tail_length = NA,
                                                                 polya_fastq = NA,
                                                                 file_path = riff$fast5_file)
                                                  })
                                              }

            }
            cat('\n')
            if (remove_last_duplicate_read) data_list <- data_list[[1]]
            result[[chunk]] <- data_list
            con <- file(logfile_path, open = "a")
            sink(con, append=TRUE, split = TRUE, type='output')
        }
    } else if (!multifast5) {
        # Split the data into chunks
        files_per_chunk <- 4000
        total_files <- length(fast5_files_list)
        total_chunks <- ceiling(total_files/files_per_chunk)

        counter <- 0
        result <- list()

        if (experiment_type == 'dna') {
            cat(paste(clisymbols::symbol$bullet,
                      ' Searching for Poly(A) and Poly(T) tails...\n', sep=''))
        } else {
            cat(paste(clisymbols::symbol$bullet,
                      ' Searching for Poly(A) tails...\n', sep=''))
        }

        for(chunk in c(1:total_chunks)) {
            if(chunk == total_chunks) {
                fast5_files_subset <-
                    fast5_files_list[((counter*files_per_chunk)+1):total_files]
                # if the last chunk has only one read then just duplicate this
                # one read so that the progressbar works and does not throw an error
                if (length(fast5_files_subset) == 1) {
                    fast5_files_subset[[2]] <- fast5_files_subset
                    remove_last_duplicate_read <- TRUE
                }
            } else {
                fast5_files_subset <-
                    fast5_files_list[((counter*files_per_chunk)+1):((counter+1)*files_per_chunk)]
            }
            counter <- counter + 1

            # progress bar
            cat(paste('  Processing chunk ', chunk, ' of ', total_chunks, '\n', sep=''))
            pb <- txtProgressBar(min = 1,
                                 max = length(fast5_files_subset),
                                 style = 3)
            progress <- function(n) setTxtProgressBar(pb, n)
            opts <- list(progress = progress)

            # foreach loop
            sink(file=NULL, type = 'output')
            if (experiment_type == 'dna') {
                data_list <- foreach::foreach(file_path = fast5_files_subset,
                                              .combine = 'rbind',
                                              .inorder = FALSE,
                                              .options.snow = opts,
                                              .options.multicore = mcoptions) %dopar% {
                                                 tryCatch({
                                                     find_dna_tail_per_read(file_path = file_path,
                                                                            dna_datatype = dna_datatype,
                                                                            save_plots = save_plots,
                                                                            show_plots = show_plots,
                                                                            plot_debug = plot_debug,
                                                                            save_dir = save_dir,
                                                                            plotting_library = plotting_library,
                                                                            multifast5 = multifast5,
                                                                            basecalled_with = basecalled_with,
                                                                            model = model,
                                                                            dna_opts = dna_opts)
                                                 },
                                                 error=function(e){
                                                     ls <- list(read_id = NA,
                                                                read_type = NA,
                                                                tail_is_valid = NA,
                                                                tail_start = NA,
                                                                tail_end = NA,
                                                                samples_per_nt = NA,
                                                                tail_length = NA,
                                                                file_path = file_path,
                                                                has_precise_boundary = NA)
                                                 })
                                             }
            } else {
                data_list <-foreach::foreach(file_path = fast5_files_subset,
                                             .combine = 'rbind',
                                             .inorder = FALSE,
                                             .options.snow = opts,
                                             .options.multicore = mcoptions) %dopar% {
                                                 tryCatch({
                                                     find_rna_polya_tail_per_read(file_path = file_path,
                                                                                  read_id_fast5_file = NA,
                                                                                  multifast5 = multifast5,
                                                                                  basecalled_with = basecalled_with,
                                                                                  model = model,
                                                                                  save_plots = save_plots,
                                                                                  show_plots = show_plots,
                                                                                  save_dir = save_dir,
                                                                                  plotting_library = plotting_library,
                                                                                  plot_debug = plot_debug)
                                                 },
                                                 error=function(e){
                                                     ls <- list(read_id = NA,
                                                                tail_start = NA,
                                                                tail_end = NA,
                                                                samples_per_nt = NA,
                                                                tail_length = NA,
                                                                polya_fastq = NA,
                                                                file_path = file_path)
                                                 })
                                             }
            }
            cat('\n')
            if (remove_last_duplicate_read) data_list <- data_list[[1]]
            result[[chunk]] <- data_list
            con <- file(logfile_path, open = "a")
            sink(con, append=TRUE, split = TRUE, type='output')
        }
    }

    # format the results list into a tibble
    cat(paste0(clisymbols::symbol$bullet,' Formatting the tail data...\n'))
    result <- purrr::map(result, function(.x) tibble::as_tibble(.x))
    result <- dplyr::bind_rows(result, .id = "chunk")
    result <- dplyr::select(result, -chunk)
    cat('  Done!\n')

    # write the result to a csv file
    cat(paste(clisymbols::symbol$bullet,
              ' Saving the data in the CSV file...\n', sep=''))
    data.table::fwrite(result, file.path(save_dir, csv_filename, fsep = .Platform$file.sep))
    cat('  Done!\n')

    cat(paste0(clisymbols::symbol$bullet,
               ' A logfile containing all this information has been saved in this path: \n'))
    cat(paste0('  ', logfile_path, '\n'))

    cat(cli::rule(left=paste('Processing ended at ',
                             Sys.time(), sep = '')), '\n', sep = "")
    cat(paste(crayon::green(clisymbols::symbol$tick),
              ' Tailfinder finished successfully!\n', sep=''))
    return(result)
}