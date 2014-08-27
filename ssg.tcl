#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.
package require Tcl 8.5
package require struct
package require fileutil
package require textutil
package require profiler

set PROFILE 0
if {$PROFILE} {
    ::profiler::init
}

namespace eval tclssg {
    namespace export *
    namespace ensemble create

    variable version 0.13.0
    variable debugMode 1

    proc configure {{scriptLocation .}} {
        # What follows is the configuration that is generally not supposed to
        # vary from project to project.
        set ::tclssg::config(scriptLocation) $scriptLocation

        # Source utility functions.
        source [file join $::tclssg::config(scriptLocation) utils.tcl]

        set ::tclssg::config(version) $::tclssg::version

        # Replace Markdown.pl with, e.g., sundown for improved performance.
        set ::tclssg::config(markdownProcessor) /usr/local/bin/sundown
        #set ::tclssg::config(markdownProcessor) \
                [concat perl \
                        [file join $::tclssg::config(scriptLocation) \
                                external Markdown_1.0.1 Markdown.pl]]

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

        return
    }

    namespace eval templating {
        namespace export *
        namespace ensemble create

        # Convert raw Markdown to HTML using an external Markdown processor.
        proc markdown-to-html {markdown} {
            exec -- {*}$::tclssg::config(markdownProcessor) << $markdown
        }

        # Make HTML out of rawContent (remove frontmatter, if any, expand macros
        # if expandMacrosInPages is enabled in websiteConfig, convert Markdown
        # to HTML).
        proc prepare-content {rawContent pageData websiteConfig \
                {extraVariables {}}} {
            set choppedContent \
                    [lindex [::tclssg::utils::get-page-variables $rawContent] 1]
            # Macroexpand content if needed then convert it from Markdown to
            # HTML.
            if {[::tclssg::utils::dict-default-get 0 \
                        $websiteConfig expandMacrosInPages]} {
                set choppedContent [interpreter expand \
                        $choppedContent \
                        $pageData \
                        $websiteConfig \
                        $extraVariables]
            }
            set cookedContent [markdown-to-html $choppedContent]
            return $cookedContent
        }

        # Expand template substituting in (already HTMLized) content from
        # cookedContent according to the settings in pageData. This is just
        # a wrapper for [interpreter expand] for now.
        proc apply-template {template cookedContent pageData websiteConfig \
                {extraVariables {}}} {
            set result [interpreter expand \
                    $template \
                    $pageData \
                    $websiteConfig \
                    [list content $cookedContent {*}$extraVariables]]
            return $result
        }

        namespace eval interpreter {
            namespace export *
            namespace ensemble create

            # Set variable $key to $value in the template interpreter for each
            # key-value pair in a dictionary.
            proc inject {dictionary} {
                dict for {key value} $dictionary {
                    var-set $key $value
                }
            }

            # If $varName exists return its value in the interpreter
            # templateInterp else return the default value.
            proc website-var-get-default {varName default} {
                if {[interp eval templateInterp "info exists $varName"]} {
                    return [interp eval templateInterp "set $varName"]
                } else {
                    return $default
                }
            }

            # Set up the template interpreter.
            proc up {inputDir} {
                # Create a safe interpreter to use for expanding templates (the
                # template interpreter).
                interp create -safe templateInterp
                # A command to set variable $name to $value in the template
                # interpreter.
                interp alias {} [namespace current]::var-set templateInterp set

                # Alias commands to be used in templates.
                foreach {command alias} {
                    ::tclssg::utils::replace-path-root  replace-path-root
                    ::tclssg::utils::dict-default-get   dict-default-get
                    textutil::indent                    textutil::indent
                    ::tclssg::utils::slugify            slugify
                    ::tclssg::utils::choose-dir         choose-dir
                    ::md5::md5                          ::md5::md5
                    puts                                puts
                    ::tclssg::templating::interpreter::website-var-get-default \
                            website-var-get-default
                    ::tclssg::templating::cache::update cache-update
                    ::tclssg::templating::cache::retrieve! cache-retrieve!
                } {
                    interp alias templateInterp $alias {} $command
                }

                # Expose built-ins.
                foreach builtIn {source} {
                    interp expose templateInterp $builtIn
                }

                # Allow templates to source Tcl files with directory failover
                # with the command interp-source.
                interp alias templateInterp interp-source {} \
                        ::tclssg::templating::interpreter::source-dirs [
                            list [
                                file join $inputDir \
                                          $::tclssg::config(templateDirName)
                            ] [
                                file join $::tclssg::config(skeletonDir) \
                                          $::tclssg::config(templateDirName)
                            ]
                        ]
            }

