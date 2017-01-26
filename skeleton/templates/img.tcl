# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc img {src {alt ""} {center 1}} {
    set opts {img-responsive}
    if $center {
        lappend opts "center-block"
    }
    return "<img src=\"$src\" class=\"[join $opts { }]\" alt=\"$alt\">"
}

proc img-local args {
    global currentPageId
    set prefix "[get-page-data $currentPageId rootDirPath]/"
    lset args 0 "${prefix}images/[lindex $args 0]"
    img {*}$args
}
