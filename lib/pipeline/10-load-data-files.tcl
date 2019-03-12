# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Find every file in the data/ directory and put it as an input in the DB.
namespace eval ::tclssg::pipeline::10-load-data-files {
    namespace path ::tclssg

    proc load files {
        db transaction {
            set inputDir [db config get inputDir]
            foreach file $files {
                set id [utils::replace-path-root $file $inputDir {}]
                if {[regexp {^/?data} $id]} {
                    log::info "reading data file [list $file]"
                    set data [utils::read-file -translation binary $file]
                    db input add \
                        -type data \
                        -file $id \
                        -raw $data \
                        -timestamp [file mtime $file]
                }
            }
        }
    }
}
