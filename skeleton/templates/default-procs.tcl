# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc relative-link {id} {
    global pageLinks
    return [dict get $pageLinks $id]
}

set indexLink [relative-link $indexPage]
set blogIndexLink [relative-link $blogIndexPage]

proc page-var-get-default {varName default {pageId {}}} {
    global variables
    global currentPageId
    global pages
    if {$pageId eq ""} {
        dict-default-get $default $variables $varName
    } else {
        dict-default-get $default $pages $pageId variables $varName
    }
}

proc return-if {condition value} {
    if {$condition} {
        return $value
    } else {
        return {}
    }
}

proc format-link {id {li 1} {customTitle ""}} {
    set link [relative-link $id]
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

proc format-document-title {} {
    global websiteTitle
    set pageTitle [page-var-get-default pageTitle {}]
    set hideTitle [page-var-get-default hideTitle 0]
    if {$hideTitle} {
        return ""
    } else {
        if {$pageTitle eq ""} {
            return $websiteTitle
        } else {
            return $pageTitle
        }
    }
}

proc format-article-title {} {
    # Article title.
    global currentPageId
    set title [page-var-get-default pageTitle {}]
    if {$title ne "" && ![page-var-get-default hideTitle 0]} {
        set result {<header class="page-title"><h2>}
        if {[page-var-get-default blogPost 0]} {
            append result [format-link $currentPageId 0 $title]
        } else {
            append result $title
        }
        append result {</h2></header>}
        return $result
    } else {
        return ""
    }
}

proc format-article-date {} {
    # Page date.
    set date [page-var-get-default date {}]
    if {$date ne "" && ![page-var-get-default hideDate 0]} {
        return "<header class=\"date\">$date</header>"
    } else {
        return ""
    }
}

proc format-article-tag-list {} {
    # Page tag list.
    global pageLinks
    global tagPage
    set tagList {}
    set tagPageLink {}
    if {[website-var-get-default tagPage {}] ne ""} {
        set tagPageLink [dict get $pageLinks $tagPage]
    }
    if {[page-var-get-default blogPost 0] && \
        ![page-var-get-default hidePostTags 0]} {
        set postTags [page-var-get-default tags {}]
        if {[llength $postTags] > 0} {
            append tagList {<nav class="tags"><ul>}
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
        append sidebar {<nav class="sidebar"><h3>Posts</h3><ul>}
        foreach {id _} $pages {
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
    # Blog "next" and "previous" blog index page links.
    proc make-link x {
        return "<a href=\"$x\">$x</a>"
    }
    global currentPageId pages
    puts $currentPageId
    set prevPageReal [page-var-get-default prevPage {}]
    set nextPageReal [page-var-get-default nextPage {}]
    set links {}
    if {[page-var-get-default blogPost 0] && \
                (($prevPageReal ne "") || ($nextPageReal ne ""))} {
        append links {<nav class="prev-next">}
        if {$prevPageReal ne ""} {
            append links "<span class=\"previous\">[format-link $prevPageReal 0]</span>"
        }
        if {$nextPageReal ne ""} {
            append links "<span class=\"next\">[format-link $nextPageReal 0]</span>"
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
        append tagCloud {<nav class="tag-cloud"><h3>Tags</h3><dl>}
        foreach {tag ids} [page-var-get-default tags {}] {
            append tagCloud "<dt id=\"[slugify $tag]\">$tag</dt><dd><ul>"
            foreach id [lrange $ids 0 end-1] {
                append tagCloud "[format-link $id]"}
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
    set footer {}
    if {[website-var-get-default copyright {}] ne ""} {
        append footer "<div class=\"copyright\">$copyright</div>"
    }
    if {![website-var-get-default hideFooter 0]} {
        append footer {<div class="powered-by">Powered by <a href="https://github.com/dbohdan/tclssg">Tclssg</a></div>}
    }
    return $footer
}
