# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc format-article-author {} {
    set author [get-current-page-setting author ""]
    if {$author ne "" && ![get-current-page-setting hideAuthor 0]} {
        return [format {<address class="author">%s</address>} $author]
    } else {
        return ""
    }
}

proc format-article-title {} {
    # Article title.
    global currentPageId
    global collection
    global collectionTopArticle
    set title [entities [get-current-page-setting title {}]]
    if {$title ne "" && !([get-current-page-setting hideTitle 0] ||
            [get-current-page-setting hideArticleTitle 0])} {
        set result {<h1 class="page-title">}
        if {[blog-post?] && $collection && !$collectionTopArticle} {
            append result [format-link $currentPageId 0 $title]
        } else {
            append result $title
        }
        append result {</h1>}
        return $result
    } else {
        return ""
    }
}

proc format-date {dateClass dateVarName scannedDateVarName} {
    set date [get-current-page-setting $dateVarName {}]
    set dateScanned [get-current-page-setting $scannedDateVarName {}]

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
    set date [get-current-page-setting $dateVarName {}]
    set dateScanned [get-current-page-setting $scannedDateVarName {}]

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
    set resultList {}
    if {![get-current-page-setting hideDate 0]} {
        set dateF [format-date date date dateScanned]
        if {$dateF ne ""} {
            lappend resultList $dateF
        }
        if {![get-current-page-setting hideModifiedDate 0]} {
            set modDateF [format-date modified modifiedDate modifiedDateScanned]
            if {$modDateF ne ""} {
                lappend resultList $modDateF
            }
        }
    }
    switch -exact -- [llength $resultList] {
        0 {
            return ""
        }
        1 {
            return [format [mc {Published %1$s}] $dateF]
        }
        default {
            return [format [mc {Published %1$s, updated %2$s}] $dateF $modDateF]
        }
    }
}

proc abbreviate-article {content {abbreviate 0} {absoluteLink 0}} {
    global currentPageId
    if {$absoluteLink} {
        set link [absolute-link $currentPageId]
    } else {
        set link [relative-link $currentPageId]
    }
    if {$abbreviate} {
        if {[regexp {(.*?)<!-- *more *-->} $content match content]} {
            append content [string map [list \$link $link] \
                    [get-current-page-setting moreText "(...)"]]
        }
    }
    return $content
}


proc format-article-tag-list {} {
    # Page tag list.
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
                [mc {Tagged: %1$s}] [join $tagLinks]]</ul></nav><!-- tags -->"
    }

    return $tagListHtml
}
