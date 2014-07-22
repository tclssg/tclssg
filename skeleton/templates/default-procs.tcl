# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc page-var-get-default {varName default {pageId {}}} {
    global pages
    global currentPageId
    if {$pageId eq ""} {
        set pageId $currentPageId
    }
    dict-default-get $default $pages $pageId variables $varName
}

proc format-link {id {li 1} {customTitle ""}} {
    global pages
    global pageLinks
    set link [dict get $pageLinks $id]
    if {$customTitle ne ""} {
        set title $customTitle
    } else {
        set title [page-var-get-default pageTitle $link $id]
    }
    set linkHTML "<a href=\"$link\">$title</a>"
    if {$li} {
        set linkHTML "<li>$linkHTML</li>"
    }
    return $linkHTML
}

proc format-html-title {} {
    global websiteTitle
    set pageTitle [page-var-get-default pageTitle {}]
    set hideTitle [page-var-get-default hideTitle 0]
    if {$hideTitle || ($pageTitle == "")} {
        return $websiteTitle
    } else {
        return "$pageTitle | $websiteTitle"
    }
}

proc format-index-link {} {
    # Link back to index/blog index.
    global indexPage
    global blogIndexPage
    global currentPageId
    set pageToLinkBackTo $indexPage
    if {[info exists blogIndexPage] &&
        [page-var-get-default blogPost 0] &&
        $currentPageId ne $blogIndexPage} {
        # Link from blog entries to the blog index page but link back to the
        # index page from the blog index page.
        set pageToLinkBackTo $blogIndexPage
    }

    if {$currentPageId ne $pageToLinkBackTo} {
        return "<header id=\"index-link\">[format-link $pageToLinkBackTo 0]</header>"
    } else {
        return ""
    }
}

proc format-article-title {} {
    # Article title.
    global pages
    set title [page-var-get-default pageTitle {}]
    if {$title ne "" && ![page-var-get-default hideTitle 0]} {
        return "<header id=\"page-title\"><h2>$title</h2></header>"
    } else {
        return ""
    }
}

proc format-article-date {} {
    # Page date.
    global pages
    set date [page-var-get-default date {}]
    if {$date ne "" && ![page-var-get-default hideDate 0]} {
        return "<header id=\"date\">$date</header>"
    } else {
        return ""
    }
}

proc format-article-tag-list {} {
    # Page tag list.
    global pages
    global pageLinks
    global tagPage
    set tagList {}
    set tagPageLink {}
    if {[get-default tagPage {}] ne ""} {
        set tagPageLink [dict get $pageLinks $tagPage]
    }
    if {[page-var-get-default blogPost 0] && \
        ![page-var-get-default hidePostTags 0]} {
        set postTags [page-var-get-default tags {}]
        if {[llength $postTags] > 0} {
            append tagList {<nav id="tags"><ul>}
            foreach tag [lrange $postTags 0 end-1 ] {
                append tagList "<li><a href=\"$tagPageLink#[slugify $tag]\">$tag</a></li>"
            }
            set tag [lindex $postTags end]
            append tagList "<li><a href=\"$tagPageLink#[slugify $tag]\">$tag</a></li>"
            append tagList {</ul></nav><!-- tags -->}
        }
    }
    return $tagList
}

proc format-sidebar {} {
    # Blog sidebar.
    global pages
    set sidebar {}
    if {[page-var-get-default blogPost 0] && \
        ![page-var-get-default hideSidebar 0]} {
        append sidebar {<nav id="sidebar"><ul>}
        foreach {id ___} $pages {
            # Only add links to other blog entries.
            if {[page-var-get-default blogPost 0 $id] && \
                ![page-var-get-default hideFromSidebar 0 $id]} {
                append sidebar [format-link $id]
            }
        }
        append sidebar {</ul></nav><!-- sidebar -->}
    }
    return $sidebar
}

proc format-prev-next-links {} {
    # Blog "next" and "previous" blog post links.
    global pages
    global currentPageId
    set links {}

    if {[page-var-get-default blogPost 0] && \
        ![page-var-get-default hidePrevNextLinks 0]} {
        set pageIds {}
        foreach {id ___} $pages {
            # Only have links to other blog entries.
            if {[page-var-get-default blogPost 0 $id] && \
                ![page-var-get-default hideFromSidebar 0 $id]} {
                lappend pageIds $id
            }
        }

        set currentPageIndex [lsearch -exact $pageIds $currentPageId]
        append links {<nav id="prev-next">}
        set prevPage [lindex $pageIds [expr $currentPageIndex - 1]]
        set nextPage [lindex $pageIds [expr $currentPageIndex + 1]]
        if {$prevPage ne ""} {
            append links "<span id=\"previous\">[format-link $prevPage 0]</span>"
        }
        if {$nextPage ne ""} {
            append links "<span id=\"next\">[format-link $nextPage 0]</span>"
        }
        append links {</nav><!-- prev-next -->}
    }
    return $links
}

proc format-tag-cloud {} {
    # Blog tag cloud. For each tag it links to pages that are tagged with it.
    global pages
    set tagCloud {}
    if {[page-var-get-default showTagCloud 0]} {
        append tagCloud {<nav id="tag-cloud"><dl>}
        foreach {tag ids} [dict-default-get {} $pages tags] {
            append tagCloud "<dt id=\"[slugify $tag]\">$tag</dt><dd><ul>"
            foreach id [lrange $ids 0 end-1] {
                append tagCloud "[format-link $id]"
            }
            append tagCloud [
                format-link [
                    lindex $ids end
                ]
            ]
            append tagCloud "</ul></dd>"
        }
        append tagCloud {</dl></nav><!-- tag-cloud -->}
    }
    return $tagCloud
}

proc format-footer {} {
    # Footer.
    global pages
    set footer {}
    if {[get-default copyright {}] ne ""} {
        append footer "<div id=\"copyright\">$copyright</div>"
    }
    if {![page-var-get-default hideFooter 0]} {
        append footer {<div id="powered-by">Powered by <a href="https://github.com/dbohdan/tclssg">Tclssg</a></div>}
    }
    return $footer
}
