#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require Tcl 8.5
package require struct
package require fileutil
package require textutil
package require textutil::expander

namespace eval templating {
    namespace export *
    namespace ensemble create

    # Convert raw Markdown to HTML using an external Markdown processor.
    proc markdown-to-html {markdown} {
        exec -- {*}$::tclssg::config(markdownProcessor) << $markdown
    }

    # Make HTML out of content plus article template.
    proc prepare-content {rawContent pageData websiteConfig} {


        set choppedContent [lindex [get-page-variables $rawContent] 1]
        templating interpreter up [dict get $websiteConfig inputDir]
        templating interpreter inject $websiteConfig
        # Page data overrides website config.
        templating interpreter inject $pageData
        # Macroexpand content if needed then convert it from Markdown to HTML.
        if {[dict-default-get 0 $websiteConfig expandMacrosInPages]} {
            set choppedContent [::templating::exp expand $choppedContent]
        }
        templating interpreter down
        set cookedContent [markdown-to-html $choppedContent]
        return $cookedContent
    }

    # Expand template with (HTML) content.
    proc expand {template cookedContent pageData websiteConfig} {
        templating interpreter up [dict get $websiteConfig inputDir]
        templating interpreter inject $websiteConfig
        # Page data overrides website config.
        templating interpreter inject $pageData

        # Expand template with content substituted in.
        templating interpreter var-set content $cookedContent
        set result [::templating::exp expand $template]
        templating interpreter down

        return $result
    }

    # If $varName exists return its value in the interpreter templateInterp
    # else return the default value.
    proc website-var-get-default {varName default} {
        if {[interp eval templateInterp "info exists $varName"]} {
            return [interp eval templateInterp "set $varName"]
        } else {
            return $default
        }
    }

    namespace eval interpreter {
        namespace export *
        namespace ensemble create

        # Set variable $name to $value in the template interpreter.
        proc var-set {name value} {
            interp eval templateInterp [format {set {%s} {%s}} $name $value]
        }

        # Set variable $key to $value in the template interpreter for each key-
        # value pair in a dictionary.
        proc inject {dictionary} {
            dict for {key value} $dictionary {
                var-set $key $value
            }
        }

        # Set up template interpreter and expander.
        proc up {inputDir} {


            # Create safe interpreter and expander for templates. Those are
            # global.
            interp create -safe templateInterp

            foreach command {
                replace-path-root
                dict-default-get
                textutil::indent
                slugify
                choose-dir
                puts
            } {
                interp alias templateInterp $command {} $command
            }
            interp alias templateInterp website-var-get-default \
                    {} ::templating::website-var-get-default
            interp eval templateInterp {
                proc = varName { return $varName }
            }

            foreach builtIn {source} {
                interp expose templateInterp $builtIn
            }

            # Allow templates to source Tcl files with directory failover.
            interp alias templateInterp interp-source {} \
                    ::templating::interpreter::source-dirs [
                        list [
                            file join $inputDir \
                                      $::tclssg::config(templateDirName)
                        ] [
                            file join $::tclssg::config(skeletonDir) \
                                      $::tclssg::config(templateDirName)
                        ]
                    ]

            if {![catch {::textutil::expander ::templating::exp}]} {
                ::templating::exp evalcmd {interp eval templateInterp}
                ::templating::exp setbrackets \
                        {*}$::tclssg::config(templateBrackets)
            }
        }

        # Tear down template interpreter.
        proc down {} {
            interp delete templateInterp
        }

        # Source fileName into templateInterp from the first directory out of
        # dirs where it exists.
        proc source-dirs {dirs fileName} {
            set command [
                subst -nocommands {
                    source [
                        choose-dir $fileName {$dirs}
                    ]
                }
            ]
            interp eval templateInterp $command
        }
    } ;# namespace interpreter
} ;# namespace templating

# Format one HTML article out of a page according to an article template.
proc format-article {pageData articleTemplate websiteConfig} {
    templating expand $articleTemplate [dict get $pageData cookedContent] \
            $pageData $websiteConfig
}

# Format one HTML document according to an document template. Document content
# is taken from in the variable content while page variables are taken from
# pageData.
proc format-document {content pageData documentTemplate websiteConfig} {
    templating expand $documentTemplate $content $pageData $websiteConfig
}

