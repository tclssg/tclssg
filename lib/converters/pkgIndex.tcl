# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package ifneeded tclssg::converters 0 [list apply {dir {
    namespace eval ::tclssg::converters {
        namespace export *
        namespace ensemble create
    }

    foreach path {
        markdown.tcl
    } {
        uplevel 1 [list source -encoding utf-8 [file join $dir {*}$path]]
    }
    package provide tclssg::converters 0
}} $dir]
