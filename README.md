ssg-tcl
=======

A static website generator written in Tcl for danyilbohdan.com.

To use `ssg-tcl` you'll need Tcl 8.5 and Tcllib.

Generates blogs. All blog entries have a sidebar. Relative links.
Tags. HTML5.

Usage
-----

    ./ssg.tcl (init|build|upload-copy|upload-ftp) sourceDir destDir

    make init

    make build (or just make)

    make upload

Website settings
----------------
websiteTitle {Danyil Bohdan}
url {http://danyilbohdan.com/}
uploadDestCopy {/tmp/dest}
uploadDestFTP {ftp://ftp.univ.kiev.ua/incoming/upload/dotcomtest}
expandMacrosInPages 0
charset utf-8
indexPage {data/input/pages/index.md}

Per-page variables
------------------
Single lines.

pageTitle {Some title}
hideTitle 0/1 -- hides from <title> and <article>
blogEntry 0/1
hideFromList 0/1
hideSidebar 0/1
hideTagCloud 0/1
hideFooter 0/1
date
tags {tag1 tag2 {tag three with multiple words} {tag four} tag-five}
headExtra {<link rel="stylesheet" href="./contact.css">}