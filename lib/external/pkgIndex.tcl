# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

set maindir $dir
set dir [file join $maindir markdown] ; source [file join $dir pkgIndex.tcl]
set dir [file join $maindir browse] ; source [file join $dir pkgIndex.tcl]
unset maindir
