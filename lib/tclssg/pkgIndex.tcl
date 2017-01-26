# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package ifneeded tclssg-lib 0 [list apply {{dir} {
    source [file join $dir tclssg-lib.tcl]
    import $dir
}} $dir]
