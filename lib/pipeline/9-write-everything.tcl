# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.
namespace eval ::tclssg::pipeline::9-write-everything {
    namespace path ::tclssg

    proc transform {} {
        set outputDir [db settings get config outputDir]
        db eval {SELECT file, content FROM output} row {
            set dest [file join $outputDir $row(file)]
            set subdir [file dirname $dest]
            if {![file isdir $subdir]} {
                log::info "creating directory [list $subdir]"
                file mkdir $subdir
            }
            log::info "writing output file [list $dest]"
            utils::write-file -translation binary $dest $row(content)
        }
    }
}
