#!/usr/bin/env tclsh
# A static website generator in Tcl.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require Tcl 8.5
package require struct
package require fileutil
package require textutil
package require textutil::expander

# Returns the content of file fname.
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

# Save content to file fname.
proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

# Transform a path relative to fromDir into the same path relative to toDir.
proc replace-path-root {path fromDir toDir} {
    # string map here is a hack to fix /./ making printed logs ugly.
    string map {/./ /} [
        file join $toDir [
            ::fileutil::relative $fromDir [file dirname $path]
        ] [
            file tail $path
        ]
    ]
}

# Return a value from dictionary like dict get would if it is there.
# Otherwise return the default value.
proc dict-default-get {default dictionary args} {
    if {[dict exists $dictionary {*}$args]} {
        dict get $dictionary {*}$args
    } else {
        return $default
    }
}

# If $varName exists return its value else return the default value.
proc get-default {varName default} {
    if {[interp eval templateInterp "info exists $varName"]} {
        return [interp eval templateInterp "set $varName"]
    } else {
        return $default
    }
}

# Trim indentation in multiline quoted text. Unlike textutil::undent this
# removes lines at the beginning and the end of the text that were turned blank
# by the unindentation.
proc trim-indentation {msg {whitespaceChars " "}} {
    set msgLines [split $msg "\n"]
    set maxLength [string length $msg]

    set regExp [subst -nocommands {([$whitespaceChars]*)[^$whitespaceChars]}]

    set indent [
        tcl::mathfunc::min {*}[
            struct::list mapfor x $msgLines {
                if {[regexp $regExp $x match whitespace]} {
                    string length $whitespace
                } else {
                    lindex $maxLength
                }
            }
        ]
    ]

    return [
        join [
            ltrim [
                struct::list mapfor x $msgLines {string range $x $indent end}
            ]
        ] "\n"
    ]
}

# Remove empty items at the beginning and the end of a list.
proc ltrim {list {emptyRegExp "^$"}} {
    set first [lsearch -not -regexp $list $emptyRegExp]
    set last [lsearch -not -regexp [lreverse $list] $emptyRegExp]
    return [
        if {$first == -1} {
            list
        } else {
            lrange $list $first end-$last
        }
    ]
}

# Set variable $name to $value in the template interpreter.
proc interp-set {name value} {
    interp eval templateInterp [format {set {%s} {%s}} $name $value]
}

# Set variable $key to $value in the template interpreter for each key-value
# pair in a dictionary.
proc interp-inject {dictionary} {
    dict for {key value} $dictionary {
        interp-set $key $value
    }
}

# Set up template interpreter and expander.
proc interp-up {} {
    upvar 1 scriptConfig scriptConfig

    # Create safe interpreter and expander for templates. Those are global.
    interp create -safe templateInterp

    foreach command {replace-path-root dict-default-get get-default \
                     textutil::indent} {
        interp alias templateInterp $command {} $command
    }

    if {![catch {::textutil::expander exp}]} {
        ::exp evalcmd {interp eval templateInterp}
        ::exp setbrackets {*}$scriptConfig(templateBrackets)
    }
}

# Tear down template interpreter.
proc interp-down {} {
    interp delete templateInterp
}

# Convert raw Markdown to HTML using an external Markdown processor.
proc markdown-to-html {markdown} {
    upvar 1 scriptConfig scriptConfig

    exec -- {*}$scriptConfig(markdownProcessor) << $markdown
}

# Get variables set in page using the "! variable value" syntax.
proc get-metadata-variables {rawContent} {
    global errorInfo
    set result {}
    foreach line [split $rawContent \n] {
        if {[string index $line 0] == "!"} {
            if {[catch {dict set result [lindex $line 1] [lindex $line 2]}]} {
                puts "error: syntax error when setting page variable: '$line'"
                puts "$errorInfo"
                exit 1
            }
            if {[llength $line] > 3} {
                puts "warning: trailing data after variable value: '$line'"
            }
        }
    }
    return $result
}

# Make HTML out of content plus template.
proc template-subst {template pageData websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set choppedContent {}
    foreach line [split [dict get $pageData rawContent] \n] {
        # Skip lines that set variables.
        if {[string index $line 0] != "!"} {
            set choppedContent "$choppedContent$line\n"
        }
    }

    interp-up
    interp-inject $websiteConfig
    # Page data overrides website config.
    interp-inject $pageData
    # Macroexpand content if needed then convert it from Markdown to HTML.
    if {[dict-default-get 0 $websiteConfig expandMacrosInPages]} {
        set choppedContent [::exp expand $choppedContent]
    }
    set cookedContent [markdown-to-html $choppedContent]
    # Expand template with content substituted in.
    interp-set content $cookedContent
    set result [::exp expand $template]
    interp-down

    return $result
}

