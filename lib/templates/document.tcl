# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::document {}
template-proc ::document::render {
    -articles       articles
    -collection     {collection 0}
    -collectionTop  {collectionTop 1}
    -input          input
    -nextPage       nextPage
    -output         output
    -pageNumber     {pageNumber 1}
    -prevPage       prevPage
    -root           root
} {<!DOCTYPE html>
<html>
  <head>
    <%! setting {head top} {} %>
    <meta charset="<%! config charset UTF-8 %>">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <% if {[setting description] ne {%NULL%}} { %>
      <meta name="description" content="<%! entities [setting description] %>">
    <% } %>

    <% if {[config url] ne {%NULL%}} { %>
      <link rel="canonical" href="<%! url-join [config url] $output %>">
    <% } %>
    <% if {$prevPage ne {}} { %>
      <link rel="prev" href="<%! entities [link-path $prevPage] %>">
    <% } %>
    <% if {$nextPage ne {}} { %>
      <link rel="next" href="<%! entities [link-path $nextPage] %>">
    <% } %>
    <% if {[setting favicon] ne {%NULL%}} { %>
      <link rel="icon" href="<%! file join $root [setting favicon] %>">
    <% } %>
    <% if {[blog-post?] && [config {rss enable} 0]} { %>
      <link rel="" type="application/rss+xml" href="<%! rss-feed %>">
    <% } %>
    <% if {$prevPage ne {%NULL%} || $nextPage ne {%NULL%} ||
           [setting noIndex 0]} {
      # Tell search engines to not index the tag pages or the blog index
      # beyond the first page.
    %>
      <meta name="robots" content="noindex">
    <% } %>
    <title><%! document-title %></title>

    <!-- Bootstrap core CSS -->
    <link rel="stylesheet" href="<%! file join $root vendor/bootstrap/css/bootstrap.min.css %>">
    <!-- Bootstrap theme -->
    <% if {[setting bootstrap] ne {%NULL%}} { %>
      <% if {[setting {bootstrap version} 3] ne {3}} {
        error "Bootstrap version must be \"3\""
      } %>
      <link rel="stylesheet" href="<%! file join $root [setting {bootstrap theme}] %>">
    <% } %>
    <!-- Custom stylesheets, if any -->
    <% foreach cssLink [setting customCSS {}] { %>
      <link href="<%! url-join $root $cssLink %>" rel="stylesheet">
    <% } %>
    <%! setting {head bottom} {} %>
  </head>

  <body>
    <%! setting {body top} {} %>
    <div class="navbar navbar-default">
      <div class="container">
        <div class="navbar-header">
          <button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".navbar-collapse">
            <span class="sr-only">Toggle navigation</span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </button>
          <a class="navbar-brand" href="<%= $root %>"><%! navbar-brand %></a>
        </div>
        <div class="navbar-collapse collapse">
          <ul class="nav navbar-nav">
          <% foreach {item link} [setting {navbar items} {}] { %>
            <li><a href="<%! file join $root $link %>"><%= $item %></a></li>
          <% } %>
          </ul>
        <% if {[blog-post?] && [config {rss enable} 0]} { %>
          <ul class="nav navbar-nav navbar-right">
            <li><a rel="alternate" type="application/rss+xml" href="<%! rss-feed %>"><%=
              ([setting tagPageTag] ne {%NULL%}) && ([config {rss tagFeeds} 0]) ?
              [lc "Tag RSS"] : [lc "RSS"]
            %></a></li>
          </ul>
        <% } %>
        </div><!--/.nav-collapse -->
      </div>
    </div>


    <div class="container">
      <div class="row">
        <% if {[sidebar-note?] ||
               ([blog-post?] && ([sidebar-links?] || [tag-cloud?]))} { %>
          <%
            lassign [content-and-sidebar-class] content_class sidebar_class
          %>
          <section class="<%= $content_class %>">
            <%! content %>
            <%! prev-next-link {« Newer posts} {Older posts »} %>
          </section>
          <div class="<%= $sidebar_class %> well content">
            <%! if {[sidebar-note?]} sidebar-note %>
            <%! if {[sidebar-links?]} sidebar-links %>
            <%! if {[tag-cloud?]} tag-cloud %>
          </div>
         <% } else { %>
          <section class="<%! setting {bootstrap gridClassPrefix} col-md- %>12 content">
            <%! content %>
            <%! prev-next-link {« Newer posts} {Older posts »} %>
          </section>
        <%  }
        %>
        <div>

        </div>
      </div>


      <%! comments %>


      <footer class="footer">
        <%! footer %>
      </footer>

    </div><!-- /container -->


    <!-- Bootstrap core JavaScript
    ================================================== -->
    <!-- Placed at the end of the document so the pages load faster -->
    <script src="<%! file join $root vendor/jquery/jquery.min.js %>"></script>
    <script src="<%! file join $root vendor/bootstrap/js/bootstrap.min.js %>"></script>
    <%! setting {body bottom} {} %>
</html>}

