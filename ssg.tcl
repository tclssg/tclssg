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

# If $varName exists return its value in the interpreter templateInterp
# else return the default value.
proc get-default {varName default} {
    if {[interp eval templateInterp "info exists $varName"]} {
        return [interp eval templateInterp "set $varName"]
    } else {
        return $default
    }
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
proc interp-up {inputDir} {
    upvar 1 scriptConfig scriptConfig

    # Create safe interpreter and expander for templates. Those are global.
    interp create -safe templateInterp

    foreach command {replace-path-root dict-default-get  \
                     get-default textutil::indent slugify
                     choose-dir interp-source puts} {
        interp alias templateInterp $command {} $command
    }
    foreach builtIn {source} {
        interp expose templateInterp $builtIn
    }

    # Allow templates to source Tcl files with directory failover.
    interp alias templateInterp interp-source {} interp-source-dirs [
        list [
            file join $inputDir \
                      $scriptConfig(templateDirName)
        ] [
            file join $scriptConfig(skeletonDir) \
                      $scriptConfig(templateDirName)
        ]
    ]

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

    interp-up [dict get $websiteConfig inputDir]
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

# Process the raw content of a page supplied in pageData (which can contain
# Markdown plus template code if enabled), substitute the result into a template
# and save in the file specified under key outputFile in pageData.
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

    dict set websiteConfig inputDir $inputDir
    set contentDir [file join $inputDir $scriptConfig(contentDirName)]

    # Build page data.
    set pages {}
    foreach file [fileutil::findByPattern $contentDir -glob *.md] {
        set id [
            ::fileutil::relative $contentDir $file
        ]
        dict set pages $id inputFile $file
        dict set pages $id outputFile [
            file rootname [
                replace-path-root $file $contentDir $outputDir
            ]
        ].html
        # May want to change this preloading behavior for very large websites.
        dict set pages $id rawContent [read-file $file]
        dict set pages $id variables [
            get-metadata-variables [
                dict get $pages $id rawContent
            ]
        ]
        dict set pages $id variables dateUnix [
            incremental-clock-scan [
                dict-default-get {} $pages $id variables date
            ]
        ]
    }

    # Read template from $inputDir or scriptConfig(skeletonDir). The template is
    # either the default (determined by $scriptConfig(templateFileName)) or the
    # one specified in the configuration file. Can later be made per-directory
    # or metadata-based.
    set templateFile [
        choose-dir [
            dict-default-get $scriptConfig(templateFileName) \
                             $websiteConfig templateFileName
        ] [
            list [
                file join $inputDir \
                          $scriptConfig(templateDirName)
            ] [
                file join $scriptConfig(skeletonDir) \
                          $scriptConfig(templateDirName)
            ]
        ]
    ]
    set template [
        read-file $templateFile
    ]

    # Sort pages by date.
    dict set websiteConfig pages [
        dict-sort $pages {variables dateUnix} 0 \
                  {-decreasing}
    ]
    dict set websiteConfig pages tags [tag-list $pages]

    # Process page files into HTML output.
    dict for {id ___} $pages {
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
        dict set pages $id pageLinks $pageLinks
        dict set pages $id rootDirLink [
            ::fileutil::relative [
                file dirname $outputFile
            ] $outputDir
        ]
        dict set websiteConfig currentPageId $id

        page-to-html [dict get $pages $id] $template $websiteConfig
    }

    # Copy static files verbatim.
    copy-files [
      file join $inputDir $scriptConfig(staticDirName)
    ] $outputDir 1
}

# Load website configuration file from directory.
proc load-config {sourceDir {verbose 1}} {
    upvar 1 scriptConfig scriptConfig

    set websiteConfig [
        read-file [
            file join $sourceDir $scriptConfig(websiteConfigFileName)
        ]
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

# Source fileName into templateInterp from the first directory out of dirs where
# it exists.
proc interp-source-dirs {dirs fileName} {
    set command [
        subst -nocommands {
            source [
                choose-dir $fileName {$dirs}
            ]
        }
    ]
    interp eval templateInterp $command
}

proc main {argv0 argv} {
    set scriptLocation [file dirname $argv0]

    # Utility functions.
    source [file join $scriptLocation utils.tcl]

    # Configuration that is generally not supposed to vary from website to
    # website.
    set scriptConfig(markdownProcessor) [
        concat perl [
            file join $scriptLocation external Markdown_1.0.1 Markdown.pl
        ]
    ]

    set scriptConfig(contentDirName) pages
    set scriptConfig(templateDirName) templates
    set scriptConfig(staticDirName) static
    set scriptConfig(templateFileName) default.thtml
    set scriptConfig(websiteConfigFileName) website.conf
    set scriptConfig(skeletonDir) [file join $scriptLocation skeleton]
    set scriptConfig(defaultSourceDir) [file join "website" "input"]
    set scriptConfig(defaultDestDir) [file join "website" "output"]

    set scriptConfig(templateBrackets) {<% %>}


    # Get command line options, including directories to operate on.
    set command [unqueue argv]

    set options {}
    while {[lindex $argv 0] ne "--" && [string match -* [lindex $argv 0]]} {
        lappend options [string trimleft [unqueue argv] -]
    }
    set sourceDir [unqueue argv]
    set destDir [unqueue argv]

    # Defaults for sourceDir and destDir.
    if {$sourceDir eq "" && $destDir eq ""} {
        set sourceDir $scriptConfig(defaultSourceDir)
        set destDir $scriptConfig(defaultDestDir)
    } elseif {$destDir eq ""} {
        catch {
            set destDir [
                dict-default-get {} [
                    load-config $sourceDir 0
                ] destDir
            ]
            # Make relative path from config relative to sourceDir.
            if {$destDir ne "" && [path-is-relative? $destDir]} {
                set destDir [
                    ::fileutil::lexnormalize [
                        file join $sourceDir $destDir
                    ]
                ]
            }
        }
        if {$destDir eq ""} {
            puts [
                trim-indentation {
                    error: no destDir given.

                    please either a) specify both sourceDir and destDir or
                                  b) set destDir in your configuration file.
                }
            ]
            exit 1
        }
    }

    # Execute command.
    switch -exact -- $command {
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

            # Copy project skeleton.
            set skipRegExp [
                if {"templates" in $options} {
                    lindex {}
                } else {
                    lindex {.*templates.*}
                }
            ]
            copy-files $scriptConfig(skeletonDir) $sourceDir 0 $skipRegExp
            exit 0
        }
        build {
            set websiteConfig [load-config $sourceDir]

            if {[file isdir $sourceDir]} {
                compile-website $sourceDir $destDir $websiteConfig
            } else {
                puts "couldn't access directory \"$sourceDir\""
                exit 1
            }
        }
        clean {
            foreach file [fileutil::find $destDir {file isfile}] {
                puts "deleting $file"
                file delete $file
            }
        }
        update {
            set updateSourceDirs [
                list $scriptConfig(staticDirName) {static files}
            ]
            if {"templates" in $options} {
                lappend updateSourceDirs \
                        $scriptConfig(templateDirName) \
                        templates
            }
            foreach {dir descr} $updateSourceDirs {
                puts "updating $descr"
                copy-files [
                    file join $scriptConfig(skeletonDir) $dir
                ] [
                    file join $sourceDir $dir
                ] 2
            }
        }
        deploy-copy {
            set websiteConfig [load-config $sourceDir]

            set deployDest [dict get $websiteConfig deployCopyPath]

            copy-files $destDir $deployDest 1
            exit 0
        }
        deploy-ftp {
            set websiteConfig [load-config $sourceDir]

            package require ftp
            global errorInfo

            set conn [
                ::ftp::Open [
                    dict get $websiteConfig deployFtpServer
                ] [
                    dict get $websiteConfig deployFtpUser
                ] [
                    dict get $websiteConfig deployFtpPassword
                ] -port [
                    dict-default-get 21 $websiteConfig deployFtpPort
                ] -mode passive
            ]
            set deployFtpPath [dict get $websiteConfig deployFtpPath]

            ::ftp::Type $conn binary

            foreach file [fileutil::find $destDir {file isfile}] {
                set destFile [replace-path-root $file $destDir $deployFtpPath]
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
        open {
            set websiteConfig [load-config $sourceDir]

            # Open the index page in the default browser.
            # Currently this is written just for Linux.
            exec -- xdg-open [
                file rootname [
                    file join $destDir [
                        dict-default-get index.md $websiteConfig indexPage
                    ]
                ]
            ].html
        }
        default {
            puts [
                subst -nocommands [
                    trim-indentation {
                        usage: $argv0 <command> [options] [sourceDir [destDir]]

                        Possible commands are:
                            init        create project skeleton
                                --templates copy template files as well
                            build       build static website
                            clean       delete files in destDir
                            update      selectively replace static
                                        files (e.g., CSS) in sourceDir with
                                        those of project skeleton
                                --templates update template files as well
                            deploy-copy copy result to location set in config
                            deploy-ftp  upload result to FTP server set in
                                        config
                            open        open index page in default browser

                        sourceDir defaults to "$scriptConfig(defaultSourceDir)"
                        destDir defaults to "$scriptConfig(defaultDestDir)"
                    }
                ]
            ]
        }
    }
}

main $argv0 $argv
