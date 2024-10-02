![A stylized feather and the text "Tclssg".](logo/tclssg-logo-text-small.png)

Tclssg is a full-featured extensible static site generator designed for Tcl programmers.
It aims to make it easy to manage a static website with an optional blog.
Tclssg website projects with a few hundred pages usually build in under a minute on modest hardware.

Features
--------

- [Markdown](#markup)
- [Bootstrap 3](http://getbootstrap.com/docs/3.4/) (with Bootstrap theme support)
- Tcl code embedded in HTML for [templates](https://github.com/tclssg/tclssg/wiki/Templating)
- Regular pages and blog posts[^1]
- Footnotes
- Feeds with new blog posts: RSS, [JSON Feed](https://jsonfeed.org/version/1.1), and [twtxt](https://twtxt.readthedocs.io/en/latest/user/twtxtfile.html#format-specification)
- SEO and usability features out of the box: site maps, canonical and previous/next links, `noindex` on collection pages
- Valid HTML5 and CSS level 3 output
- Legacy deployment over FTP
- Deployment over SCP and in other ways with a [custom deployment command](https://github.com/tclssg/tclssg/wiki/Using-deployCustom)
- Support for external comment engines (currently: Disqus)
- Relative links in the HTML output that make it browsable over *file://*
- [Pretty fast](https://github.com/tclssg/tclssg/wiki/Benchmarks)
- Few dependencies.
  Experimental self-contained [binaries](https://github.com/tclssg/tclssg/wiki/Binaries) are available for Linux, Mac, and Windows.

[^1]: Unlike a regular page, a blog post has a sidebar with tags and links to other blog posts sorted by recency.
      The latest posts are featured in the blog index, and tag pages are generated to collect blog posts with the same tag.

Page screenshot
---------------
![A test page built with Tclssg.](screenshot.png)

Getting started
---------------

Tclssg is known to work on Linux, FreeBSD, NetBSD, OpenBSD, macOS, and Windows 7/8.x/10/11.

To use Tclssg, you will need Tcl 8.6 or 9, Tcllib 1.21 or later, and SQLite 3 bindings for Tcl.
Tclssg can optionally use [cmark](https://github.com/commonmark/cmark) and [tidy-html5](https://www.html-tidy.org).

To install the dependencies on **Debian** or **Ubuntu**, run the following command:

    sudo apt install libsqlite3-tcl tcl tcllib

On **Fedora**:

    sudo dnf install sqlite-tcl tcl tcllib

On **Windows 7 and later**, the recommended way to run Tclssg is to install [Magicsplat Tcl/Tk for Windows](https://www.magicsplat.com/tcl-installer/).
The copy of Tcl that comes with [Git for Windows](https://gitforwindows.org/) does not include Tcllib or the SQLite 3 extension, so it will not run Tclssg out of the box.

On **macOS**, use [Homebrew](https://brew.sh/) or [MacPorts](https://www.macports.org/).

Homebrew:

    brew install tcl-tk

MacPorts:

    sudo port install tcllib tcl-sqlite3

Once you have the dependencies installed, clone this repository, `cd` into it, then run

    ./ssg.tcl init
    ./ssg.tcl build --local
    ./ssg.tcl serve --browse

or on Windows

    ssg.cmd init
    ssg.cmd build --local
    ssg.cmd serve --browse

This will create a new website project in the directory `website/` based on the default project skeleton, build the website in `website/output/`, and open the result in your web browser.

Markup
------

Tclssg uses [Markdown](http://daringfireball.net/projects/markdown/syntax).
In blog posts `<!-- more -->` designates a break between the teaser (the part of the article shown in the blog index and on tag pages) and the rest of the content.
Use page settings to customize the page's output.

Example:

```markdown
{
    title {Test page}
    blogPost 1
    tags {test {a long tag with spaces}}
    date 2014-01-02
    show {
        date false
    }
}
**Lorem ipsum** reprehenderit _ullamco deserunt sit eiusmod_ ut minim in id
voluptate proident enim eu aliqua sit.

<!-- more -->

Mollit ex cillum pariatur anim [exemplum](http://example.com) tempor
exercitation sed eu Excepteur dolore deserunt cupidatat aliquip irure in
fugiat eu laborum est.
```

User's guide
------------

For more information on how to use Tclssg, read the **User's guide** on the [project wiki](https://github.com/tclssg/tclssg/wiki).

Answers to frequently asked questions can be found in the [FAQ](https://github.com/tclssg/tclssg/wiki/FAQ).

License
-------

MIT. See the file [`LICENSE`](LICENSE) for details.

The Tclssg logo images are copyright (c) 2014 D. Bohdan and are distributed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

[`skeleton/static/images/placeholder.jpg`](skeleton/static/images/placeholder.jpg) is cropped from a [photo](https://unsplash.com/photos/AsNfzwdcz2I) by Daniel Olah distributed under the [Unsplash license](https://unsplash.com/license).

The [stackato-cli](https://github.com/ActiveState/stackato-cli) browse package is copyright (c) 2011-2012 ActiveState Software Inc.
It is distributed under the Apache License, Version 2.0.
See [`vendor/browse/license.txt`](vendor/browse/license.txt).
