# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package ifneeded tclssg::pipeline 0 [list apply {dir {
    foreach path [lsort [glob -dir $dir {[0-9]*.tcl}]] {
        uplevel 1 [list source -encoding utf-8 $path]
    }
    package provide tclssg::pipeline 0
}} $dir]
