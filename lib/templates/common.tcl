# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

set ::blogDefaults [db settings get config blogDefaults]
set ::pageDefaults [db settings get config pageDefaults]

proc config {key {default %NULL%}} {
    return [db settings get config $key $default]
}

proc setting {key {default %NULL%}} {
    return [file-setting $::input $key $default]
}

proc absolute-link path {
    if {$url eq {%NULL%}} {
        error "using absolute-link requires that \"url\" be set in website\
               config"
    }
}

proc tag-page-link tag {
    return [rel-link blog/tags/[slugify $tag] $tag]
}

proc rel-link {path title} {
    if {[regexp {^/} $path]} {
        error "not a relative path: \"$path\""
    }
    set link [url-join $::root $path]
    if {[config prettyURLs 0]} {
        regexp {(.*?/)index.html$} $link _ link
    }
    return "<a href=\"[entities $link]\">[entities $title]</a>"
}

proc blog-post? {} {
    return [setting blogPost 0]
}

proc url-join args {
    set url {}
    foreach fragment $args {
        if {[regexp {^[a-z]+://} $fragment]} {
            set url {}
        } elseif {[regexp {[^/]$} $url]} {
            append url /
        }
        append url $fragment
    }
    return $url
}
