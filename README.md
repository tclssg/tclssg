ssg-tcl
=======

A static website generator written in Tcl for danyilbohdan.com.

To use `ssg-tcl` you'll need Tcl 8.5 and Tcllib.

Generates blogs. All blog entries have a sidebar. Relative links.
Tags. HTML5.

FTP uploading.

Usage
-----

    ./ssg.tcl (init|build|upload-copy|upload-ftp) sourceDir destDir

    make init

    make build (or just make)

    make upload

Website settings
----------------
* websiteTitle {Danyil Bohdan}
* url {http://danyilbohdan.com/}
* uploadFtpServer {ftp.univ.kiev.ua}
* uploadFtpPort 21
* uploadFtpPath {incoming/upload/dotcomtest}
* uploadFtpUser {anonymous}
* uploadFtpPassword {a@b}
* expandMacrosInPages 0
* charset utf-8
* indexPage {data/input/pages/index.md}
* tagsPage {data/input/pages/blog/index.md}
* copyright {Copyright (C) 2014 P. Erson}

Per-page variables
------------------
Single lines.

* pageTitle {Some title}
* hideTitle 0/1 -- hides from <title> and <article>
* blogEntry 0/1
* hideFromList 0/1
* hideSidebar 0/1
* hidePostTags 0/1
* hideFooter 0/1
* 0 0/1
* date
* tags {tag1 tag2 {tag three with multiple words} {tag four} tag-five}
* headExtra {<link rel="stylesheet" href="./page-specific.css">}

Multiline page variables and manipulating website variables just for the
current page: set `expandMacrosInPages` to `1` and use macros like

	<%
	dict set pages $currentPageId variables headExtra {
		<link rel="stylesheet"
		href="./contact.css">
	}
	set websiteTitle blah
	lindex ""
	%>