namespace eval ::document {
    proc content {} {
        upvar 1 articles articles \
                collection collection \
                collectionTop collectionTop \
                input input \
                root root

        set result {}
        set abbreviate [expr {
            $collection && [config abbreviate 1]
        }]
        foreach articleInput $articles {
            set content [db input get $articleInput cooked]

            append result [::article::render \
                -abbreviate $abbreviate \
                -articleInput $articleInput \
                -collection $collection \
                -collectionTop $collectionTop \
                -content $content \
                -root $root \
            ]

            set collectionTop 0
        }

        return $result
    }

    proc blog-post? {} {
        upvar 1 input input

        return [setting blogPost 0]
    }

    proc sidebar-links? {} {
        upvar 1 input input

        return [expr {
            [blog-post?] && [setting {sidebar links} 1]
        }]
    }

    proc sidebar-note? {} {
        upvar 1 input input

        return [setting {sidebar note enable} 1]
    }

    proc tag-cloud? {} {
        upvar 1 input input

        return [expr {
            [blog-post?] && [setting {sidebar tagCloud} 1]
        }]
    }

    proc content-and-sidebar-class {} {
        upvar 1 input input

        set class_prefix [setting {bootstrap gridClassPrefix} col-md-]
        set content_column_width [setting contentColumns 8]
        set sidebar_column_width [expr {12 - $content_column_width}]
        set content_class $class_prefix$content_column_width
        set sidebar_class $class_prefix$sidebar_column_width
        if {[setting {sidebar position} right] eq {left}} {
            append content_class " ${class_prefix}push-$sidebar_column_width"
            append sidebar_class " ${class_prefix}pull-$content_column_width"
        }
        return [list $content_class $sidebar_class]
    }

    proc pick-at-most {list limit} {
        if {[string is integer -strict $limit] && ($limit >= 0)} {
            return [lrange $list 0 [expr {$limit - 1}]]
        } else {
            return $list
        }
    }

    proc lc text {
        upvar 1 input input

        localization get [setting locale en_US] ::document $text
    }

    proc document-title {} {
        upvar 1 input input \
                pageNumber pageNumber

        set websiteTitle [config websiteTitle {}]

        set sep { | }

        set pageTitle [setting title {}]
        set showTitle [setting {show title} 1]
        set tagPageTag [setting tagPageTag {}]

        set result {}
        if {($showTitle) && ($pageTitle ne "")} {
            lappend result $pageTitle
        }

        if {$tagPageTag ne ""} {
            lappend result [format [lc {Posts tagged "%1$s"}] $tagPageTag]
        }

        if {[string is integer $pageNumber] && ($pageNumber > 1)} {
            lappend result [format [lc {page %1$s}] $pageNumber]
        }
        if {$websiteTitle ne ""} {
            lappend result $websiteTitle
        }

        return [entities [join $result $sep]]
    }

