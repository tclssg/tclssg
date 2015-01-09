# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc get-current-page-variable {name default} {
    global currentPageId
    return [get-page-variable $currentPageId $name $default]
}

proc relative-link {id} {
    global currentPageId
    return [get-page-link $currentPageId $id]
}

proc link-or-nothing {websiteVarName} {
    set targetId [get-website-config-variable $websiteVarName {}]
    if {$targetId ne ""} {
        lindex [relative-link $targetId]
    } else {
        lindex {}
    }
}

set rootDirPath [get-page-data $currentPageId rootDirPath]
set indexLink [link-or-nothing indexPage]
set blogIndexLink [link-or-nothing blogIndexPage]

proc with-cache script {
    global currentPageId
    with-cache-for-filename [get-page-data $currentPageId outputFile] $script
}

proc blog-post? {} {
    get-current-page-variable blogPost 0
}

proc format-link {id {li 1} {customTitle ""}} {
    set link [relative-link $id]
    if {$customTitle ne ""} {
        set title $customTitle
    } else {
        set title [get-page-variable $id title $link]
    }

    set linkHtml "<a href=\"$link\">$title</a>"
    if {$li} {
        set linkHtml "<li>$linkHtml</li>"
    }
    return $linkHtml
}
