#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.
package require Tcl 8.5
package require struct
package require fileutil
package require textutil
package require sqlite3

set PROFILE 0
if {$PROFILE} {
    package require profiler
    ::profiler::init
}

# Code conventions: Procedures ("procs") have names-like-this; variables have
# namesLikeThis. "!" at the end of a proc's name means the proc modifies one or
# more of the variables it is passed by name (e.g., "unqueue!"). This is
# somewhat similar to the use of "!" in Scheme. "?" in the same position means
# it returns a boolean value.

namespace eval tclssg {
    namespace export *
    namespace ensemble create

    variable version 0.15.0
    variable debugMode 1
    variable database {}

    proc configure {{scriptLocation .}} {
        # What follows is the configuration that is generally not supposed to
        # vary from project to project.
        set ::tclssg::config(scriptLocation) $scriptLocation

        # Source utility functions.
        source [file join $::tclssg::config(scriptLocation) utils.tcl]

        set ::tclssg::config(version) $::tclssg::version

        # Replace Markdown.pl with, e.g., sundown for improved performance.
        #set ::tclssg::config(markdownProcessor) /usr/local/bin/sundown
        set ::tclssg::config(markdownProcessor) \
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
        proc prepare-content {rawContent id {extraVariables {}}} {
            set choppedContent \
                    [lindex [::tclssg::utils::get-page-variables $rawContent] 1]
            # Macroexpand content if needed then convert it from Markdown to
            # HTML.
            if {[tclssg pages get-website-config-variable \
                        expandMacrosInPages 0]} {
                set choppedContent [interpreter expand \
                        $choppedContent \
                        $id \
                        $extraVariables]
            }
            set cookedContent [markdown-to-html $choppedContent]
            return $cookedContent
        }

        # Expand template substituting in (already HTMLized) content from
        # cookedContent according to the settings in pageData. This is just
        # a wrapper for [interpreter expand] for now.
        proc apply-template {template cookedContent id {extraVariables {}}} {
            set result [interpreter expand \
                    $template \
                    $id \
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
                    puts                                puts
                    ::tclssg::templating::interpreter::with-cache with-cache

                    ::tclssg::pages::get-variable get-page-variable
                    ::tclssg::pages::get-data get-page-data
                    ::tclssg::pages::get-website-config-variable
                            website-var-get-default
                    ::tclssg::pages::get-tag-list get-tag-list
                    ::tclssg::pages::get-link get-page-link
                    ::tclssg::pages::get-tags get-page-tags
                    ::tclssg::pages::get-tag-page get-tag-page
                } {
                    interp alias templateInterp $alias {} {*}$command
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
            proc expand {template id {extraVariables {}}} {
                up [tclssg pages get-website-config-variable inputDir ""]
                #TODO VERIFY
                #inject $websiteConfig
                # Page data overrides website config.
                var-set currentPageId $id
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

            # Run $script and cache the result. Return that result immediately
            # if the script has already been run for $outputFile.
            proc with-cache {outputFile script} {
                set result {}
                if {![[namespace parent]::cache::retrieve-key! \
                            $outputFile $script result]} {
                    set result [interp eval templateInterp $script]
                    [namespace parent]::cache::update-key \
                            $outputFile $script result
                }
                return $result
            }
        } ;# namespace interpreter

        namespace eval cache {
            namespace export *
            namespace ensemble create

            variable cachedFile {}
            variable data {}

            # Check if the cache is fresh for file newFile. Fresh in our case
            # means it's either the same file or a file located in the same
            # directory (because relative link paths for the sidebar and the tag
            # cloud are the same for such files).
            proc fresh? {newFile} {
                variable cachedFile
                variable data

                set result [expr {
                    [file dirname $cachedFile] eq [file dirname $newFile]
                }]
                return $result
            }

            # Update cache item $key. If the rest of the cache is no longer
            # fresh discard it.
            proc update-key {newFile key varName} {
                variable cachedFile
                variable data

                upvar 1 $varName var

                if {![fresh? $newFile]} {
                    set data {}
                    set cachedFile $newFile
                }
                dict set data $key $var
            }

            # Use varName as the key in update-key.
            proc update {newFile varName} {
                upvar 1 $varName localVar
                update-key $newFile $varName localVar
            }

            # If fresh for newFile retrieve the cached value under key and put
            # it in variable varName.
            proc retrieve-key! {newFile key varName} {
                upvar 1 $varName var

                variable data

                if {![fresh? $newFile] || ![dict exists $data $key]} {
                    return 0
                }
                set var [dict get $data $key]
                return 1
            }

            # Use varName as key for retrieve-key!.
            proc retrieve! {newFile varName} {
                upvar 1 $varName localVar
                retrieve-key! $newFile $varName localVar
            }
         } ;# namespace cache
    } ;# namespace templating

    # Make one HTML article out of a page according to an article template.
    proc format-article {id articleTemplate {abbreviate 0} \
            {extraVariables {}}} {
        set cookedContent [tclssg pages get-data $id cookedContent]
        templating apply-template $articleTemplate $cookedContent \
                $id [list abbreviate $abbreviate {*}$extraVariables]
    }

    # Format an HTML document according to a document template. The document
    # content is taken from the variable content while page settings are taken
    # from pageData.
    proc format-document {content id documentTemplate} {
        templating apply-template $documentTemplate $content $id
    }

    # Generate an HTML document out of the pages listed in pageIds and
    # store it as outputFile. The page data corresponding to the ids in
    # pageIds must be present in the dict pages.
    proc generate-html-file {outputFile topPageId articleTemplate
            documentTemplate} {
        set inputFiles {}
        set gen {}
        set first 1

        set pageIds [list $topPageId \
                {*}[tclssg pages get-data $topPageId articlesToAppend {}]]
        foreach id $pageIds {
            append gen [format-article $id $articleTemplate [expr {!$first}] \
                    [list collectionPageId $topPageId]]
            lappend inputFiles [tclssg pages get-data $id inputFile]
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
            format-document $gen $topPageId \
                    $documentTemplate
        ]
        fileutil::writeFile $outputFile $output
    }

    # Read the template named in $varName from $inputDir or (if it is not found
    # in $inputDir) from ::tclssg::config(skeletonDir). The name resolution
    # scheme is a bit convoluted right now. Can later be made per- directory or
    # metadata-based.
    proc read-template-file {inputDir varName} {
        set templateFile [
            ::tclssg::utils::choose-dir [
                tclssg pages get-website-config-variable \
                        $varName \
                        $::tclssg::config($varName)
            ] [
                list [file join $inputDir $::tclssg::config(templateDirName)] \
                        [file join $::tclssg::config(skeletonDir) \
                              $::tclssg::config(templateDirName)]
            ]
        ]
        return [read-file $templateFile]
    }

    # Appends to the pages database table a page or a series of pages that
    # collect the articles of those pages that are listed in pageIds. The number
    # of pages added equals ([llength pageIds] / $blogPostsPerFile) rounded to
    # the nearest whole number. Page settings are taken from the page topPageId
    # and its content is prepended to every output page. Used for making the
    # blog index page.
    proc add-article-collection {pageIds topPageId} {
        set blogPostsPerFile [tclssg pages get-website-config-variable \
                blogPostsPerFile 10]
        set i 0
        set currentPageArticles {}
        set pageNumber 0
        set resultIds {}

        set pageIds [::struct::list filterfor x $pageIds {
            $x ne $topPageId &&
            ![tclssg pages get-variable $x hideFromCollections 0]
        }]

        set prevIndexPageId {}

        foreach id $pageIds {
            lappend currentPageArticles $id
            # If there is enough posts for a page or this is the last post...
            if {($i == $blogPostsPerFile - 1) ||
                    ($id eq [lindex $pageIds end])} {

                set newId [tclssg pages copy $topPageId 1]
                tclssg pages set-data \
                        $newId \
                        inputFile \
                        [tclssg::utils::add-number-before-extension \
                                [tclssg pages get-data $newId inputFile] \
                                [expr {$pageNumber + 1}] {-%d} 1]
                puts -nonewline "adding article collection\
                        [tclssg pages get-data $newId inputFile]"
                tclssg pages set-data \
                        $newId \
                        outputFile \
                        [tclssg::utils::add-number-before-extension \
                                [tclssg pages get-data $newId outputFile] \
                                [expr {$pageNumber + 1}] {-%d} 1]
                tclssg pages set-data $newId \
                        articlesToAppend $currentPageArticles

                tclssg pages set-variable $newId collection 1
                if {$pageNumber > 0} {
                    tclssg pages set-variable $newId \
                            prevPage $prevIndexPageId
                    tclssg pages set-variable $prevIndexPageId \
                            nextPage $newId
                }

                puts " with posts $currentPageArticles"
                lappend resultIds $newId
                set prevIndexPageId $newId
                set i 0
                set currentPageArticles {}
                incr pageNumber
            } else {
                incr i
            }
        }
        return $resultIds
    }

    # For each tag add a page that collects the articles tagged with it using
    # add-article-collection.
    proc add-tag-pages {} {
        set tagPageId [tclssg pages get-website-config-variable tagPage ""]
        if {[string is integer -strict $tagPageId]} {
            foreach tag [tclssg pages get-tag-list] {
                set taggedPages [tclssg pages get-pages-with-tag $tag]
                set newPageId [tclssg pages copy $tagPageId 1]
                set toReplace [file rootname \
                        [lindex [file split [tclssg pages get-data \
                                $newPageId inputFile ""]] end]]
                set replaceWith "tag-[utils::slugify $tag]"
                foreach varName {inputFile outputFile} {
                    tclssg pages set-data \
                            $newPageId \
                            $varName \
                            [string map \
                                    [list $toReplace $replaceWith] \
                                    [tclssg pages get-data \
                                            $newPageId $varName ""]]
                }
                set resultIds [add-article-collection $taggedPages $newPageId]
                for {set i 0} {$i < [llength $resultIds]} {incr i} {
                    tclssg pages add-tag-page [lindex $resultIds $i] $tag $i
                }
            }
        }
    }

    # Website page database.
    namespace eval pages {
        namespace export *
        namespace ensemble create

        proc init {} {
            catch {file delete /tmp/debug.sqlite3}
            sqlite3 tclssg-db /tmp/debug.sqlite3
            # Do not store variable values as columns because this allows pages
            # to set custom variables to be parsed by templates without
            # changes to the static site generator source itself.
            tclssg-db eval {
                CREATE TABLE pages(
                    id INTEGER PRIMARY KEY,
                    inputFile TEXT,
                    outputFile TEXT,
                    rawContent TEXT,
                    cookedContent TEXT,
                    pageLinks TEXT,
                    rootDirPath TEXT,
                    articlesToAppend TEXT,
                    dateScanned INTEGER
                );
                CREATE TABLE links(
                    id INTEGER,
                    targetId INTEGER,
                    link TEXT,
                    PRIMARY KEY (id, targetId)
                );
                CREATE TABLE variables(
                    id INTEGER,
                    name TEXT,
                    value TEXT,
                    PRIMARY KEY (id, name)
                );
                CREATE TABLE websiteConfig(
                    name TEXT PRIMARY KEY,
                    value TEXT
                );
                CREATE TABLE tags(
                    id INTEGER,
                    tag TEXT
                );
                CREATE TABLE tagPages(
                    tag TEXT,
                    pageNumber INTEGER,
                    id INTEGER,
                    PRIMARY KEY (tag, pageNumber)
                );
            }
        }

        proc add {inputFile outputFile rawContent cookedContent dateScanned} {
            tclssg-db eval {
                INSERT INTO pages(
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    dateScanned)
                VALUES ($inputFile, $outputFile, $rawContent, $cookedContent,
                    $dateScanned);
            }
            return [tclssg-db last_insert_rowid]
        }
        proc copy {id copyVariables} {
            tclssg-db eval {
                INSERT INTO pages(
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    rootDirPath,
                    articlesToAppend,
                    dateScanned)
                SELECT
                    inputFile,
                    outputFile,
                    rawContent,
                    cookedContent,
                    rootDirPath,
                    articlesToAppend,
                    dateScanned
                FROM pages WHERE id = $id;
            }
            set newPageId [tclssg-db last_insert_rowid]
            tclssg-db eval {
                INSERT INTO links(
                    id,
                    targetId,
                    link)
                SELECT
                    $newPageId,
                    targetId,
                    link
                FROM links WHERE id = $id;
            }
            if {$copyVariables} {
                tclssg-db eval {
                    INSERT INTO variables(
                        id,
                        name,
                        value)
                    SELECT
                        $newPageId,
                        name,
                        value
                    FROM variables WHERE id = $id;
                }
            }
            return $newPageId
        }
        proc set-data {id field value} {
            tclssg-db eval [format {
                UPDATE pages SET %s=$value WHERE id = $id;
            } $field]
        }
        proc get-data {id field {default ""}} {
            tclssg-db eval {
                SELECT * FROM pages WHERE id = $id;
            } arr {}
            if {[info exists arr($field)]} {
                return $arr($field)
            } else {
                return $default
            }
        }
        proc sorted-by-date {} {
            set result [tclssg-db eval {
                SELECT id FROM pages ORDER BY dateScanned;
            }]
            return $result
        }

        proc add-link {sourceId targetId link} {
            tclssg-db eval {
                INSERT INTO links(id, targetId, link)
                VALUES ($sourceId, $targetId, $link);
            }
        }
        proc get-link {sourceId targetId} {
            set result [tclssg-db eval {
                SELECT link FROM links
                WHERE id = $sourceId AND targetId = $targetId;
            }]
            return $result
        }

        proc set-variable {id name value} {
            tclssg-db eval {
                INSERT OR REPLACE INTO variables(id, name, value)
                VALUES ($id, $name, $value);
            }
        }
        proc get-variable {id name default} {
            set result [lindex [tclssg-db eval {
                SELECT COALESCE(MAX(value), $default) FROM variables
                WHERE id = $id AND name = $name;
            }] 0]
            return $result
        }
        proc get-pages-with-variable-value {name value} {
            set result [tclssg-db eval {
                SELECT id FROM variables WHERE name = $name AND value = $value;
            }]
            return $result
        }

        proc set-website-config-variable {name value} {
            tclssg-db eval {
                INSERT OR REPLACE INTO websiteConfig(name, value)
                VALUES ($name, $value);
            }
        }
        proc get-website-config-variable {name default} {
            set result [lindex [tclssg-db eval {
                SELECT COALESCE(MAX(value), $default) FROM websiteConfig
                WHERE name = $name;
            }] 0]
            return $result
        }

        proc add-tags {id tagList} {
            foreach tag $tagList {
                tclssg-db eval {
                    INSERT INTO tags(id, tag)
                    VALUES ($id, $tag);
                }
            }
        }
        proc get-tags {id} {
            set result [tclssg-db eval {
                SELECT tag FROM tags WHERE id = $id;
            }]
            return $result
        }
        proc get-tag-page {tag pageNumber} {
            set result [tclssg-db eval {
                SELECT id FROM tagPages
                WHERE tag = $tag AND pageNumber = $pageNumber;
            }]
            return $result
        }
        proc add-tag-page {id tag pageNumber} {
            tclssg-db eval {
                INSERT INTO tagPages(tag, pageNumber, id)
                VALUES ($tag, $pageNumber, $id);
            }
        }
        proc get-pages-with-tag {tag} {
            set result [tclssg-db eval {
                SELECT id FROM tags WHERE tag = $tag;
            }]
            return $result
        }
        proc get-tag-list {{sortBy "name"}} {
            switch -exact -- $sortBy {
                frequency {
                    set result [tclssg-db eval {
                        SELECT DISTINCT tag FROM tags
                        GROUP BY tag ORDER BY count(id) DESC;
                    }]
                }
                name {
                    set result [tclssg-db eval {
                        SELECT DISTINCT tag FROM tags ORDER BY tag;
                    }]
                }
                default {
                    error "unknown tag sorting option: $sortBy"
                }
            }
            return $result
        }

    } ;# namespace pages

    # Process input files in inputDir to produce a static website in outputDir.
    proc compile-website {inputDir outputDir websiteConfig} {
        tclssg pages init
        foreach {key value} $websiteConfig {
            tclssg pages set-website-config-variable $key $value
        }

        tclssg pages set-website-config-variable inputDir $inputDir
        set contentDir [file join $inputDir $::tclssg::config(contentDirName)]

        foreach file [fileutil::findByPattern $contentDir -glob *.md] {
            # May want to change the rawContent preloading behavior for very
            # large (larger than memory) websites.
            set rawContent [read-file $file]
            set variables [lindex \
                    [::tclssg::utils::get-page-variables $rawContent] 0]
            set dateScanned [::tclssg::utils::incremental-clock-scan \
                    [::tclssg::utils::dict-default-get {} $variables date]]
            dict set variables dateScanned $dateScanned
            set id_ [tclssg pages add \
                            $file \
                            [file rootname \
                                    [::tclssg::utils::replace-path-root \
                                            $file $contentDir $outputDir]].html\
                            $rawContent \
                            "" \
                            [lindex $dateScanned 0]]

            tclssg pages add-tags $id_ \
                    [::tclssg::utils::dict-default-get {} $variables tags]
            dict unset variables tags

            foreach {var value} $variables {
                tclssg pages set-variable $id_ $var $value
            }
        }

        # Read template files.
        set articleTemplate [
            read-template-file $inputDir articleTemplateFileName
        ]
        set documentTemplate [
            read-template-file $inputDir documentTemplateFileName
        ]


        # Create list of pages that are blog posts and blog posts that should be
        # linked to from the sidebar.
        set blogPostIds [tclssg pages get-pages-with-variable-value blogPost 1]
        # TODO: FIXME
        set sidebarPostIds $blogPostIds;
        #[database get-pages-with-variable-value hideFromSidebar 0]
        tclssg pages set-website-config-variable  sidebarPostIds $sidebarPostIds

        # Find the numerical ids that correspond to page names in the config.
        foreach varName {indexPage blogIndexPage tagPage} {
            set value [file join $contentDir \
                    [tclssg pages get-website-config-variable $varName ""]]
            tclssg pages set-website-config-variable  $varName [tclssg-db eval {
                SELECT id FROM pages WHERE inputFile = $value LIMIT 1;
            }]
        }


        # Add chronological blog index.
        set blogIndexPage \
                [tclssg pages get-website-config-variable blogIndexPage ""]
        if {$blogIndexPage ne ""} {
            add-article-collection $blogPostIds $blogIndexPage
        }

        # Add pages with blog posts for each tag.
        add-tag-pages

        # Process page files into HTML output.
        foreach id [tclssg pages sorted-by-date] {
            # Links to other pages relative to the current one.
            set outputFile [tclssg pages get-data $id outputFile]

            # Use the previous list of relative links in the current file is
            # in the same directory as the previous one.
            if {![templating cache retrieve! $outputFile pageLinks]} {
                # Compute new pageLinks for the current page. Beware: in the
                # worst case scenario (each page is in its own directory) this
                # gives us n^2 operations for n pages.
                set pageLinks {}
                foreach otherFileId [tclssg pages sorted-by-date] {
                    # pageLinks maps page id (= input FN relative to
                    # $contentDir) to relative link to it.
                    lappend pageLinks $otherFileId \
                            [::fileutil::relative \
                                    [file dirname $outputFile] \
                                    [tclssg pages get-data \
                                            $otherFileId outputFile]]
                }
                templating cache update $outputFile pageLinks
            }
            # Store links to other pages and website root path relative to the
            # current page.
            foreach {targetId link} $pageLinks {
                tclssg pages add-link $id $targetId $link
            }
            tclssg pages set-data $id rootDirPath \
                    [::fileutil::relative \
                            [file dirname $outputFile] \
                            $outputDir]

            # Expand templates, first for the article then for the HTML
            # document. This modifies pages.
            tclssg pages set-data $id cookedContent [
                templating prepare-content \
                        [tclssg pages get-data $id rawContent] \
                        $id \
            ]

            generate-html-file \
                    [tclssg pages get-data $id outputFile] \
                    $id \
                    $articleTemplate \
                    $documentTemplate \
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
        set command [utils::unqueue! argv]

        set options {}
        while {[lindex $argv 0] ne "--" &&
                [string match -* [lindex $argv 0]]} {
            lappend options [string trimleft [::tclssg::utils::unqueue! argv] -]
        }
        set inputDir [::tclssg::utils::unqueue! argv]
        set outputDir [::tclssg::utils::unqueue! argv]

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
