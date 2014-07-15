# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc page-variable-default-get {default varName {pageId {}}} {
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
        set title [page-variable-default-get $link pageTitle $id]
    }
    set linkHTML "<a href=\"$link\">$title</a>"
    if {$li} {
        set linkHTML "<li>$linkHTML</li>"
    }
    return $linkHTML
}

proc format-html-title {} {
    global websiteTitle
    set pageTitle [page-variable-default-get {} pageTitle]
    set hideTitle [page-variable-default-get 0 hideTitle]
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
        [page-variable-default-get 0 blogEntry] &&
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
    set title [page-variable-default-get {} pageTitle]
    if {$title ne "" && ![page-variable-default-get 0 hideTitle]} {
        return "<header id=\"page-title\"><h2>$title</h2></header>"
    } else {
        return ""
    }
}

proc format-article-date {} {
    # Page date.
    global pages
    set date [page-variable-default-get {} date]
    if {$date ne "" && ![page-variable-default-get 0 hideDate]} {
        return "<header id=\"date\">$date</header>"
    } else {
        return ""
    }
}

proc format-article-tag-list {} {
    # Page tag list.
    global pages
    global pageLinks
    set tagList {}
    set tagPageLink {}
    if {[get-default tagPage {}] ne ""} {
        set tagPageLink [dict get $pageLinks $tagPage]
    }
    if {[page-variable-default-get 0 blogEntry] && \
        ![page-variable-default-get 0 hidePostTags]} {
        set postTags [page-variable-default-get {} tags]
        if {[llength $postTags] > 0} {
            append tagList {<nav id="tags"><ul>}
            foreach tag [lrange $postTags 0 end-1 ] {
                append tagList "<li><a href=\"$tagPageLink#[slugify $tag]\">$tag</a>, </li>"
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
    if {[page-variable-default-get 0 blogEntry] && \
        ![page-variable-default-get 0 hideSidebar]} {
        append sidebar {<nav id="sidebar"><ul>}
        foreach {id ___} $pages {
            # Only add links to other blog entries.
            if {[page-variable-default-get 0 blogEntry $id] && \
                ![page-variable-default-get 0 hideFromSidebar $id]} {
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

    if {[page-variable-default-get 0 blogEntry] && \
        ![page-variable-default-get 0 hidePrevNextLinks]} {
        set pageIds {}
        foreach {id ___} $pages {
            # Only have links to other blog entries.
            if {[page-variable-default-get 0 blogEntry $id] && \
                ![page-variable-default-get 0 hideFromSidebar $id]} {
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
    if {[page-variable-default-get 0 showTagCloud]} {
        append tagCloud {<nav id="tag-cloud"><dl>}
        foreach {tag ids} [dict-default-get {} $pages tags] {
            append tagCloud "<dt id=\"[slugify $tag]\">$tag</dt><dd><ul>"
            foreach id [lrange $ids 0 end-1] {
                append tagCloud "[format-link $id], "
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
    if {![page-variable-default-get 0 hideFooter]} {
        append footer {<div id="powered-by">Powered by <a href="https://github.com/dbohdan/tclssg">Tclssg</a></div>}
    }
    return $footer
}