# Generate an HTML document out pages and store it as outputFile.  Articles are
# taken from those pages in the dict pages the ids of which are listed in
# pageIds.
proc generate-html-file {outputFile pages pageIds articleTemplate
        documentTemplate websiteConfig} {
    set inputFiles {}
    set gen {}
    foreach id $pageIds {
        append gen [format-article [dict get $pages $id] $articleTemplate \
                $websiteConfig]
        lappend inputFiles [dict get $pages $id inputFile]
    }

    set subdir [file dirname $outputFile]

    if {![file isdir $subdir]} {
        puts "creating directory $subdir"
        file mkdir $subdir
    }

    puts "processing page file $inputFiles into $outputFile"
    # Take page settings form the first page.
    set output [
        format-document $gen [dict get $pages [lindex $pageIds 0]] \
                $documentTemplate $websiteConfig
    ]
    fileutil::writeFile $outputFile $output
}

# Generate tag list in the format of dict tag -> {id id id...}.
proc tag-list {pages} {
    set tags {}
    dict for {page pageData} $pages {
        foreach tag [dict-default-get {} $pageData variables tags] {
            dict lappend tags $tag $page
        }
    }
    return $tags
}

# Read template from $inputDir or ::tclssg::config(skeletonDir). The template is
# either the default (determined by $::tclssg::config(templateFileName)) or the
# one specified in the configuration file. Can later be made per-directory
# or metadata-based.
proc read-template-file {inputDir varName websiteConfig} {


    set templateFile [
        choose-dir [
            dict-default-get $::tclssg::config($varName) \
                             $websiteConfig $varName
        ] [
            list [
                file join $inputDir \
                          $::tclssg::config(templateDirName)
            ] [
                file join $::tclssg::config(skeletonDir) \
                          $::tclssg::config(templateDirName)
            ]
        ]
    ]
    return [read-file $templateFile]
}

# Appends to ordered dict pagesVarName a page or a series of pages that collect
# the articles of those pages that are listed in pageIds. The number of pages
# added equals ([llength pageIds] / $blogPostsPerFile) rounded to the nearest
# whole number. Page settings are taken from the page topPageId and its content
# is prepended to every output page. Used for making the blog index page.
proc add-article-collection {pagesVarName pageIds topPageId websiteConfig} {
    upvar 1 $pagesVarName pages

    set blogPostsPerFile \
            [dict-default-get 10 $websiteConfig blogPostsPerFile]
    set i 0
    set currentPageArticles {}
    set pageNumber 0

    set topPageData [dict get $pages $topPageId]
    # Needed to move the key to the end of the dict.
    dict unset pages $topPageId

    set prevIndexPageId {}

    foreach id $pageIds {
        lappend currentPageArticles $id
        # If there is enough posts for a page or this is the last post...
        if {($i == $blogPostsPerFile - 1) || \
                    ($id eq [lindex $pageIds end])} {
            set newPageId \
                    [add-number-before-extension $topPageId $pageNumber]
            puts -nonewline \
                    "adding article collection page $pageNumber ($newPageId) "

            set newPageData $topPageData
            dict with newPageData {
                set currentPageId $newPageId
                set inputFile \
                        [add-number-before-extension $inputFile $pageNumber]
                set outputFile \
                        [add-number-before-extension $outputFile $pageNumber]
            }
            dict set newPageData articlesToAppend $currentPageArticles
            if {$pageNumber > 0} {
                dict set newPageData variables prevPage $prevIndexPageId
                dict set pages $prevIndexPageId variables nextPage $newPageId
            }
            # Hack alert! Add key while keep dictionary ordering. This is
            # needed, among other things, to generate the pageLinks for
            # normal pages before they are included into multiarticle ones.
            lappend pages $newPageId $newPageData
            puts "with posts $currentPageArticles"
            set prevIndexPageId $newPageId
            set i 0
            set currentPageArticles {}
            incr pageNumber
        } else {
            incr i
        }
    }

}

