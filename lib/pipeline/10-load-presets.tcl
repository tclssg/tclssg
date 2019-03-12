# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Load settings from the preset files into the database.
namespace eval ::tclssg::pipeline::10-load-presets {
    namespace path ::tclssg

    proc load files {
        db transaction {
            set inputDir [db config get inputDir]
            foreach file $files {
                set id [utils::replace-path-root $file $inputDir {}]
                if {[regexp {^/?presets} $id]} {
                    log::info "reading preset file [list $file]"

                    set bin [utils::read-file -translation binary $file]

                    set settings [utils::remove-comments $bin]

                    if {[dict exists $settings presets]} {
                        error [list forbidden setting {"presets"} in preset \
                                    file $file]
                    }
                    db input add \
                        -type preset \
                        -file $id \
                        -timestamp [file mtime $file]
                    dict for {key value} $settings {
                        db settings set $id $key $value
                    }
                }
            }
        }
    }
}
