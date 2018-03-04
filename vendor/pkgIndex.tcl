# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

if {[info exists dir]} {set prevDir $dir}
foreach subdir {browse markdown} {
    set dir [file join $prevDir $subdir]
    source -encoding utf-8 [file join $dir pkgIndex.tcl]
}
if {[info exists prevDir]} {set dir $prevDir; unset prevDir}