# Process input files in inputDir to produce static website in outputDir.
proc compile-website {inputDir outputDir websiteConfig} {
    dict set websiteConfig inputDir $inputDir
    set contentDir [file join $inputDir $::tclssg::config(contentDirName)]

    # Build page data from input files.
    set pages {}
    foreach file [fileutil::findByPattern $contentDir -glob *.md] {
        set id [::fileutil::relative $contentDir $file]
        dict set pages $id currentPageId $id
        dict set pages $id inputFile $file
        dict set pages $id outputFile [
            file rootname [replace-path-root $file $contentDir $outputDir]
        ].html
        # May want to change this preloading behavior for very large websites.
        dict set pages $id rawContent [read-file $file]
        dict set pages $id variables [
            lindex [get-page-variables [dict get $pages $id rawContent]] 0
        ]
        dict set pages $id variables dateUnix [
            incremental-clock-scan [
                dict-default-get {} $pages $id variables date
            ]
        ]
    }

    # Read template files.
    set articleTemplate [
        read-template-file $inputDir articleTemplateFileName $websiteConfig
    ]
    set documentTemplate [
        read-template-file $inputDir documentTemplateFileName $websiteConfig
    ]

    # Sort pages by date.
    set pages [
        dict-sort $pages {variables dateUnix} 0 \
                {-decreasing}
    ]

    # Filter blog posts out of pages. This preserves the ordering.
    set posts [
        dict filter $pages script {id pageData} {
            dict-default-get 0 $pageData variables blogPost
        }
    ]

    # Add chronological blog index.
    set blogIndexPage [dict get $websiteConfig blogIndexPage]
    add-article-collection pages [dict keys $posts] \
            $blogIndexPage $websiteConfig

    dict set websiteConfig pages $pages
    dict set websiteConfig tags [tag-list $pages]

    ## Add tag pages.
    # foreach {tag taggedPages} [dict get $websiteConfig tags] {
    #     lappend blog/$tag.md [dict get $pages $blogIndexPage]
    #     add-article-collection pages $taggedPages \
    #         $blogIndexPage $websiteConfig
    # }

    dict for {id pageData} $pages {
        # Expand templates, first for the article then for the HTML document.
        # This modifies pages.
        dict set pages $id cookedContent [
            templating prepare-content \
                    [dict get $pages $id rawContent] \
                    [dict get $pages $id] \
                    $websiteConfig
        ]
    }

    # Process page files into HTML output.
    dict for {id _} $pages {
        # Links to other page relative to the current.
        set outputFile [dict get $pages $id outputFile]
        set pageLinks {}
        dict for {otherFile otherMetadata} $pages {
            # pageLinks maps page id (= input FN relative to $contentDir) to
            # relative link to it.
            lappend pageLinks $otherFile [
                ::fileutil::relative [
                    file dirname $outputFile
                ] [
                    dict get $otherMetadata outputFile
                ]
            ]
        }

        # Store links to other pages and website root path relative to the
        # current page.
        dict set pages $id pageLinks $pageLinks
        dict set pages $id rootDirPath [
            ::fileutil::relative [
                file dirname $outputFile
            ] $outputDir
        ]

        generate-html-file \
                [dict get $pages $id outputFile] \
                $pages \
                [list $id \
                        {*}[dict-default-get {} $pages $id articlesToAppend]] \
                $articleTemplate \
                $documentTemplate \
                $websiteConfig
    }

    set blogPosts {}
    # Can't use $pages here because by now they may have lost how they
    # sorted.
    foreach {id _} [dict get $websiteConfig pages] {
        if {$id eq [dict-default-get {} $websiteConfig blogIndexPage]} {
            continue
        }
        set pageData [dict get $pages $id]
        if {[dict-default-get 0 $pageData variables blogPost]} {
            lappend blogPosts $pageData
        }
    }

    # Copy static files verbatim.
    copy-files [file join $inputDir $::tclssg::config(staticDirName)] $outputDir 1
}

# Load website configuration file from directory.
proc load-config {inputDir {verbose 1}} {
    set websiteConfig [
        read-file [file join $inputDir $::tclssg::config(websiteConfigFileName)]
    ]

    # Show loaded config to user (without the password values).
    if {$verbose} {
        puts "Loaded config file:"
        puts [
            textutil::indent [
                dict-format [
                    obscure-password-values $websiteConfig
                ]
            ] {    }
        ]
    }

    return $websiteConfig
}

