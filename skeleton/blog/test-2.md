{
    title {Test page 2}
    author {Joe Bloggs}
    presets blog
    tags {test something}
    date 2014-03-04
    modified 2018-03-09
    more {
        markup {(<a href="$link">check out macros</a>)}
    }
    locale en_US_rot13
    {sidebar note content} {
        <h3>Nobhg</h3>
        Guvf vf gur oybt bs gur fnzcyr Gpyfft cebwrpg.
    }
    websiteTitle {FFT Grfg}
}

This page's locale is `<%! setting locale %>`.

Quis ullamco nulla anim sunt ex proident qui consequat enim adipisicing do aute irure sit dolore enim adipisicing qui sunt pariatur dolore eiusmod commodo sit laboris. Excepteur sit et magna ex labore tempor nulla.

<!--more-->

Macro test: 1 + 2 = <%= 1 + 2 %>. Set `macros 1` in `website.conf` to see.

Data test: `<%! db input get data/test.json raw %>`

Markdown data test:
<%! db input get data/test.md raw %>

Custom template demo: `<%! demo %>`

Custom command from a plugin:

><%! try { foo } on error _ { lindex {Command unavailable!} } %>
