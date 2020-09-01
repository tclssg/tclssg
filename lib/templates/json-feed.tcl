# Tclssg, a static website generator.
# Copyright (c) 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::json-feed {}

template-proc ::json-feed::render {
    -articles       articles
    -collection     {collection 0}
    -collectionTop  {collectionTop 1}
    -input          input
    -nextPage       nextPage
    -output         output
    -pageNumber     {pageNumber 1}
    -prevPage       prevPage
    -root           root
    -tagPage        {tagPage {}}
} {<%
    set feed {}

    dict set feed version \"https://jsonfeed.org/version/1.1\"
    dict set feed title [json::write string \
        [document-title $input $pageNumber] \
    ]

    set homePageURL [link-path [input-to-output-path [expr {
        $tagPage eq {} ? $input : $tagPage
    }]] true]
    dict set feed home_page_url [json::write string $homePageURL]
    dict set feed feed_url [json::write string [link-path $output true]]

    set descr [config {feeds description} {}]
    if {$descr ne {}} {
        dict set feed description [json::write string $descr]
    }

    set items {}
    foreach articleInput [lrange $articles 1 end] {
        set item {}

        dict set item title [json::write string [article-setting title {}]]
        set time [clock format [db input get $articleInput timestamp] \
            -format {%Y-%m-%dT%H:%M:%SZ} \
            -timezone :UTC \
        ]

        dict set item date_published [json::write string $time]

        set link [json::write string \
            [link-path [input-to-output-path $articleInput] 1] \
        ]
        dict set item id $link
        dict set item url $link

        set content [db input get $articleInput cooked]
        set abbr [::article::abbreviate-article \
            $content \
            [config abbreviate 1] \
            1 \
        ]
        dict set item content_html [json::write string $abbr]

        lappend items [json::write object {*}$item]
    }

    dict set feed items [json::write array {*}$items]
    %><%! json::write object {*}$feed %>}

proc ::json-feed::path {input root} {
    feed-path $input $root feed.json .feed.json
}