namespace eval tclssg {
    namespace export *
    namespace ensemble create -prefixes 0 -unknown ::tclssg::unknown

    proc init {inputDir outputDir options} {
        foreach dir [
            list $::tclssg::config(contentDirName) \
                 $::tclssg::config(templateDirName) \
                 $::tclssg::config(staticDirName) \
                 [file join $::tclssg::config(contentDirName) blog]
        ] {
            file mkdir [file join $inputDir $dir]
        }
        file mkdir $outputDir

        # Copy project skeleton.
        set skipRegExp [
            if {"templates" in $options} {
                lindex {}
            } else {
                lindex {.*templates.*}
            }
        ]
        copy-files $::tclssg::config(skeletonDir) $inputDir 0 $skipRegExp
        exit 0
    }

    proc build {inputDir outputDir options} {
        set websiteConfig [load-config $inputDir]

        if {[file isdir $inputDir]} {
            compile-website $inputDir $outputDir $websiteConfig
        } else {
            puts "couldn't access directory \"$inputDir\""
            exit 1
        }
    }

    proc clean {inputDir outputDir options} {
        foreach file [fileutil::find $outputDir {file isfile}] {
            puts "deleting $file"
            file delete $file
        }
    }

    proc update {inputDir outputDir options} {
        set updateSourceDirs [
            list $::tclssg::config(staticDirName) {static files}
        ]
        if {"templates" in $options} {
            lappend updateSourceDirs \
                    $::tclssg::config(templateDirName) \
                    templates
        }
        foreach {dir descr} $updateSourceDirs {
            puts "updating $descr"
            copy-files [
                file join $::tclssg::config(skeletonDir) $dir
            ] [
                file join $inputDir $dir
            ] 2
        }
    }

    proc deploy-copy {inputDir outputDir options} {
        set websiteConfig [load-config $inputDir]

        set deployDest [dict get $websiteConfig deployCopyPath]

        copy-files $outputDir $deployDest 1
        exit 0
    }

    proc deploy-ftp {inputDir outputDir options} {
        set websiteConfig [load-config $inputDir]

        package require ftp
        global errorInfo

        set conn [
            ::ftp::Open \
                    [dict get $websiteConfig deployFtpServer] \
                    [dict get $websiteConfig deployFtpUser] \
                    [dict get $websiteConfig deployFtpPassword] \
                    -port [
                        dict-default-get 21 $websiteConfig deployFtpPort
                    ] \
                    -mode passive
        ]
        set deployFtpPath [dict get $websiteConfig deployFtpPath]

        ::ftp::Type $conn binary

        foreach file [fileutil::find $outputDir {file isfile}] {
            set destFile [replace-path-root $file $outputDir $deployFtpPath]
            set dir [file dirname $destFile]
            if {[ftp::Cd $conn $dir]} {
                ftp::Cd $conn /
            } else {
                puts "creating directory $dir"
                ::ftp::MkDir $conn $dir
            }
            puts "uploading $file as $destFile"
            if {![::ftp::Put $conn $file $destFile]} {
                puts "upload error: $errorInfo"
                exit 1
            }
        }
        ::ftp::Close $conn
    }

    proc open {inputDir outputDir options} {
        set websiteConfig [load-config $inputDir]

        package require platform
        set platform [platform::generic]

        set openCommand [
            switch -glob -- $platform {
                *win* { lindex {cmd /c start ""} }
                *osx* { lindex open }
                default { lindex xdg-open }
            }
        ] ;# The default is the freedesktop.org open command for *nix.
        exec -- {*}$openCommand [
            file rootname [
                file join $outputDir [
                    dict-default-get index.md $websiteConfig indexPage
                ]
            ]
        ].html
    }

    proc version {inputDir outputDir options} {
        puts $::tclssg::config(version)
    }