            # Tear down the template interpreter.
            proc down {} {
                interp delete templateInterp
            }

            # Source fileName into templateInterp from the first directory where
            # it exists out of those in dirs.
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

            # Expand template for page pageData.
            proc expand {template pageData websiteConfig {extraVariables {}}} {
                up [dict get $websiteConfig inputDir]
                inject $websiteConfig
                # Page data overrides website config.
                inject $pageData
                inject $extraVariables
                set listing [parse $template]
                set result [interp eval templateInterp $listing]
                down
                return $result
            }

            # Convert a template into Tcl code.
            # Inspired by tmpl_parser by Kanryu KATO (http://wiki.tcl.tk/20363).
            proc parse {template} {
                set result {}
                set regExpr {^(.*?)<%(.*?)%>(.*)$}
                set listing "set _output {}\n"
                while {[regexp $regExpr $template \
                        match preceding token template]} {
                    append listing [list append _output $preceding]\n
                    # Process <%= ... %> (expression), <%! ... %> (command)
                    # and <% ... %> (raw code) syntax.
                    switch -exact -- [string index $token 0] {
                        = {
                            append listing \
                                    [format {append _output [expr %s]} \
                                            [list [string range $token 1 end]]]
                        }
                        ! {
                            append listing \
                                    [format {append _output [%s]} \
                                            [string range $token 1 end]]
                        }
                        default {
                            append listing $token
                        }
                    }
                    append listing \n
                }
                append listing [list append _output $template]\n
                return $listing
            }
        } ;# namespace interpreter

        namespace eval cache {
            namespace export *
            namespace ensemble create

            variable cachedFile {}
            variable data {}

            proc fresh? {newFile} {
                variable cachedFile
                variable data

                set result [expr {
                    [file dirname $cachedFile] eq [file dirname $newFile]
                }]
                return $result
            }

            proc update {newFile key value} {
                variable cachedFile
                variable data

                if {![fresh? $newFile]} {
                    set data {}
                    set cachedFile $newFile
                }
                dict set data $key $value
            }

            proc retrieve! {newFile key varName} {
                upvar 1 varName value

                variable data

                if {![fresh? $newFile] || ![dict exists $data $key]} {
                    return 0
                }
                set value [dict get $data $key]
                return 1
            }
         };# namespace cache
    } ;# namespace templating

    # Make one HTML article out of a page according to an article template.
    proc format-article {pageData articleTemplate websiteConfig \
            {abbreviate 0} {extraVariables {}}} {
        set cookedContent [dict get $pageData cookedContent]
        templating apply-template $articleTemplate $cookedContent \
                $pageData $websiteConfig \
                [list abbreviate $abbreviate {*}$extraVariables]
    }

    # Format an HTML document according to a document template. The document
    # content is taken from the variable content while page settings are taken
    # from pageData.
    proc format-document {content pageData documentTemplate websiteConfig} {
        templating apply-template $documentTemplate $content \
                $pageData $websiteConfig
    }

