# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::rss-feed {}
template-proc ::rss-feed::render {
    -articles       articles
    -collection     {collection 0}
    -collectionTop  {collectionTop 1}
    -input          input
    -nextPage       nextPage
    -output         output
    -pageNumber     {pageNumber 1}
    -prevPage       prevPage
    -root           root
} {<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">

<channel>
<atom:link href="<%! rss-feed-path $input $root %>" rel="self" type="application/rss+xml" />

<title><%! entities [::document::document-title] %></title>
<link><%! link-path [input-to-output-path $input] 1 %></link>
<description><%! entities [config {rss feedDescription} {}] %></description>
<language><%! lindex [split [setting locale en_US] _] 0 %></language>
<%! copyright %>
<%! last-build-date %>
<generator>Tclssg <%! lindex [version] 0 %></generator>
<%! content %>
</channel>
</rss>
}

namespace eval ::rss-feed {
    variable rfc822 {%a, %d %b %Y %H:%M:%S GMT}

    proc content {} {
        upvar 1 articles articles \
                articleInput articleInput \
                collectionTop collectionTop

        set result {}
        foreach articleInput $articles {
            if {$collectionTop} {
                set collectionTop 0
                continue
            }
            append result [item -articleInput $articleInput]
        }
        return $result
    }

    template-proc item {
        -articleInput  articleInput
    } {<%
        variable rfc822

        set title [article-setting title {}]
        set timestamp [db input get $articleInput timestamp]
        set link [link-path [input-to-output-path $articleInput] 1]
        set content [db input get $articleInput cooked]
        %>
        <item>
          <%= $title ne "" ? "<title><!\[CDATA\[$title\]\]></title>" : "" %>
          <link><%! entities $link %></link>
          <guid><%! entities $link %></guid>
          <description>
            <![CDATA[<%! ::article::abbreviate-article $content \
                                                       [config abbreviate 1] \
                                                       1 %>]]>
          </description>
          <pubDate><%! clock format $timestamp \
                                    -format $rfc822 \
                                    -timezone :UTC %></pubDate>
        </item>
    }

    proc copyright {} {
        upvar 1 input input

        set copyright [entities [setting copyright {}]]]
        return [expr {
            $copyright eq {} ?
            {} :
            "<copyright><!\[CDATA\[$copyright\]\]></copyright>"
        }]
    }

    proc rss-feed-path {input root} {
        set tagPageTag [db settings preset-get $input tagPageTag {}]

        if {$tagPageTag eq {}} {
            return [file join $root blog/rss.xml]
        }

        set path [input-to-output-path $input]

        if {[db config get prettyURLs 0]} {
            return [file join $root [file dirname $path] rss.xml]
        } else {
            # Get the output path without the page number added to it.
            return [file join $root [file rootname $path]].xml
        }
    }

    proc last-build-date {} {
        variable rfc822
        set date [clock format [config buildTimestamp] \
                               -format $rfc822 \
                               -timezone :UTC]
        return <lastBuildDate>$date</lastBuildDate>
    }
}
