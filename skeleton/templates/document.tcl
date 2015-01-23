# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc sidebar-links? {} {
    return [expr {
        [blog-post?] && ![get-current-page-setting hideSidebarLinks 0]
    }]
}

proc sidebar-note? {} {
    return [expr {
        ![get-current-page-setting hideSidebarNote 0]
    }]
}

proc tag-cloud? {} {
    return [expr {
        [blog-post?] && ![get-current-page-setting hideSidebarTagCloud 0]
    }]
}

proc pick-at-most {list limit} {
    if {[string is integer -strict $limit] && ($limit >= 0)} {
        return [lrange $list 0 [expr {$limit - 1}]]
    } else {
        return $list
    }
}

proc format-document-title {} {
    set websiteTitle [get-website-config-setting websiteTitle {}]

    set sep { | }

    set pageTitle [get-current-page-setting title {}]
    set hideTitle [get-current-page-setting hideTitle 0]
    set pageNumber [get-current-page-setting pageNumber {}]
    set tagPageTag [get-current-page-setting tagPageTag {}]

    set result {}
    if {(!$hideTitle) && ($pageTitle ne "")} {
        lappend result $pageTitle
    }

    if {$tagPageTag ne ""} {
        lappend result [format [mc {Posts tagged "%1$s"}] $tagPageTag]
    }

    if {[string is integer $pageNumber] && ($pageNumber > 0)} {
        lappend result [format [mc {page %1$s}] [expr {$pageNumber + 1}]]
    }
    lappend result $websiteTitle


    return [entities [join $result $sep]]
}

proc format-navbar-brand {} {
    set navbarBrand [string map [list \
                    \$rootDirPath [get-current-page-data rootDirPath]] \
            [get-current-page-setting navbarBrand {}]]
    if {$navbarBrand ne ""} {
        return $navbarBrand
    } else {
        return [get-website-config-setting websiteTitle {}]
    }
}

proc format-sidebar-links {} {
    # Blog sidebar.
    set sidebar {}
    if {[sidebar-links?]} {
        append sidebar {<nav class="sidebar-links"><h3>Posts</h3><ul>}

        # Limit the number of posts linked to according to maxSidebarLinks.
        set sidebarPostIds [get-website-config-setting sidebarPostIds {}]
        set maxSidebarLinks [get-website-config-setting maxSidebarLinks inf]

        foreach id [pick-at-most $sidebarPostIds $maxSidebarLinks] {
            append sidebar [format-link $id]
        }
        append sidebar {</ul></nav><!-- sidebar-links -->}
    }
    return $sidebar
}


proc format-sidebar-note {} {
    return [format \
            {<div class="sidebar-note">%s</div><!-- sidebar-note -->} \
            [get-current-page-setting sidebarNote ""]]
}

proc format-prev-next-links {prevLinkTitle nextLinkTitle} {
    # Blog "next" and "previous" blog index page links.
    set prevPageReal [get-current-page-setting prevPage {}]
    set nextPageReal [get-current-page-setting nextPage {}]
    set links {}
    if {[blog-post?] && (($prevPageReal ne "") || ($nextPageReal ne ""))} {
        append links {<nav class="prev-next text-center"><ul class="pager">}
        if {$prevPageReal ne ""} {
            append links "<li class=\"previous\">[format-link \
                    $prevPageReal 0 $prevLinkTitle]</li>"
        }
        if {$nextPageReal ne ""} {
            append links "<li class=\"next\">[format-link \
                    $nextPageReal 0 $nextLinkTitle]</li>"
        }
        append links {</ul></nav><!-- prev-next -->}
    }
    return $links
}

proc format-tag-cloud {} {
    # Blog tag cloud. For each tag it links to pages that are tagged with it.
    set tagCloud {}

    # Limit the number of tags listed to according to maxTagCloudTags.
    set maxTagCloudTags [get-website-config-setting maxTagCloudTags inf]
    if {![string is integer -strict $maxTagCloudTags]} {
        set maxTagCloudTags -1
    }
    set tags [get-tag-list \
            [get-website-config-setting sortTagsBy "name"] $maxTagCloudTags]

    append tagCloud {<nav class="tag-cloud"><h3>Tags</h3><ul>}

    foreach tag $tags {
        append tagCloud [format-link [get-tag-page $tag 0] 1 $tag]
    }
    append tagCloud {</ul></nav><!-- tag-cloud -->}

    return $tagCloud
}

proc format-footer {} {
    # Footer.
    set footer {}
    set copyright [string map [list \
        \$rootDirPath [get-current-page-data rootDirPath] \
        \$year [clock format [clock seconds] -format %Y]
    ] [get-website-config-setting copyright {}]]
    if {$copyright ne ""} {
        append footer "<div class=\"copyright\">$copyright</div>"
    }
    if {![get-current-page-setting hideFooter 0]} {
        append footer {<div class="powered-by"><small>Powered by <a href="https://github.com/dbohdan/tclssg">Tclssg</a> and <a href="http://getbootstrap.com/">Bootstrap</a></small></div>}
    }
    return $footer
}

proc format-comments {} {
    set commentsConfig [get-website-config-setting comments {}]
    set engine [dict-default-get none $commentsConfig engine]
    set result {}
    if {![get-current-page-setting hideUserComments 0]} {
        switch -nocase -- $engine {
            disqus { set result [format-comments-disqus] }
            none {}
            {} {}
            default { error "comments engine $engine not found" }
        }
    }
    if {$result eq ""} {
        return ""
    } else {
        return "<div class=\"comments\">$result</div>"
    }
}

proc format-comments-disqus {} {
    set commentsConfig [get-website-config-setting comments {}]
    set disqusShortname [dict-default-get {} $commentsConfig disqusShortname]
    set result [string map [list {%disqusShortname} $disqusShortname] {
        <div id="disqus_thread"></div>
        <script type="text/javascript">
        /* * * CONFIGURATION VARIABLES: EDIT BEFORE PASTING INTO YOUR WEBPAGE * * */
        var disqus_shortname = '%disqusShortname'; // required: replace example with your forum shortname
        /* * * DON'T EDIT BELOW THIS LINE * * */
        (function() {
            var dsq = document.createElement('script'); dsq.type = 'text/javascript'; dsq.async = true;
            dsq.src = '//' + disqus_shortname + '.disqus.com/embed.js';
            (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(dsq);
        })();
        </script>
        <noscript>Please enable JavaScript to view the <a href="http://disqus.com/?ref_noscript">comments powered by Disqus.</a></noscript>
        <a href="http://disqus.com" class="dsq-brlink">comments powered by <span class="logo-disqus">Disqus</span></a>
    }]
    return $result
}
