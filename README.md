ssg-tcl
=======

A small static site generator with template support written in Tcl for danyilbohdan.com.

Features
--------

* Mark up content with Markdown.
* Produce plain old pages or blogs post. [1]
* Tag blog entries. Show a tag cloud.
* Upload the resulting website over FTP with a single command.
* Embed Tcl code in HTML for templating. [2]
* Generated links are all relative.
* Output is valid HTML5 and CSS level 3.

1\. Blog posts feature a sidebar linking to other blog posts sorted by date.

2\. Templating example:

        <article>
        <% textutil::indent $content {        } %>
        </article>

Installing
----------

To use `ssg-tcl` you will need Tcl 8.5 or newer and Tcllib installed. You will also need a Markdown processor to turn Markdown into HTML. The default processor Markdown shipped with `ssg-tcl` is [Markdown 1.0.1](http://daringfireball.net/projects/markdown/), which requires Perl 5.

Installing Tcl + Tcllib on Debian/Ubuntu:

    sudo apt-get install tcl tcllib

On Fedora/RHEL/CentOS:

    su -
    yum install tcl tcllib

Usage
-----

    usage: ./ssg.tcl <command> [sourceDir [destDir]]

`sourceDir` specifies the directory where the input for ssg-tcl is located. It defaults to `data/input` in the current directory.
`destDir` us were the HTML is put. It defaults to `data/output`.

The default layout of the source directory is

    .
    ├── pages <-- Markdown files from which HTML is generated
    │   ├── blog
    │   │   └── index.md <-- Blog index page with tag list
    │   │                    and links to blog posts.
    │   ├── index.md <-- Website index page.
    ├── static
    │   └── main.css
    ├── templates
    │   └── default.thtml <-- The website's layout
    │                         template (HTML + Tcl)
    └── website.conf <-- Configurating file.



The possible commands are

* `init`      create project skeleton
* build       build static website
* clean       delete files in destDir
* upload-copy copy files to destination set in config
* upload-ftp  upload files to FTP server set in config
* open        open index page in the default browser



Website settings
----------------

`data/input/website.conf`

* websiteTitle {My Awesome Website}
* url {http://example.com/}
* uploadFtpServer {ftp.hosting.example.net}
* uploadFtpPort 21
* uploadFtpPath {htdocs}
* uploadFtpUser {user}
* uploadFtpPassword {password}
* expandMacrosInPages 0/1
* charset utf-8
* indexPage {data/input/pages/index.md}
* tagsPage {data/input/pages/blog/index.md}
* copyright {Copyright (C) 2014 You}

All 0/1 settings default to 0.

Per-page variables
------------------
Single lines. Format: a separate lines per variable that say

    ! variableNameOne short_value
    ! variableNameTwo {A variable value with spaces.}

* pageTitle {Some title}
* hideTitle 0/1 -- hides from <title> and <article>
* blogEntry 0/1
* hideFromList 0/1
* hideSidebar 0/1
* hidePostTags 0/1
* hideFooter 0/1
* showTagCloud 0/1
* date
* tags {tag1 tag2 {tag three with multiple words} {tag four} tag-five}
* headExtra {<link rel="stylesheet" href="./page-specific.css">}

All 0/1 settings default to 0.

Multiline page variables and manipulating website variables just for the current page: set `expandMacrosInPages` to `1` and use a macro like

    <%
    dict set pages $currentPageId variables headExtra {
        <link rel="stylesheet"
        href="./contact.css">
    }
    set websiteTitle blah
    lindex ""
    %>

Sample session
--------------

    $ ./ssg.tcl build
    Loaded config file:
        websiteTitle Danyil Bohdan
        url http://danyilbohdan.com/
        uploadCopyPath /tmp/dest
        uploadFtpServer ftp.<webhost>.com
        uploadFtpPath danyilbohdan.com
        uploadFtpUser dbohdan
        uploadFtpPassword ***
        expandMacrosInPages 0
        indexPage data/input/pages/index.md
        tagPage data/input/pages/blog/index.md
    processing page file data/input/pages/contact.md into data/output/contact.html
    processing page file data/input/pages/index.md into data/output/index.html
    processing page file data/input/pages/total.md into data/output/total.html
    processing page file data/input/pages/blog/index.md into data/output/blog/index.html
    copying static file data/input/static/main.css to data/output/main.css
    copying static file data/input/static/contact.css to data/output/contact.css
    $ ./ssg.tcl upload-ftp
    Loaded config file:
        websiteTitle Danyil Bohdan
        url http://danyilbohdan.com/
        uploadCopyPath /tmp/dest
        uploadFtpServer ftp.<webhost>.com
        uploadFtpPath danyilbohdan.com
        uploadFtpUser dbohdan
        uploadFtpPassword ***
        expandMacrosInPages 0
        indexPage data/input/pages/index.md
        tagPage data/input/pages/blog/index.md
    uploading data/output/index.html as danyilbohdan.com/index.html
    uploading data/output/total.html as danyilbohdan.com/total.html
    uploading data/output/contact.html as danyilbohdan.com/contact.html
    uploading data/output/main.css as danyilbohdan.com/main.css
    uploading data/output/contact.css as danyilbohdan.com/contact.css
    uploading data/output/blog/index.html as danyilbohdan.com/blog/index.html

License
-------

MIT. See the file `LICENSE` for details.

`ssg-tcl` includes a copy of Markdown 1.0.1, which is copyright (c) 2004, John Gruber, and is distributed under a three-clause BSD license. See `scripts/Markdown_1.0.1/License.text`.
