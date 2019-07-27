# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.
namespace eval ::tclssg::pipeline::90-write-everything {
    namespace path ::tclssg

    proc transform {} {
        set outputDir [db config get outputDir]
        set outputDirNorm [fileutil::fullnormalize $outputDir]

        # Restore the original $outputDir prefix for logging.
        set shorten [list apply {{fromDir toDir path} {
            list [::tclssg::utils::replace-path-root $path $fromDir $toDir]
        }} $outputDirNorm $outputDir]

        db eval {SELECT file, content FROM output} row {
            set dest [fileutil::jail $outputDir $row(file)]
            set subdir [file dirname $dest]
            if {![file isdir $subdir]} {
                log::info "creating directory [{*}$shorten $subdir]"
                file mkdir $subdir
            }
            log::info "writing output file [{*}$shorten $dest]"
            utils::write-file -translation binary $dest $row(content)
        }
    }
}
