# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc format-article-author {} {
    set author [get-current-page-variable author ""]
    if {$author ne "" && ![get-current-page-variable hideAuthor 0]} {
        return [format {<address class="author">%s</address>} $author]
    } else {
        return ""
    }
}

proc format-article-title {} {
    # Article title.
    global currentPageId
    global collection
    set title [get-current-page-variable title {}]
    if {$title ne "" && ![get-current-page-variable hideTitle 0]} {
        set result {<h2 class="page-title">}
        if {[blog-post?] && $collection} {
            append result [format-link $currentPageId 0 $title]
        } else {
            append result $title
        }
        append result {</h2>}
        return $result
    } else {
        return ""
    }
}

proc format-date {dateClass dateVarName scannedDateVarName} {
    set date [get-current-page-variable $dateVarName {}]
    set dateScanned [get-current-page-variable $scannedDateVarName {}]

    if {$date ne ""} {
        set datetime [clock format \
                [lindex $dateScanned 0] \
                -format [lindex $dateScanned 1]]
        return \
            "<time datetime=\"$datetime\" class=\"$dateClass\">$date</time>"
    }
    return ""
}

proc format-date {dateClass dateVarName scannedDateVarName} {
    set date [get-current-page-variable $dateVarName {}]
    set dateScanned [get-current-page-variable $scannedDateVarName {}]

    if {$date ne ""} {
        set datetime [clock format \
                [lindex $dateScanned 0] \
                -format [lindex $dateScanned 1]]
        return \
            "<time datetime=\"$datetime\" class=\"$dateClass\">$date</time>"
    }
    return ""
}

proc format-article-date {} {
    # Article creation and modification date.
    set result ""
    if {![get-current-page-variable hideDate 0]} {
        append result [format-date date date dateScanned]
        if {$result ne ""} {
            append result "<br>"
        }
        if {![get-current-page-variable hideModifiedDate 0]} {
            append result \
                    [format-date modified modifiedDate modifiedDateScanned]
        }
    }
    return $result
}

proc abbreviate-article {content {abbreviate 0}} {
    global moreText
    global currentPageId
    if {$abbreviate} {
        if {[regexp {(.*?)<!-- *more *-->} $content match content]} {
            append content \
                    [format [get-current-page-variable moreText "(...)"] \
                    [relative-link $currentPageId]]
        }
    }
    return $content
}


proc format-article-tag-list {} {
    # Page tag list.
    set tagPage [get-website-config-variable tagPage {}]

    global currentPageId
    set tagListHtml {}

    set postTags [get-page-tags $currentPageId]
    if {[llength $postTags] > 0} {

        set tagLinks {}
        foreach tag $postTags {
            lappend tagLinks "<li class=\"tag\">[format-link \
                    [get-tag-page $tag 0] 0 $tag]</li>"
        }

        set tagListHtml "<nav class=\"container-fluid tags\"><ul>[format \
                [mc {Tagged: %s}] [join $tagLinks]]</ul></nav><!-- tags -->"
    }

    return $tagListHtml
}