# Process the page inputFile (a file containing Markdown + template code).
# put its rendered content into a template under the same path relative to
# outputDir that inputFile is relative to inputDir.
proc page-to-html {pageData template websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set inputFile [dict get $pageData inputFile]
    set outputFile [dict get $pageData outputFile]

    set subdir [file dirname $outputFile]

    if {![file isdir $subdir]} {
        puts "creating directory $subdir"
        file mkdir $subdir
    }

    puts "processing page file $inputFile into $outputFile"
    set output [
        template-subst $template $pageData $websiteConfig
    ]
    write-file $outputFile $output
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

# Process input files in inputDir to produce static website in outputDir.
proc compile-website {inputDir outputDir websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set contentDir [file join $inputDir $scriptConfig(contentDirName)]

    # Build page data.
    set pages {}
    foreach file [fileutil::findByPattern $contentDir -glob *.md] {
        dict set pages $file inputFile $file
        dict set pages $file outputFile [
            file rootname [
                replace-path-root $file $contentDir $outputDir
            ]
        ].html
        # May want to change this preloading behavior for very large websites.
        dict set pages $file rawContent [read-file $file]
        dict set pages $file variables [
            get-metadata-variables [
                dict get $pages $file rawContent
            ]
        ]
    }

    # Read template for $inputDir. Can later be made per-directory or
    # metadata-based.
    set template [
        read-file [
            file join $inputDir \
                      $scriptConfig(templateDirName) \
                      $scriptConfig(templateFileName) \
        ]
    ]

    dict set websiteConfig pages $pages
    dict set websiteConfig pages tags [tag-list $pages]

    # Process page files into HTML output.
    dict for {file ___} $pages {
        # Links to other page relative to the current.
        set outputFile [dict get $pages $file outputFile]
        set pageLinks {}
        dict for {otherFile otherMetadata} $pages {
            # pageLinks maps page id (= input FN for not) to relative link to
            # it.
            lappend pageLinks $otherFile [
                ::fileutil::relative [
                    file dirname $outputFile
                ] [
                    dict get $otherMetadata outputFile
                ]
            ]
        }
        dict set pages $file pageLinks $pageLinks
        dict set pages $file rootDirLink [
            ::fileutil::relative [
                file dirname $outputFile
            ] $outputDir
        ]
        dict set websiteConfig currentPageId $file

        page-to-html [dict get $pages $file] $template $websiteConfig
    }

    # Copy static files verbatim.
    foreach file [
        fileutil::find [file join $inputDir $scriptConfig(staticDirName)]
    ] {
        if {[file isfile $file]} {
            set destFile [
                replace-path-root $file [
                    file join $inputDir $scriptConfig(staticDirName)
                ] $outputDir
            ]
            puts "copying static file $file to $destFile"
            file copy -force $file $destFile
        }
    }
}

# Load website configuration file from directory.
proc load-config {sourceDir} {
    upvar 1 scriptConfig scriptConfig
    upvar 1 websiteConfig websiteConfig

    set websiteConfig [
        read-file [
            file join $sourceDir $scriptConfig(websiteConfigFileName)
        ]
    ]
    puts "Loaded config file:\n[textutil::indent $websiteConfig {    }]\n"
}

proc main {argv0 argv} {
    # Configuration.
    set scriptConfig(markdownProcessor) \
        {perl scripts/Markdown_1.0.1/Markdown.pl}

    set scriptConfig(contentDirName) pages
    set scriptConfig(templateDirName) templates
    set scriptConfig(staticDirName) static
    set scriptConfig(templateFileName) default.thtml
    set scriptConfig(websiteConfigFileName) website.conf

    set scriptConfig(templateBrackets) {<% %>}

    set sourceDir [lindex $argv 1]
    set destDir [lindex $argv 2]

    # init command.
    switch -exact -- [lindex $argv 0] {
        init {
            foreach dir [
                list $scriptConfig(contentDirName) \
                     $scriptConfig(templateDirName) \
                     $scriptConfig(staticDirName) \
                     [file join $scriptConfig(contentDirName) blog]
            ] {
                file mkdir [file join $sourceDir $dir]
            }
            file mkdir $destDir

            set websiteConfigFile [
                file join $sourceDir $scriptConfig(websiteConfigFileName)
            ]

            proc write-file-if-not-there {file content} {
                if {![file isfile $file]} {
                    write-file $file $content
                }
            }

            set indexPageFile [
                file join $sourceDir $scriptConfig(contentDirName) index.md
            ]
            set blogIndexPageFile [
                file join $sourceDir $scriptConfig(contentDirName) blog index.md
            ]

            write-file-if-not-there $websiteConfigFile [
                subst -nocommands [
                    trim-indentation {
                        websiteTitle {SSG Test}
                        indexPage {$indexPageFile}
                        tagPage {$blogIndexPageFile}
                    }
                ]
            ]
            write-file-if-not-there $indexPageFile [
                trim-indentation {
                    ! pageTitle {Hello, World!}
                    This is a sample page.
                }
            ]
            write-file-if-not-there $blogIndexPageFile [
                trim-indentation {
                    ! blogEntry 1
                    ! hideFromList 1
                    ! hideTitle 1
                    ! showTagCloud 1
                    ! hidePostTags 1
                    This is your blog's index tag.
                }
            ]
            exit 0
        }
        build {
            load-config $sourceDir

            if {[file isdir $sourceDir]} {
                compile-website $sourceDir $destDir $websiteConfig
            } else {
                puts "couldn't access directory \"$sourceDir\""
                exit 1
            }
        }
        upload-copy {
            load-config $sourceDir

            set uploadDest [dict get $websiteConfig uploadDestCopy]

            foreach file [fileutil::find $destDir {file isfile}] {
                set destFile [replace-path-root $file $destDir $uploadDest]
                puts "copying $file to $destFile"
                if {![file isdir [file dirname $destFile]]} {
                    file mkdir [file dirname $destFile]
                }
                file copy -force $file $destFile
            }
            exit 0
        }
        upload-ftp {
            puts "not implemented"
            exit 1
        }
        default {
            puts [concat "usage: $argv0 (init|build|upload-copy|upload-ftp) " \
                         "sourceDir destDir"]
        }
    }
}

main $argv0 $argv
