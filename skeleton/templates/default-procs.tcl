# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc relative-link {id} {
    global pageLinks
    return [dict get $pageLinks $id]
}

set indexLink [relative-link $indexPage]
if {[website-var-get-default blogIndexPage {}] ne ""} {
    set blogIndexLink [relative-link $blogIndexPage]
} else {
    set blogIndexLink {}
}

proc page-var-get-default {varName explicitDefault {pageId {}}} {
    global variables
    global currentPageId
    global pages
    global pageVariables

    # Account for config defaults.
    set default [dict-default-get \
            $explicitDefault \
            [website-var-get-default pageVariables {}] \
            $varName]

    if {$pageId eq ""} {
        dict-default-get $default $variables $varName
    } else {
        dict-default-get $default $pages $pageId variables $varName
    }
}

proc either {condition value} {
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

proc format-article-title {} {
    # Article title.
    global currentPageId
    set title [page-var-get-default pageTitle {}]
    if {$title ne "" && ![page-var-get-default hideTitle 0]} {
        set result {<header class="page-title"><h2>}
        if {[page-var-get-default blogPost 0] &&
            [page-var-get-default collection 0]} {
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

proc abbreviate-article {content {abbreviate 0}} {
    global moreText
    global currentPageId
    if {$abbreviate} {
        if {[regexp {(.*?)<!-- *more *-->} $content match content]} {
            append content \
                    [format [page-var-get-default moreText "(...)"] \
                    [relative-link $currentPageId]]
        }
    }
    return $content
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

            set listElems {}
            foreach tag $postTags {
                lappend listElems \
                    "<li><a href=\"$tagPageLink#[slugify $tag]\">$tag</a></li>"
            }
            append tagList [join $listElems \
                    "<span class='separator small'> </span>"]

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

proc format-prev-next-links {prevLinkTitle nextLinkTitle} {
    # Blog "next" and "previous" blog index page links.
    proc make-link x {
        return "<a href=\"$x\">$x</a>"
    }
    global currentPageId pages
    set prevPageReal [page-var-get-default prevPage {}]
    set nextPageReal [page-var-get-default nextPage {}]
    set links {}
    if {[page-var-get-default blogPost 0] && \
                (($prevPageReal ne "") || ($nextPageReal ne ""))} {
        append links {<nav class="prev-next">}
        if {$prevPageReal ne ""} {
            append links "<span class=\"prev-page-link\">[format-link $prevPageReal 0 $prevLinkTitle]</span>"
        }
        if {$nextPageReal ne ""} {
            append links "<span class=\"next-page-link\">[format-link $nextPageReal 0 $nextLinkTitle]</span>"
        }
        append links {</nav><!-- prev-next -->}
    }
    return $links
}

proc format-tag-cloud {} {
    # Blog tag cloud. For each tag it links to pages that are tagged with it.
    global tags
    global pages
    set tagCloud {}
    if {[page-var-get-default showTagCloud 0]} {
        append tagCloud {<nav class="tag-cloud"><h3>Tags</h3><dl>}
        foreach {tag ids} [website-var-get-default tags {}] {
            append tagCloud "<dt id=\"[slugify $tag]\">$tag</dt><dd><ul>"

            set listElems {}
            foreach id $ids {
                lappend listElems [format-link $id]
            }
            append tagCloud [join $listElems "<span class='separator small'> </span>"]
            append tagCloud "</ul></dd>"
        }
        append tagCloud {</dl></nav><!-- tag-cloud -->}
    }
    return $tagCloud
}

proc format-footer {} {
    # Footer.
    global copyright
    set footer {}
    if {[website-var-get-default copyright {}] ne ""} {
        append footer "<div class=\"copyright\">$copyright</div>"
    }
    if {![page-var-get-default hideFooter 0]} {
        append footer {<div class="powered-by"><small>Powered by <a href="https://github.com/dbohdan/tclssg">Tclssg</a> and <a href="http://getbootstrap.com/">Bootstrap</a></small></div>}
    }
    return $footer
}

proc format-comments {} {
    global commentsEngine
    set engine [website-var-get-default commentsEngine none]
    set result {}
    if {[page-var-get-default showUserComments 0]} {
        switch -nocase -- $engine {
            disqus { set result [format-comments-disqus] }
            none {}
            {} {}
            default { error "comments engine $engine not found" }
        }
    }
    return "<div class=\"comments\">$result</div>"
}

proc format-comments-disqus {} {
    global commentsDisqusShortname
    set str ""
    set str {
         <div id="disqus_thread"></div>
            <script type="text/javascript">
            /* * * CONFIGURATION VARIABLES: EDIT BEFORE PASTING INTO YOUR WEBPAGE * * */
            }
    append str "var disqus_shortname = '$commentsDisqusShortname'; // required: replace example with your forum shortname \n"
    append str {
            /* * * DON'T EDIT BELOW THIS LINE * * */
            (function() {
                var dsq = document.createElement('script'); dsq.type = 'text/javascript'; dsq.async = true;
                dsq.src = '//' + disqus_shortname + '.disqus.com/embed.js';
                (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(dsq);
            })();
            </script>
            <noscript>Please enable JavaScript to view the <a href="http://disqus.com/?ref_noscript">comments powered by Disqus.</a></noscript>
            <a href="http://disqus.com" class="dsq-brlink">comments powered by <span class="logo-disqus">Disqus</span></a>
    }
    return $str
}