    proc help {{inputDir ""} {outputDir ""} {options ""}} {
        global argv0

        puts [
            subst -nocommands [
                trim-indentation {
                    usage: $argv0 <command> [options] [inputDir [outputDir]]

                    Possible commands are:
                        init        create project skeleton
                            --templates copy template files as well
                        build       build static website
                        clean       delete files in outputDir
                        update      selectively replace static
                                    files (e.g., CSS) in inputDir with
                                    those of project skeleton
                            --templates update template files as well
                        deploy-copy copy result to location set in config
                        deploy-ftp  upload result to FTP server set in
                                    config
                        open        open index page in default browser
                        version     print version number and exit
                        help        show this message

                    inputDir defaults to "$::tclssg::config(defaultInputDir)"
                    outputDir defaults to "$::tclssg::config(defaultOutputDir)"
                }
            ]
        ]
    }

    proc configure {{scriptLocation .}} {
        # What follows is the configuration that is generally not supposed to vary
        # from project to project.
        set ::tclssg::config(scriptLocation) $scriptLocation

        set ::tclssg::config(markdownProcessor) [
            concat perl [
                file join $::tclssg::config(scriptLocation) \
                        external Markdown_1.0.1 Markdown.pl
            ]
        ]

        set ::tclssg::config(contentDirName) pages
        set ::tclssg::config(templateDirName) templates
        set ::tclssg::config(staticDirName) static
        set ::tclssg::config(articleTemplateFileName) article.thtml
        set ::tclssg::config(documentTemplateFileName) bootstrap.thtml
        set ::tclssg::config(websiteConfigFileName) website.conf
        set ::tclssg::config(skeletonDir) \
                [file join $::tclssg::config(scriptLocation) skeleton]
        set ::tclssg::config(defaultInputDir) [file join "website" "input"]
        set ::tclssg::config(defaultOutputDir) [file join "website" "output"]

        set ::tclssg::config(templateBrackets) {<% %>}

        puts [array names ::tclssg::config]
    }

    proc unknown args {
        return ::tclssg::help
    }
} ;# namespace tclssg

proc main {argv0 argv} {
    tclssg configure [file dirname $argv0]

    # Utility functions.
    source [file join $::tclssg::config(scriptLocation) utils.tcl]
    set ::tclssg::config(version) [
        string trim [
            read-file [file join $::tclssg::config(scriptLocation) VERSION]
        ]
    ]

    # Version.
    catch {
        set currentPath [pwd]
        cd $::tclssg::config(scriptLocation)
        append ::tclssg::config(version) \
                " (commit [string range [exec git rev-parse HEAD] 0 9])"
        cd $currentPath
    }

    # Get command line options, including directories to operate on.
    set command [unqueue argv]

    set options {}
    while {[lindex $argv 0] ne "--" && [string match -* [lindex $argv 0]]} {
        lappend options [string trimleft [unqueue argv] -]
    }
    set inputDir [unqueue argv]
    set outputDir [unqueue argv]

    # Defaults for inputDir and outputDir.
    if {$inputDir eq "" && $outputDir eq ""} {
        set inputDir $::tclssg::config(defaultInputDir)
        set outputDir $::tclssg::config(defaultOutputDir)
    } elseif {$outputDir eq ""} {
        catch {
            set outputDir [
                dict-default-get {} [
                    load-config $inputDir 0
                ] outputDir
            ]
            # Make relative path from config relative to inputDir.
            if {$outputDir ne "" && [path-is-relative? $outputDir]} {
                set outputDir [
                    ::fileutil::lexnormalize [
                        file join $inputDir $outputDir
                    ]
                ]
            }
        }
        if {$outputDir eq ""} {
            puts [
                trim-indentation {
                    error: no outputDir given.

                    please either a) specify both inputDir and outputDir or
                                  b) set outputDir in your configuration file.
                }
            ]
            exit 1
        }
    }

    # Execute command.
    tclssg $command $inputDir $outputDir $options
}

# Check if we were run as the primary script by the interpreter.
# Based on http://wiki.tcl.tk/40097.
proc main-script? {} {
    global argv0

    if {[info exists argv0]
     && [file exists [info script]] && [file exists $argv0]} {
        file stat $argv0 argv0Info
        file stat [info script] scriptInfo
        expr {$argv0Info(dev) == $scriptInfo(dev)
           && $argv0Info(ino) == $scriptInfo(ino)}
    } else {
        return 0
    }
}

if {[main-script?]} {
    main $argv0 $argv
}
