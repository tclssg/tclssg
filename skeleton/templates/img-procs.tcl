# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc image {relativeSrc {alt ""} {center 1}} {
    set opts {img-responsive}
    if $center {
        lappend opts "center-block"
    }
    return "<img src=\"$relativeSrc\" class=\"[join $opts { }]\" alt=\"$alt\">"
}

proc local-image args {
	global rootDirPath
    lset args 0 "$rootDirPath/images/[lindex $args 0]"
    image {*}$args
}
