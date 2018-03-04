# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package ifneeded tclssg::templating 0 [list apply {dir {
    foreach path {
        {cache cache.tcl}
        {interpreter interpreter.tcl}
        templating.tcl
    } {
        uplevel 1 [list source -encoding utf-8 [file join $dir {*}$path]]
    }
}} $dir]
