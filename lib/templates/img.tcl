# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

proc img {src {alt {}} {center 1}} {
    set opts img-responsive

    if $center {
        lappend opts "center-block"
    }

    return "<img src=\"[entities $src]\"\
                 class=\"[entities [join $opts { }]]\"\
                 alt=\"[entities $alt]\">"
}

proc img-local {file {alt {}} {center 1}} {
    upvar 1 input input

    set imagePath [setting imagePath {}]

    if {$imagePath eq {} ||
        (![regexp {^/} $imagePath] &&
         ![regexp {^[A-Za-z]://} $imagePath])} {
       error "\[img-local\] requires the page setting \"imagePath\" to be\
              an absolute path or a URL; \"$imagePath\" given"
    }

    return [img [url-join $imagePath $file] $alt $center]
}
