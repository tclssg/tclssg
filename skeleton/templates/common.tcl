# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

set rfc822 {%a, %d %b %Y %H:%M:%S GMT}

proc get-current-page-setting {name default} {
    global currentPageId
    return [get-page-setting $currentPageId $name $default]
}

proc get-current-page-data {name} {
    global currentPageId
    return [get-page-data $currentPageId $name]
}

proc absolute-link {id} {
    set url [get-website-config-setting url ""]
    if {$url eq ""} {
        error "using absolute-link requires that url be set in website config"
    }
    set outputDir [get-website-config-setting outputDir ""]
    return $url[replace-path-root [get-page-data $id outputFile] $outputDir ""]
}

proc relative-link {id} {
    global currentPageId
    return [get-page-link $currentPageId $id]
}

proc link-or-nothing {websiteVarName} {
    set targetId [get-website-config-setting $websiteVarName {}]
    if {$targetId ne ""} {
        lindex [relative-link $targetId]
    } else {
        lindex {}
    }
}

set rootDirPath [get-page-data $currentPageId rootDirPath]
set indexLink [link-or-nothing indexPageId]
set blogIndexLink [link-or-nothing blogIndexPageId]

proc with-cache script {
    global currentPageId
    with-cache-for-filename [get-page-data $currentPageId outputFile] $script
}

proc blog-post? {} {
    get-current-page-setting blogPost 0
}

proc format-link {id {li 1} {customTitle ""}} {
    set link [relative-link $id]
    if {$customTitle ne ""} {
        set title $customTitle
    } else {
        set title [get-page-setting $id title $link]
    }

    set linkHtml "<a href=\"$link\">$title</a>"
    if {$li} {
        set linkHtml "<li>$linkHtml</li>"
    }
    return $linkHtml
}

proc subst-if-not-empty args {
    set values [lrange $args 0 end-1]
    set str [lindex $args end]
    foreach value $values {
        if {$value eq ""} {
            return ""
        }
    }
    return [uplevel 1 [list subst $str]]
}