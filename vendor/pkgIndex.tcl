# Tclssg, a static website generator.
# Copyright (c) 2013-2018, 2024
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

if {[info exists dir]} {set prevDir $dir}
foreach subdir browse {
    set dir [file join $prevDir $subdir]
    source -encoding utf-8 [file join $dir pkgIndex.tcl]
}
if {[info exists prevDir]} {set dir $prevDir; unset prevDir}