    proc rss-feed {} {
        upvar 1 input input \
                root root

        return [::rss-feed::rss-feed-path $input $root]
    }

    proc navbar-brand {} {
        upvar 1 input input

        return [setting {navbar brand} [config websiteTitle {}]]
    }

    proc sidebar-links {} {
        upvar 1 input input \
                root root

        # Blog sidebar.
        lassign [blog-index] blogIndex
        set sidebar {}

        append sidebar "<nav class=\"sidebar-links\"><h3>[lc Posts]</h3><ul>"

        set sidebarPosts \
            [db settings inputs-with-true-setting blogPost [list $blogIndex]]

        foreach destInput [pick-at-most $sidebarPosts \
                                        [config maxSidebarLinks]] {
            set output [input-to-output-path $destInput -includeIndexHtml 0]
            set title [file-setting $destInput title $output]
            append sidebar <li>[rel-link $output $title]</li>
        }
        append sidebar {</ul></nav><!-- sidebar-links -->}

        return $sidebar
    }


    proc sidebar-note {} {
        upvar 1 input input

        return [format \
                {<div class="sidebar-note">%s</div><!-- sidebar-note -->} \
                [setting {sidebar note content} {}]]
    }

    proc prev-next-link {prevLinkTitle nextLinkTitle} {
        upvar 1 input input \
                nextPage nextPage \
                prevPage prevPage \
                root root

        # Blog "next" and "previous" blog index page links.
        set links {}
        if {[blog-post?] && (($prevPage ne {}) || ($nextPage ne {}))} {
            append links {<nav class="prev-next text-center"><ul class="pager">}
            if {$prevPage ne {}} {
                append links "<li class=\"previous\">[rel-link \
                        $prevPage [lc $prevLinkTitle]]</li>"
            }
            if {$nextPage ne {}} {
                append links "<li class=\"next\">[rel-link \
                        $nextPage [lc $nextLinkTitle]]</li>"
            }
            append links {</ul></nav><!-- prev-next -->}
        }
        return $links
    }

    proc tag-cloud {} {
        upvar 1 root root \
                input input

        # Blog tag cloud. For each tag it links to pages that are tagged with it.
        set tagCloud {}

        # Limit the number of tags listed to according to maxTagCloudTags.
        set maxTagCloudTags [config maxTagCloudTags inf]
        if {![string is integer -strict $maxTagCloudTags]} {
            set maxTagCloudTags -1
        }
        set tags [db tags list [config sortTagsBy name] $maxTagCloudTags]

        append tagCloud "<nav class=\"tag-cloud\"><h3>[lc Tags]</h3><ul>"

        foreach tag $tags {
            append tagCloud <li>[tag-page-link $tag]</li>
        }
        append tagCloud {</ul></nav><!-- tag-cloud -->}

        return $tagCloud
    }

    proc footer {} {
        upvar 1 input input \
                root root

        set footer {}
        set copyright [string map [list \$root $root \
                                        \$year [clock format [clock seconds] \
                                                             -format %Y]] \
                                  [config copyright {}]]
        if {$copyright ne ""} {
            append footer "<div class=\"copyright\">$copyright</div>"
        }
        if {[setting {show footer} 1]} {
            append footer {<div class="powered-by"><small>Powered by <a href="https://github.com/tclssg/tclssg">Tclssg</a> and <a href="http://getbootstrap.com/">Bootstrap</a></small></div>}
        }
        return $footer
    }

    proc comments {} {
        upvar 1 input input

        set engine [setting {comments engine} none]
        set result {}
        if {[setting {comments show} 1]} {
            switch -nocase -- $engine {
                disqus { set result [comments-disqus] }
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

    proc comments-disqus {} {
        upvar 1 input input

        set disqusShortname [setting {comments disqus shortname} {}]
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
}