    # Generate an HTML document out of the pages listed in pageIds and
    # store it as outputFile. The page data corresponding to the ids in
    # pageIds must be present in the dict pages.
    proc generate-html-file {outputFile pages pageIds articleTemplate
            documentTemplate websiteConfig} {
        set inputFiles {}
        set gen {}
        set first 1

        set topPageId [lindex [dict keys $pages] 0]
        foreach id $pageIds {
            set pageData [dict get $pages $id]
            if {!$first} {
                dict set pageData variables collection 1
            }
            append gen [format-article $pageData $articleTemplate \
                    $websiteConfig [expr {!$first}] \
                    [list collectionPageId $topPageId]]
            lappend inputFiles [dict get $pageData inputFile]
            set first 0
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

    # Generate a tag list in the format of dict {tag {id id id ...} ...}.
    proc tag-list {pages} {
        set tags {}
        dict for {page pageData} $pages {
            foreach tag [::tclssg::utils::dict-default-get {} \
                    $pageData variables tags] {
                dict lappend tags $tag $page
            }
        }
        return $tags
    }

    # Read the template named in $varName from $inputDir or (if it is not found
    # in $inputDir) from ::tclssg::config(skeletonDir). The name resolution
    # scheme is a bit convoluted right now. Can later be made per- directory or
    # metadata-based.
    proc read-template-file {inputDir varName websiteConfig} {
        set templateFile [
            ::tclssg::utils::choose-dir [
                ::tclssg::utils::dict-default-get $::tclssg::config($varName) \
                        $websiteConfig $varName
            ] [
                list [file join $inputDir $::tclssg::config(templateDirName)] \
                        [file join $::tclssg::config(skeletonDir) \
                              $::tclssg::config(templateDirName)]
            ]
        ]
        return [read-file $templateFile]
    }

    # Appends to the ordered dict pagesVarName a page or a series of pages that
    # collect the articles of those pages that are listed in pageIds. The number
    # of pages added equals ([llength pageIds] / $blogPostsPerFile) rounded to
    # the nearest whole number. Page settings are taken from the page topPageId
    # and its content is prepended to every output page. Used for making the
    # blog index page.
    proc add-article-collection! {pagesVarName pageIds topPageId websiteConfig} {
        upvar 1 $pagesVarName pages

        set blogPostsPerFile [::tclssg::utils::dict-default-get 10 \
                $websiteConfig blogPostsPerFile]
        set i 0
        set currentPageArticles {}
        set pageNumber 0

        set topPageData [dict get $pages $topPageId]
        # Needed to move the key to the end of the dict.
        dict unset pages $topPageId

        set pageIds [::struct::list filterfor x $pageIds {
            $x ne $topPageId &&
            ![utils::dict-default-get 0 \
                    $pages $x variables hideFromCollections]
        }]

        set prevIndexPageId {}

        foreach id $pageIds {
            lappend currentPageArticles $id
            # If there is enough posts for a page or this is the last post...
            if {($i == $blogPostsPerFile - 1) ||
                    ($id eq [lindex $pageIds end])} {
                set newPageId \
                        [tclssg::utils::add-number-before-extension \
                                $topPageId [expr {$pageNumber + 1}] {-%d} 1]
                puts -nonewline \
                    "adding article collection $newPageId "

                set newPageData $topPageData
                dict with newPageData {
                    set currentPageId $newPageId
                    set inputFile \
                            [tclssg::utils::add-number-before-extension \
                                    $inputFile \
                                    [expr {$pageNumber + 1}] {-%d} 1]
                    set outputFile \
                            [tclssg::utils::add-number-before-extension \
                                    $outputFile \
                                    [expr {$pageNumber + 1}] {-%d} 1]
                }
                dict set newPageData articlesToAppend $currentPageArticles
                dict set newPageData variables collection 1
                if {$pageNumber > 0} {
                    dict set newPageData \
                            variables prevPage $prevIndexPageId
                    dict set pages \
                            $prevIndexPageId variables nextPage $newPageId
                }
                # Add a key at the end of the dictionary pages while keeping it
                # sorted. This is needed to make sure the pageLinks for normal
                # pages are generated before they are included into collections.
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

    # For each tag add a page that collects the articles tagged with it using
    # add-article-collection.
    proc add-tag-pages! {pagesVarName websiteConfigVarName} {
        upvar 1 $pagesVarName pages
        upvar 1 $websiteConfigVarName websiteConfig

        set tagPage [utils::dict-default-get {} $websiteConfig tagPage]
        foreach tag [dict keys [dict get $websiteConfig tags]] {
            set taggedPages [dict get $websiteConfig tags $tag pageIds]
            set oldIdRepl [file rootname \
                    [lindex [file split \
                            [dict get $pages $tagPage currentPageId]] end]]
            set newPageIdRepl "tag-[utils::slugify $tag]"
            set newPageId [string map [list $oldIdRepl $newPageIdRepl] \
                    [dict get $pages $tagPage currentPageId]]
            lappend pages $newPageId [dict get $pages $tagPage]
            dict with pages $newPageId {
                foreach varName {currentPageId inputFile outputFile} {
                    set $varName [string map [list $oldIdRepl $newPageIdRepl] \
                            [set $varName]]
                }
            }
            add-article-collection! pages $taggedPages \
                $newPageId $websiteConfig
            dict with websiteConfig tags $tag {
                lappend tagPages $newPageId
            }
        }
    }

    # Process input files in inputDir to produce a static website in outputDir.
    proc compile-website {inputDir outputDir websiteConfig} {
        dict set websiteConfig inputDir $inputDir
        set contentDir [file join $inputDir $::tclssg::config(contentDirName)]

        # Build page data from input files.
        set pages {}
        foreach file [fileutil::findByPattern $contentDir -glob *.md] {
            set id [::fileutil::relative $contentDir $file]
            dict set pages $id currentPageId $id
            dict set pages $id inputFile $file
            dict set pages $id outputFile \
                    [file rootname [::tclssg::utils::replace-path-root \
                            $file $contentDir $outputDir]].html
            # May want to change this preloading behavior for very large
            # websites.
            dict set pages $id rawContent [read-file $file]
            dict set pages $id variables \
                    [lindex [::tclssg::utils::get-page-variables \
                            [dict get $pages $id rawContent]] 0]
            dict set pages $id variables dateScanned \
                    [::tclssg::utils::incremental-clock-scan \
                            [::tclssg::utils::dict-default-get {} \
                                    $pages $id variables date]]
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
            tclssg::utils::dict-sort $pages {variables dateScanned} 0 \
                    {-decreasing} {x {lindex $x 0}}
        ]

        # Create list of pages that are blog posts and blog posts that should be
        # linked to from the sidebar.
        set blogPostIds {}
        set sidebarPostIds {}
        foreach {id pageData} $pages {
            if {[::tclssg::utils::dict-default-get 0 \
                    $pageData variables blogPost]} {
                lappend blogPostIds $id
                if {![::tclssg::utils::dict-default-get 0 \
                        $pageData variables hideFromSidebar]} {
                    lappend sidebarPostIds $id
                }
            }
        }

        # Add chronological blog index.
        set blogIndexPage [utils::dict-default-get {} $websiteConfig blogIndexPage]
        if {$blogIndexPage ne ""} {
            add-article-collection! pages $blogPostIds \
                    $blogIndexPage $websiteConfig
        }

        dict set websiteConfig pages $pages
        dict set websiteConfig sidebarPostIds $sidebarPostIds
        dict set websiteConfig tags {}
        foreach {tag pageIds} [tag-list $pages] {
            dict set websiteConfig tags $tag pageIds $pageIds
            dict set websiteConfig tags $tag tagPages {}
            # This is a hack that allows us to sort tags alphabetically with
            # dict-sort below.
            dict set websiteConfig tags $tag tagText $tag
        }

        # Sort tags.
        dict set websiteConfig tags [
            set sortBy [utils::dict-default-get {} $websiteConfig sortTagsBy]
            if {$sortBy eq "frequency"} {
                tclssg::utils::dict-sort [dict get $websiteConfig tags] \
                        {pageIds} 0 {-decreasing} {x {llength $x}}
            } elseif {($sortBy eq "name") || ($sortBy eq "")} {
                tclssg::utils::dict-sort [dict get $websiteConfig tags] \
                        {tagText} 0 {-increasing}
            } else {
                error "unknown tag sorting option: $sortBy"
            }
        ]

        # Add pages with blog posts for each tag.
        add-tag-pages! pages websiteConfig

        # Process page files into HTML output.
        set prevPageLinks {}
        set prevOutputFile {}

        dict for {id pageData} $pages {
            # Links to other pages relative to the current one.
            set outputFile [dict get $pageData outputFile]

            # Use the previous list of relative links in the current file is
            # in the same directory as the previous one.
            if {![templating cache retrieve! $outputFile pageLinks pageLinks]} {
                # Compute new pageLinks for the current page. Beware: in the
                # worst case scenario (each page is in its own directory) this
                # gives us n^2 operations for n pages.
                set pageLinks {}
                dict for {otherFile otherMetadata} $pages {
                    # pageLinks maps page id (= input FN relative to
                    # $contentDir) to relative link to it.
                    lappend pageLinks $otherFile [
                        ::fileutil::relative [
                            file dirname $outputFile
                        ] [
                            dict get $otherMetadata outputFile
                        ]
                    ]
                }
                templating cache update $outputFile pageLinks $pageLinks
            }
            # Store links to other pages and website root path relative to the
            # current page.
            dict set pages $id pageLinks $pageLinks
            dict set pages $id rootDirPath [
                ::fileutil::relative [
                    file dirname $outputFile
                ] $outputDir
            ]

            # Expand templates, first for the article then for the HTML
            # document. This modifies pages.
            dict set pages $id cookedContent [
                templating prepare-content \
                        [dict get $pages $id rawContent] \
                        [dict get $pages $id] \
                        $websiteConfig
            ]

            generate-html-file \
                    [dict get $pageData outputFile] \
                    $pages \
                    [list $id \
                            {*}[::tclssg::utils::dict-default-get {} \
                                    $pages $id articlesToAppend]] \
                    $articleTemplate \
                    $documentTemplate \
                    $websiteConfig
        }

        # Copy static files verbatim.
        tclssg::utils::copy-files \
                [file join $inputDir $::tclssg::config(staticDirName)] \
                $outputDir \
                1
    }

    # Load the website configuration file from the directory inputDir.
    proc load-config {inputDir {verbose 1}} {
        set websiteConfig [
            read-file [file join $inputDir \
                    $::tclssg::config(websiteConfigFileName)]
        ]

        # Show loaded config to user (without the password values).
        if {$verbose} {
            puts "Loaded config file:"
            puts [
                textutil::indent [
                    ::tclssg::utils::dict-format [
                        ::tclssg::utils::obscure-password-values $websiteConfig
                    ]
                ] {    }
            ]
        }

        return $websiteConfig
    }

    # Commands that can be given to Tclssg on the command line.
    namespace eval command {
        namespace export *
        namespace ensemble create \
                -prefixes 0 \
                -unknown ::tclssg::command::unknown

        proc init {inputDir outputDir {options {}}} {
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
            ::tclssg::utils::copy-files \
                    $::tclssg::config(skeletonDir) $inputDir 0 $skipRegExp
        }

        proc build {inputDir outputDir {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            if {[file isdir $inputDir]} {
                ::tclssg::compile-website $inputDir $outputDir $websiteConfig
            } else {
                error "couldn't access directory \"$inputDir\""
            }
        }

        proc clean {inputDir outputDir {options {}}} {
            foreach file [fileutil::find $outputDir {file isfile}] {
                puts "deleting $file"
                file delete $file
            }
        }

        proc update {inputDir outputDir {options {}}} {
            set updateSourceDirs [
                list $::tclssg::config(staticDirName) {static files}
            ]
            if {"templates" in $options} {
                lappend updateSourceDirs \
                        $::tclssg::config(templateDirName) \
                        templates
            }
            if {"yes" in $options} {
                set overwriteMode 1
            } else {
                set overwriteMode 2
            }
            foreach {dir descr} $updateSourceDirs {
                puts "updating $descr"
                ::tclssg::utils::copy-files [
                    file join $::tclssg::config(skeletonDir) $dir
                ] [
                    file join $inputDir $dir
                ] $overwriteMode
            }
        }

        proc deploy-copy {inputDir outputDir {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            set deployDest [dict get $websiteConfig deployCopyPath]

            ::tclssg::utils::copy-files $outputDir $deployDest 1
        }

        proc deploy-custom {inputDir outputDir {options {}}} {
            proc exec-deploy-command {key} {
                foreach varName {deployCustomCommand outputDir file fileRel} {
                    upvar 1 $varName $varName
                }
                if {[dict exists $deployCustomCommand $key] &&
                    ([dict get $deployCustomCommand $key] ne "")} {
                    puts [exec -- {*}[subst -nocommands \
                            [dict get $deployCustomCommand $key]]]
                }
            }
            set websiteConfig [::tclssg::load-config $inputDir]

            set deployCustomCommand \
                    [dict get $websiteConfig deployCustomCommand]

            exec-deploy-command start
            foreach file [fileutil::find $outputDir {file isfile}] {
                set fileRel [::fileutil::relative $outputDir $file]
                exec-deploy-command file
            }
            exec-deploy-command end
        }

        proc deploy-ftp {inputDir outputDir {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

            package require ftp
            global errorInfo
            set conn [
                ::ftp::Open \
                        [dict get $websiteConfig deployFtpServer] \
                        [dict get $websiteConfig deployFtpUser] \
                        [dict get $websiteConfig deployFtpPassword] \
                        -port [::tclssg::utils::dict-default-get 21 \
                                $websiteConfig deployFtpPort] \
                        -mode passive
            ]
            set deployFtpPath [dict get $websiteConfig deployFtpPath]

            ::ftp::Type $conn binary

            foreach file [fileutil::find $outputDir {file isfile}] {
                set destFile [::tclssg::utils::replace-path-root \
                        $file $outputDir $deployFtpPath]
                set path [file split [file dirname $destFile]]
                set partialPath {}

                foreach dir $path {
                    set partialPath [file join $partialPath $dir]
                    if {[ftp::Cd $conn $partialPath]} {
                        ftp::Cd $conn /
                    } else {
                        puts "creating directory $partialPath"
                        ::ftp::MkDir $conn $partialPath
                    }
                }
                puts "uploading $file as $destFile"
                if {![::ftp::Put $conn $file $destFile]} {
                    error "upload error: $errorInfo"
                }
            }
            ::ftp::Close $conn
        }

        proc open {inputDir outputDir {options {}}} {
            set websiteConfig [::tclssg::load-config $inputDir]

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
                        ::tclssg::utils::dict-default-get index.md \
                                $websiteConfig indexPage
                    ]
                ]
            ].html
        }

        proc version {inputDir outputDir {options {}}} {
            puts $::tclssg::config(version)
        }

        proc help {{inputDir ""} {outputDir ""} {options ""}} {
            global argv0

            puts [
                format [
                    ::tclssg::utils::trim-indentation {
                        usage: %s <command> [options] [inputDir [outputDir]]

                        Possible commands are:
                            init        create project skeleton
                                --templates copy template files as well
                            build       build static website
                            clean       delete files in outputDir
                            update      selectively replace static
                                        files (e.g., CSS) in inputDir with
                                        those of project skeleton
                                --templates update template files as well
                                --yes       assume "yes" to all questions
                            deploy-copy copy output to location set in config
                            deploy-custom
                                        run custom commands to deploy output
                            deploy-ftp  upload output to FTP server set in
                                        config
                            open        open index page in default browser
                            version     print version number and exit
                            help        show this message

                        inputDir defaults to "%s"
                        outputDir defaults to "%s"
                    }
                ] $argv0 $::tclssg::config(defaultInputDir) \
                $::tclssg::config(defaultOutputDir)
            ]
        }

        proc unknown args {
            return ::tclssg::command::help
        }
    } ;# namespace command

    proc main {argv0 argv} {
        tclssg configure [file dirname $argv0]

        # Version.
        catch {
            set currentPath [pwd]
            cd $::tclssg::config(scriptLocation)
            append ::tclssg::config(version) \
                    " (commit [string range [exec git rev-parse HEAD] 0 9])"
            cd $currentPath
        }

        # Get command line options, including directories to operate on.
        set command [utils::unqueue argv]

        set options {}
        while {[lindex $argv 0] ne "--" &&
                [string match -* [lindex $argv 0]]} {
            lappend options [string trimleft [::tclssg::utils::unqueue argv] -]
        }
        set inputDir [::tclssg::utils::unqueue argv]
        set outputDir [::tclssg::utils::unqueue argv]

        # Defaults for inputDir and outputDir.
        if {$inputDir eq "" && $outputDir eq ""} {
            set inputDir $::tclssg::config(defaultInputDir)
            set outputDir $::tclssg::config(defaultOutputDir)
        } elseif {$outputDir eq ""} {
            catch {
                set outputDir [
                    ::tclssg::utils::dict-default-get {} [
                        ::tclssg::load-config $inputDir 0
                    ] outputDir
                ]
                # Make relative path from config relative to inputDir.
                if {$outputDir ne "" &&
                        [::tclssg::utils::path-is-relative? $outputDir]} {
                    set outputDir [
                        ::fileutil::lexnormalize [
                            file join $inputDir $outputDir
                        ]
                    ]
                }
            }
            if {$outputDir eq ""} {
                puts [
                    ::tclssg::utils::trim-indentation {
                        error: no outputDir given.

                        please either a) specify both inputDir and outputDir or
                                      b) set outputDir in your configuration
                                         file.
                    }
                ]
                exit 1
            }
        }

        # Execute command.
        if {$::tclssg::debugMode} {
            tclssg command $command $inputDir $outputDir $options
        } else {
            if {[catch {tclssg command \
                    $command $inputDir $outputDir $options} errorMessage]} {
                puts $errorMessage
                exit 1
            }
        }
    }
} ;# namespace tclssg

# Check if we were run as the primary script by the interpreter. Code from
# http://wiki.tcl.tk/40097.
proc main-script? {} {
    global argv0

    if {[info exists argv0] &&
                [file exists [info script]] &&
                [file exists $argv0]} {
        file stat $argv0 argv0Info
        file stat [info script] scriptInfo
        expr {$argv0Info(dev) == $scriptInfo(dev)
           && $argv0Info(ino) == $scriptInfo(ino)}
    } else {
        return 0
    }
}

if {[main-script?]} {
    ::tclssg::main $argv0 $argv
    if {$PROFILE} {
        puts [::profiler::sortFunctions exclusiveRuntime]
    }
}
