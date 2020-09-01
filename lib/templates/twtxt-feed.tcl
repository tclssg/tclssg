# Tclssg, a static website generator.
# Copyright (c) 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::twtxt-feed {}

template-proc ::twtxt-feed::render {
    -articles       articles
    -collection     {collection 0}
    -collectionTop  {collectionTop 1}
    -input          input
    -nextPage       nextPage
    -output         output
    -pageNumber     {pageNumber 1}
    -prevPage       prevPage
    -root           root
} {<% foreach articleInput [lrange $articles 1 end] {

    set title [article-setting title {}]
    set timestamp [db input get $articleInput timestamp]
    set link [link-path [input-to-output-path $articleInput] 1]

    set time [clock format $timestamp \
        -format {%Y-%m-%dT%H:%M:%SZ} \
        -timezone :UTC \
    ]
%><%! lindex "$time\t\"$title\" $link" %>
<% } %>}

proc ::twtxt-feed::path {input root} {
    set tagPageTag [db settings preset-get $input tagPageTag {}]

    if {$tagPageTag eq {}} {
        return [file join $root blog/twtxt.txt]
    }

    set path [input-to-output-path $input]

    if {[db config get prettyURLs 0]} {
        return [file join $root [file dirname $path] twtxt.txt]
    } else {
        # Get the output path without the page number added to it.
        return [file join $root [file rootname $path]].twtxt.txt
    }
}
