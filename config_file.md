# Config File

The configuration file for a particular blog is .config. It is recommended that one use web server configuration to deny access to this log or simply ensure local file permission prevent the web server from reading it.

.htaccess
```
<Files ".config">
  Require all denied
</Files>
```

File permissions
```
[user@devserv blog]$ ls -l .config
-rw-rw-r--. 1 user user 439 May 27 17:17 .config
[user@devserv blog]$ chmod 600 .config
[user@devserv blog]$ ls -l .config
-rw-------. 1 user user 439 May 27 17:17 .config
```

## Syntax

The config file is simply a file containing bash varibale definition. All rules regarding varibales in bash apply.

## Configuration directives

editor
  * The editor to be used. Will default to environment variable EDITOR and then vi.

editor_args
  * An array of optional arguments to be used with the editor.

mdtool
  * The tool to use to convert the markdown files into html. Defaults to pandoc.

mdtool_args
  * An array of optional arguments to be used with the markdown tool.

tmpdir
  * Location of the temp directory. Default to /tmp.

templatefile
  * Name of the template file. Defaults to template.tmpl.

rssfeedfile
  * Name of the output file of the rss feed xml. Defaults to feed.rss.

index_entries
  * Number of posts to be rendered on the index page. Defaults to 10.

tag_prefix
  * Filename prefix for the tag pages (html files). Defaults to "tag_".

**baseurl** (MUST BE SET IN CONFIG)
  * Base URL of the blog. Include directory if needed (e.g. https://somesite.xyz/blog). There is no default. This must be set in the config file.

previewpref
  * Filename prefix for preview files/URLs. Defaults to "prev".

blogtitle
  * Primary title of blog. Defaults to "My Blog".

blogsubtitle
  * Subtitle of blog. Defaults to "Yet another blog!"

post_footer
  * A footer to be attached to the end of the each post's content. `~~~PAGEURL~~~` and `~~~PAGETITLE~~~` template variables are recognized if used in this directive.

index_post_footer
  * A footer to be attached to the end of the each post's content ON THE INDEX PAGE ONLY. This will be in addition to the post footer. The same template variables as post_footer are recognized.

post_page_footer
  * A footer attached just below the post's content on the post's specific page. This will be in addition to the post footer. The same template variables as post_footer are recognized.
