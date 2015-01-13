# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc image {src {alt ""} {center 1}} {
    set opts {img-responsive}
    if $center {
        lappend opts "center-block"
    }
    return "<img src=\"$src\" class=\"[join $opts { }]\" alt=\"$alt\">"
}

proc local-image args {
    global currentPageId
    set absoluteLinks 0
    if {$absoluteLinks} {
        set prefix [get-website-config-variable url {}]
    } else {
        set prefix [get-page-data $currentPageId rootDirPath]
    }
    lset args 0 "${prefix}images/[lindex $args 0]"
    image {*}$args
}
