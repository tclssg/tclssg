# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

proc config {key {default %NULL%}} {
    return [db config get $key $default]
}

proc setting {key {default %NULL%}} {
    upvar 1 input input
    return [file-setting $input $key $default]
}

proc article-setting {key {default %NULL%}} {
    upvar 1 articleInput articleInput
    return [file-setting $articleInput $key $default]
}

proc link-path {path {absolute 0}} {
    if {[regexp {^/} $path]} {
        error "not a relative path: \"$path\""
    }
    if {$absolute} {
        set url [config url]
        if {$url eq {%NULL%}} {
            error "for absolute links \"url\" must be set in\
                   the website config"
        }
        set link [url-join $url $path]
    } else {
        upvar 1 root root
        set link [url-join $root $path]
    }
    if {[config prettyURLs 0]} {
        regexp {(.*?/)index.html$} $link _ link
    }
    return $link
}

proc rel-link {path title} {
    upvar 1 root root
    set link [link-path $path 0]
    return "<a href=\"[entities $link]\">[entities $title]</a>"
}

proc tag-page-path tag {
    set path blog/tags/[slugify $tag]

    if {[config prettyURLs 0]} {
        append path /
    } else {
        append path .html
    }

    return $path
}

proc tag-page-link tag {
    upvar 1 root root
    return [rel-link [tag-page-path $tag] $tag]
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

proc absolute? link {
    return [regexp {^(?:[a-z]+:)?//} $link]
}

proc feed-path {input root filename suffix} {
    set tagPageTag [db settings preset-get $input tagPageTag {}]

    if {$tagPageTag eq {}} {
        return [file join $root blog $filename]
    }

    set path [input-to-output-path $input]

    if {[db config get prettyURLs 0]} {
        return [file join $root [file dirname $path] $filename]
    } else {
        # Get the output path without the page number added to it.
        return [file join $root [file rootname $path]]$suffix
    }
}

proc localized {input text} {
    localization get [setting locale en_US] ::document $text
}

proc document-title {input pageNumber} {
    set websiteTitle [setting websiteTitle {}]

    set sep { | }

    set pageTitle [setting title {}]
    set showTitle [setting {show title} 1]
    set tagPageTag [setting tagPageTag {}]

    set result {}
    if {$showTitle && $pageTitle ne ""} {
        lappend result $pageTitle
    }

    if {$tagPageTag ne ""} {
        lappend result [format \
            [localized $input {Posts tagged "%1$s"}] \
            $tagPageTag \
        ]
    }

    if {[string is integer $pageNumber] && $pageNumber > 1} {
        lappend result [format \
            [localized $input {page %1$s}] \
            $pageNumber \
        ]
    }
    if {$websiteTitle ne ""} {
        lappend result $websiteTitle
    }

    return [join $result $sep]
}
