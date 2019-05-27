# blog.sh - A relatively simple bash-based blogging application

Author: Mike Gauthier &lt;thalios1973 at 3cx dot org&gt;

## VERSION HISTORY

* 0.1.0 First relatively working version. Certainly some bugs. Being used actively at [blog.3cx.org](http://blog.3cx.org).
* 0.1.1 New feature - per post footers. One can specify in the config file a footer for each post, a footer for each post for display on the index page, and a footer for each post's html page. One use case is to integrate with a commenting system like [Isso][isso]

## WHY BASH?

Because I can? I guess that's the truth of it. I was inspired by [Carlos Fenollosa's][1] [bashblog][2]. I used it on my own blog for a bit and made some tweaks and contributions to the code, but I thought it could be done differently and maybe even better (my way!). So I wrote (am writing) bash.sh from scratch. bashblog was definitely my inspiration, but I took zero code from it.

## FEATURES

* Supposed to be simple. Right now less than 1000 lines of code.
* Basic features for blogging
  * Create new
  * Save to draft
  * Edit existing or draft
  * Rebuild of site (good for updating the template)
  * Static page support.
* Very basic templating - variable substition (TITLE, SUBTITLE, etc.). Currently supported variables
  * `~~~TITLE~~~` - set in .config as blogtitle
  * `~~~SUBTITLE~~~` - set in .config as blogsubtitle
  * `~~~BASEURL~~~` - the base URL of the blog set in .config as baseurl
  * `~~~CONTENT~~~` - the generated content of the page
  * `~~~PAGETITLE~~~` - the specific title of the specific post
  * `~~~PAGEURL~~~` - the URL (permalink) of the specific post
* Per post footers. Support three types of footers that can be added as a config file variable.
  1. post_footer - a footer attached to the end of the post content
  2. index_post_footer - a footer attached to the end of the post content on the index page
  3. post_page_footer - a footer attached just below the post content on the post's specific page  
  Two templating tags are supported in these config variables.
    * `~~~PAGEURL~~~` - the URL (permalink) of the specific post.
    * `~~~PAGETITLE~~~` - the specific title of the specific post
* Uses all standard utilities available on any modern Linux/Unix system. Should work in Cygwin as well.
  * The only exception to this is [pandoc](http://pandoc.org/) for markdown parsing. One could use something else, but I chose pandoc because it provides for a LOT of flexibility.
  * The emoji extension and full github style markdown are useful.
* Simple RSS support. Creates a feed.rss file for syndication ([Simple RSS 2.0][3])

**MORE TO COME**

[1]: https://github.com/cfenollosa
[2]: https://github.com/cfenollosa/bashblog
[3]: http://www.rssboard.org/rss-specification
[isso]: https://posativ.org/isso/
