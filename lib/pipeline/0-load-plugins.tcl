# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Find Tcl source code files in the plugins/ directory and source them.
namespace eval ::tclssg::pipeline::0-load-plugins {
    namespace path ::tclssg

    proc load files {
        set plugins [db settings get security plugins 0]

        db transaction {
            set inputDir [db settings get config inputDir]
            foreach file $files {
                set id [utils::replace-path-root $file $inputDir {}]
                if {[regexp {^/?plugins.*\.tcl$} $id]} {
                    if {$plugins} {
                        log::info "loading plugin [list $file]"
                        source $file
                    } else {
                        log::warn "NOT loading plugin [list $file]"
                    }
                }
            }
        }
    }
}
