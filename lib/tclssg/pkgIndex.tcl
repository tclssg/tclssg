# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package ifneeded tclssg-lib 0 [format {
    source %s
    import %s
} [file join $dir tclssg-lib.tcl] $dir]
