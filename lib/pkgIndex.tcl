# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

foreach subdir {cli config db debugger interpreter templates utils} {
    package ifneeded tclssg::$subdir 0 [
        list source -encoding utf-8 [file join $dir $subdir $subdir.tcl]
    ]
}

if {[info exists dir]} {set prevDir $dir}
foreach subdir {converters dustmote-snit pipeline} {
    set dir [file join $prevDir $subdir]
    source -encoding utf-8 [file join $dir pkgIndex.tcl]
}
if {[info exists prevDir]} {set dir $prevDir; unset prevDir}
