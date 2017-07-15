#!/usr/bin/env bash

# author: Mike Gauthier <thalios at 3cx dot org>
#
# blog.sh
#

config=".config"

set -o nounset
set -o pipefail
IFS=$'\n\t'
nl=$'\n'

# Renicing to priority 10 -- it's nice to be nice.
renice -n 10 $$ > /dev/null 2>&1

#######################################################################
#######################################################################

# Setting the program name for later use.
progname=$(basename $0)

# "Declaring" some variables we'll use later.
# Why? See 'set -o nounset'. Makes finding errors MUCH easier in bash.
# It's easier to check the status of a variable with [ "$var" = "" ]
# than it is with [ "${var-}" = "" ] (and a lot easier to read), so
# that's what we're "declaring" variables.
# Also setting default value where needed.

version="0.1"
typeset -l clo_html="no" # Default is not to use html - can only be set
                         # on the command line
_DEBUG=""

# Load config varibales -- anything in this file can override any varibale
# set prior to this line
source "$config"

# After config file loaded, setting some defaults for things not set in
# config file.
editor=${editor:-"$EDITOR"}
[[ $editor == "" ]] && editor="vi"
[[ "${editor_args[@]:-}" == "" ]] && editor_args=("")
mdtool=${pandoc:-"pandoc"}
[[ "${mdtool_args[@]:-}" == "" ]] && mdtool_args=("")
tmpdir=${tmpdir:-"/tmp"}
templatefile=${templatefile:-"template.tmpl"}
rssfeedfile=${rssfeedfile:-"feed.rss"}
index_entries=${index_entries:-10} # default of 10 entires on index page
tag_prefix=${tag_prefix:-"tag_"}
baseurl=${baseurl:-}
previewpref=${previewpref:-"prev"}
blogtitle=${blogtitle:-"My Blog"}
blogsubtitle=${blogsubtitle:-"Yet another blog!"}

# Global variables not to be overridden via config.
# Or just creating global variables for easy of use later
# (due to nounset)
cleanuplist="$tmpdir/$$.cleanup"
declare OIFS   # Old IFS var - temp var just to hold the old IFS setting
POSTREGEX="^[0-9]{14}_.+\.md$"

# Printing some warnings about config variables.
warnings=""
if [[ $baseurl == "" ]]; then
  warnings+="WARNING: baseurl is empty. Previews will not work.$nl"
  baseurl="http://somesite.example"
else
  baseurl=${baseurl%"/"}
fi

if [[ $warnings != "" ]]; then
  >&2 echo -e "$warnings"
  sleep 4
fi

# // FUNCTIONS //

# Output debug information to the debug log (e.g. ./ssb3-debug.out) if
# the -d option passed on the command line or debug="yes" in the config
# file. To use, simply pass a string to this function.

DEBUG() {
  if [ "$_DEBUG" = "yes" ]; then
    _DEBUGLOG="./debug-$(basename $0).out"
    [ -n "${1-}" ] &&
      debugmsg="$1" ||
      debugmsg="Hmmm... no message sent to function _DEBUG."
    echo "[$(date '+%Y-%m-%d %I:%M:%S')] $1" | tee -a $_DEBUGLOG >&2
  fi
}

# Produces a random alphanumeric string. Only argument is the string
# length (default to 8).
randstr() {
  thislen="${1:-8}"
  thisstr="$(cat /dev/urandom | tr -dc '[:alnum:]' | head -c $thislen)"
  echo "$thisstr"
}

# Writes to system log. One argument - the log line. progname must be set
# before this funtion. Requires logger.
dolog() {
  DEBUG "Entered dolog: Writing \""${1-}"\" to log."
  logline="$1"
  logger -t "$progname[$$]" "$logline" || >&2 echo "Error writing log line: $1"
}

# cleanup -- rm any temp files, start or stop things, etc
# usually called on ERR (via trap) or at the end of the script
cleanup() {
  DEBUG "Cleaning up after myself (entered cleanup)."
  if [[ -f "$cleanuplist" ]]; then
    while read file; do
      rm -f "$file"
    done < "$cleanuplist"
    rm -f "$cleanuplist"
  fi
  DEBUG "Leaving cleanup."
}

errortrap() {
  cleanup
}

exittrap() {
  cleanup
  # >&2 echo "Site rebuild completed in $SECONDS seconds."
}

# Simple way to exit on error - two arugment
# ARG1 = the text to output to STDERR
# ARG2 = the exit code you want to exit with (defaults to 1)
# Nice to call this with a check on $? or as the right side of an ||.
errorexit() {
  DEBUG "Entered errorexit: $1"
  errortext="$1"
  exitcode="${2-"1"}" # if $2 is unset, value will be 1.
  DEBUG "In errorexit with errortext='$errortext' and exitcode='$exitcode'"
  >&2 echo -e "Error: $errortext" && dolog "Error: $errortext"
  DEBUG "Exiting with exitcode: $exitcode"
  exit $exitcode
}

# Simple secure way to make a temp filename.
# This exists because mktemp -u is discouaged by its author.
mkstemp() {
  DEBUG "Entered mkstemp."
  local mytmpfile="$tmpdir/$(randstr)"
  echo "$mytmpfile" >> "$cleanuplist"
  echo "$mytmpfile"
  DEBUG "Leaving mkstemp."
}

# Usage... nuff said.

usage() {
cat <<ENDOFUSAGE

Usage: $progname [options] <command>

Commands:
  new        Write a new blog entry.
  static     Write a new static page.
  edit       Edit an existing entry/static page. Path must be relative to
             blog_home.
  delete     Delete an entry/static page.
  rebuild    Rebuild entire site (good for updating all pages with a new
             or updated template).

Options:
  -h         Show usage.
  -v         Show version.
  -H         Force HTML only -- primarily used with static command.
             Note that HTML can be used regardless, but this will force
             markdown to NOT be processed.

ENDOFUSAGE
}

make_dummy_file() {
  outfile="$1"
  {
cat <<ENDOFDUMMY
This Line Is The Entry Title

Place the contents of your *markdown* post here -- Multiple paragraphs,
images, list, anything you want. End this file with the *optional* "%%TAGS:"
line. Tags should equal one or more comma-separated tag words associated with
the current entry. Individual tags **CAN NOT** have spaces. Recommend one use
dashes in place of spaces (e.g. "my-project" vs. "my project").

The tags line can go anywhere in this file, but it is recommended to go after
the content. It must be its own line and it must begin with "%%TAGS:".

%%TAGS: a, comma-separated, list, of, tags
ENDOFDUMMY
  } > "$outfile"
}

get_title() {
  thisfile="$1"
  thistitle=$(head -n 1 "$thisfile")
  echo "$thistitle"
}

get_tags() {
  local thesetags
  thisfile="$1"
  thesetags=$(grep -m 1 -e "^%%TAGS:" "$thisfile")
  thesetags=${thesetags/"%%TAGS:"/}
  thesetags=${thesetags//" "/}
  echo "$thesetags"
}

get_content() {

  local myfile="$1"
  local mycontfile=$(mkstemp)
  tail -n +2 "$myfile" | grep -v -e "^%%TAGS:" > "$mycontfile"
  $mdtool "${mdtool_args[@]}" "$mycontfile"
}

# Simply convert the date format from the post filename to something
# that can be used by the date command (the -d argument specifically)
# This doesn't account for timezone... that could be a problems if someone
# tries to get fancy.
convert_date() {
  local thisdate=${1:-}
  local year month day hour min

  year=${thisdate:0:4}
  month=${thisdate:4:2}
  day=${thisdate:6:2}
  hour=${thisdate:8:2}
  min=${thisdate:10:2}

  echo "${year}-${month}-${day} ${hour}:${min}"
}

# Make new entry html
make_entry() {
  local mytitle="${1-}"
  local mylink="${2-}"
  local mycontent="${3-}"
  local mytags="${4-}"
  local mydate="${5-}"
  local d_date visdate

  # Pulling individual tags out of mytags into the array tags
  local -a tags
  OIFS=$IFS
  IFS=","
  read -a tags <<<"$mytags"
  IFS=$OIFS

  # Building the tagline in html
  local x=0
  local tagline
  tagline="<div class=\"tagline\">Tags: "
  for thistag in "${tags[@]}"; do
    [[ $x == 1 ]] && tagline+=", "
    tagline+="<a href=\"$tag_prefix${thistag}.html\">$thistag</a>"
    x=1
  done
  tagline+="</div>"

  [[ $mydate == "" ]] && mydate=$(date +%Y%m%d%H%M%S)
  d_date=$(convert_date "$mydate")

  visdate="$(date -d "${d_date}" +"%B %e, %Y %H:%M %Z")"

  local newentry=""
  newentry+="<!-- start entry -->$nl"
  newentry+="<div class=\"entryholder\">$nl"
  newentry+="<div class=\"entrytitle\">$nl"
  newentry+="<h3><a href=\"$mylink\">$mytitle</a></h3>$nl"
  newentry+="<div class=\"entrysubt\">$visdate</span></a></div>$nl"
  newentry+="</div><!-- entrytitle -->$nl"
  newentry+="<div class=\"entrycontent\">$nl"

  newentry+="$mycontent"
  newentry+="$nl<!-- end content -->$nl"
  newentry+="$tagline$nl"
  newentry+="</div></div>$nl"
  newentry+="<!-- end entry -->$nl"

  echo "$newentry"
}

# Makes a filename "friendly" title for use in filenames
make_fntitle() {
  local mytitle="$1"
  echo -en "$mytitle" | tr -s 'A-Z[:blank:]' 'a-z-' | tr -d '?!@#$%^&*()[]{}/'
}

make_postpage() {
  local myfile="$1"
  local skipnewfn="${2:-}" # If set, newfn (new filname) will not be used

  [[ ${myfile:(-3)} != ".md" ]] && errorexit "Invalid filename. make_postpage requires *.md file."

  local thistitle=$(get_title "$myfile")
  local thesetags=$(get_tags "$myfile")
  local content=$(get_content "$myfile")
  local template=$(<$templatefile)
  local fntitle newfn newentry myoutput
  local mydate=""

  if [[ -z $skipnewfn ]]; then
    fntitle=$(make_fntitle "$thistitle")
    mydate="$(date +%Y%m%d%H%M%S)"
    newfn="${mydate}_$fntitle"
    cp "$myfile" "${newfn}.md" && chmod 600 "${newfn}.md"
  else
    [[ $myfile =~ $POSTREGEX ]] && mydate=${myfile:0:14}
    newfn=${myfile%".md"}
  fi

  newentry=$(make_entry "$thistitle" "${newfn}.html" "$content" "$thesetags" "$mydate")
  myoutput=${template//~~~CONTENT~~~/$newentry}

  echo -e "$myoutput" > "${newfn}.html"

}

# This makes an index page from posts. The output filename is the first
# argument (required). The postsfile is passed as the second
# argument and should be a string containing a list of .md files, one per
# line (required). The second argument is the optional title of the page.
make_index() {

  local outfile="${1:-}"
  local postslist="${2:-}"
  local pagetitle="${3:-}"
  local fname line x
  local readmore
  local mycontent=""
  local template=$(<$templatefile)
  local myoutput
  local breakregex='^<hr\ */*>$'

  [[ $pagetitle != "" ]] && mycontent+="<h1 class=\"pagetitle\">$pagetitle</h1>$nl"

  for fname in $postslist; do
    x=0
    while read line; do
      [[ $line == "<"'!'"-- start entry -->" ]] && x=1
      [[ $line == "<"'!'"-- end content -->" ]] && x=1
      if [[ $x == 1 ]]; then
        if [[ $line =~ $breakregex ]]; then
          readmore="<p><a href=\"$fname\">Read more...</a></p>"
          mycontent+="$readmore$nl"
          x=0
        else
          mycontent+="$line$nl"
        fi
        if [[ $line == "<"'!'"-- end entry -->" ]]; then
          mycontent+="$nl"
          break
        fi
      fi
    done < "$fname"
  done

  mycontent+="<div class=\"linksline\">$nl"
  mycontent+="[ <a href=\"allposts.html\">More posts</a> | <a href=\"alltags.html\">All tags</a> | <a href=\"$baseurl/feed.rss\">Subscribe</a> ]$nl"
  mycontent+="</div>$nl"

  myoutput=${template//~~~CONTENT~~~/$mycontent}
  echo -e "$myoutput" > "$outfile"

}

make_indexpage() {

  local postsfile

  >&2 echo "Builing index page (the front page) with $index_entries entries... "

  postsfile="$(ls -1 [0-9][0-9][0-9][0-9]*.html | sort -nr | head -n $index_entries)"
  make_index index.html "$postsfile"

  >&2 echo "done."

}

# Makes a simple RSS 2.0 feed file. The file location can be set
# by using the rssfeedfile config option (var). It defaults to 
# "feed.rss".
make_rssfeed() {

  local c     # c for content
  local pubdate
  local file
  local thistitle thiscontent thisdate

  >&2 echo "Building RSS feed..."

  c+='<?xml version="1.0" encoding="UTF-8" ?>'"$nl"
  c+='<rss version="2.0">'"$nl"
  c+="<channel>$nl"
  c+="  <title>$blogtitle</title>$nl"
  c+="  <link>$baseurl</link>$nl"
  c+="  <description>$blogsubtitle</description>$nl"
  c+="  <language>en-us</language>$nl"

  pubdate=$(date +"%a, %d %b %Y %H:%M:%S %Z")

  c+="  <pubDate>$pubdate</pubDate>$nl"
  c+="  <lastBuildDate>$pubdate</lastBuildDate>$nl"
  c+="  <docs>http://www.rssboard.org/rss-specification</docs>$nl"
  c+="  <generator>blog.sh</generator>$nl"

  while read file; do
    thistitle=$(get_title "$file")
    thiscontent=$(get_content "$file")
    thisdate=$(convert_date "${file:0:14}")
    pubdate=$(date -d "$thisdate" +"%a, %d %b %Y %H:%M:%S %Z")

    c+="  <item>$nl"
    c+="    <title>$thistitle</title>$nl"
    c+="    <link>$baseurl/${file%".md"}.html</link>$nl"
    c+="    <author></author>$nl"
    c+="    <pubDate>$pubdate</pubDate>$nl"
    c+="    <guid>$baseurl/${file%".md"}.html</guid>$nl"
    c+="    <description><![CDATA[$nl"
    c+="${thiscontent}$nl"
    c+="]]>$nl"
    c+="    </description>$nl"
    c+="  </item>$nl"
  done

  c+="</channel>$nl"
  c+="</rss>$nl"

  echo -e "$c" > "$rssfeedfile"

  >&2 echo "Done."

} < <(ls -1 [0-9][0-9][0-9][0-9]*.md | sort -nr | head -n $index_entries)
 
# Makes the page that contains links to all post on this blog
# separated by month/year
make_allpage() {

  local postcount=0
  local fname bname pdate
  local sect_date last_sect_date=""
  local thistitle thisdate thesetags
  local mycontent myoutput
  local template=$(<$templatefile)
  local postsfile=$(mkstemp)
  local tagsfile=$(mkstemp)
  local -A posts
  local -A tags

  >&2 echo "Building all other pages..."

  # Building array and file containing list of all posts on this blog
  for fname in *.md; do
    if [[ $fname =~ $POSTREGEX ]]; then
      thistitle="$(get_title "$fname")"
      thesetags="$(get_tags "$fname")"
 
      posts[$fname]="$thistitle"$'\t'"$thesetags"
      echo -e "$fname\t$thistitle\t$thesetags" >> $postsfile
    fi
  done

  tmpposts=$(sort -nr $postsfile)
  echo -e "$tmpposts" > $postsfile
  unset tmpposts

  #cp $postsfile /tmp/postsfile  # DELETEME

  # Building array and file containing list of all tags and the
  # posts tagged by each
  fname=""
  thistitle=""
  thesetags=""

  while read fname _ thesetags; do
    local -a mytags
    # Replacing the field delimeter "," with a tab in thesetags
    # IFS is $'\n\t'.
    thesetags=${thesetags//,/$'\t'}
    read -a mytags <<<"$thesetags"
    for t in "${mytags[@]}"; do
      tags[$t]+="${fname},"
    done
  done < $postsfile

  for x in "${!tags[@]}"; do 
    echo -e "$x\t${tags[$x]}" >> $tagsfile
  done

  # Sorting tagsfile
  tmptags=$(sort $tagsfile)
  echo -e "$tmptags" > $tagsfile
  unset tmptags

  #cp $tagsfile /tmp/tagsfile  # DELETEME

  # Creating the allposts.html file -- this file lists all posts
  # broken out by month and year.
  >&2 echo -n "  Creating allpost.html... "
  mycontent+="<h1 class=\"pagetitle\">All posts</h1>$nl"

  fname=""
  while read fname _; do
    (( postcount++ ))
    bname=${fname%".md"}
    pdate=${bname:0:8}
    sect_date="$(date -d "$pdate" "+%B %Y")"
    if [[ $sect_date != $last_sect_date ]]; then
      [[ $postcount -gt 1 ]] && mycontent+="</ul>$nl"
      mycontent+="<h2>$sect_date</h2>$nl"
      mycontent+="<ul>$nl"
      last_sect_date=$sect_date
    fi
    thistitle="$(get_title "$fname")"
    thisdate="$(date -d "$pdate" "+%B %_d, %Y")"
    mycontent+="<li><a href=\"${bname}.html\">$thistitle</a> &mdash; $thisdate</li>$nl"

  done < $postsfile

  mycontent+="</ul>$nl"

  myoutput=${template//~~~CONTENT~~~/$mycontent}
  echo -e "$myoutput" > "allposts.html"

  >&2 echo "done."


  # Creating alltags.html file -- this file lists all posts
  # broken out by tag. Also creating individual tag category
  # files (tag_<tag name>.html).
  >&2 echo -n "  Creating tag pages (alltags.html & tag_<tag name>.html)..."
  mycontent=""
  myoutput=""
  fname=""
  bname=""
  thistitle=""
  thistag=""

  local fnames_index

  mycontent+="<h1 class=\"pagetitle\">All tags</h1>$nl"

  while read thistag fnames; do
    # Replacing the field delimeter "," with a tab in fnames
    # IFS is $'\n\t'.
    fnames=${fnames//,/$'\t'}

    mycontent+="<h2><a href=\"tag_${thistag}.html\">$thistag</a></h2>$nl"
    mycontent+="<ul>$nl"
    for fname in $fnames; do
      bname=${fname%".md"}
      read thistitle _ <<<"${posts[$fname]}"
      mycontent+="<li><a href=\"${bname}.html\">$thistitle</a></li>$nl"
      # Building list of file names to send to make_index
      # to make the tag_<tage name>.html for this tag
      fnames_index+="${bname}.html"$'\n'
    done
    mycontent+="</ul>$nl"

    # Create the tag_<tag name>.html page
    fnames_index=$(sort -r <<<"$fnames_index")
    make_index "tag_${thistag}.html" "$fnames_index" "Tag: $thistag"
    fnames_index=""   # Clearing this for next iteration

  done < $tagsfile

  myoutput=${template//~~~CONTENT~~~/$mycontent}
  echo -e "$myoutput" > "alltags.html"

  >&2 echo "done."
  >&2 echo "done."

}

# Copies file (arg1) to the preview directory and generates a preview
# URL. Also makes sure preview directory exists. If nor, creates it.
# Preview file name will be based on title and some random string
# of characters. New file will be added to the "cleanup" file for
# later removal.
make_preview() {
  local thisfile=${1:-""}
  local prevfn thismd thishtml

  [[ $thisfile == "" ]] && errorexit "No file to make_preview with."

  prevfn="$(randstr 6)"
  thismd="${previewpref}-${prevfn}.md"
  thishtml="${previewpref}-${prevfn}.html"
  cp "$thisfile" "$thismd"
  make_postpage "$thismd" skip

  echo "$PWD/$thismd" >> "$cleanuplist"
  echo "$PWD/$thishtml" >> "$cleanuplist"
  echo "$baseurl/$thishtml"
}


# Editing an existing or creating a new entry
# This should support editing already posted content as well as
# editing posts that are still drafts (in the drafts directory)
do_edit() {
  local editfile=${1:-}
  local thisfile=$(mkstemp)".md"
  local edit_type=""
  local previewurl=""
  local -l myresp="" # -l forces assigned values to lowercase
  local newfn

  # First thing... check that this is a .md file
  [[ $editfile != "" && ${editfile:(-3)} != ".md" ]] && errorexit "Error: Can only edit *.md files."

  # If no editfile passed in, this is a new post, so we'll make a dummy file
  if [[ $editfile == "" ]]; then
    edit_type="new"
    make_dummy_file "$thisfile"

  # If an edit file was passed in, then we'll do some checks on it, then
  # edit it
  elif [[ -f $editfile ]]; then
    edit_type="existing"
    local o_editfile="$editfile"
    editfile=${editfile#"$PWD/"}  # Making path relative (if full path)
    editfile=${editfile#"./"}     # Removing leading ./ if exists
    # Checking to see if editfile exits within PWD (blog's home)
    [[ ! -f "$PWD/$editfile" ]] && errorexit "Error: $o_editfile does not exist inside this blog's home ($PWD)."
    local dir_regex="^.*/.*$"    
    if [[ $editfile =~ $dir_regex ]]; then
      if [[ ${editfile:0:7} == "drafts/" ]]; then
        edit_type="draft"
      else
        errorexit "Error: I can only edit *.md files in this blog's home ($PWD) or its drafts ($PWD/drafts) directories."
      fi
    fi
    cat "$editfile" > "$thisfile"
    echo "$thisfile" >> $cleanuplist
  else
    errorexit "Error: $editfile does not exist. Cannot edit."
  fi

  # Now what do you want to do wih this edited/new file?
  while [[ $myresp == "" ]]; do

    $editor ${editor_args[@]} "$thisfile" || errorexit "Error: unable to edit file $thisfile ."
    [[ $previewurl == "" ]] && previewurl=$(make_preview "$thisfile")
  	while [[ $myresp == "" ]]; do
        echo "Preview is at: $previewurl"
        if [[ $edit_type == "existing" ]]; then
          echo -n "[p]ost, [E]dit again, or [d]iscard changes? (p/E/d) "
        else
          echo -n "[p]ost, [E]dit again, [s]ave to draft, or [d]iscard? (p/E/s/d) "
        fi

       read -r myresp
       [[ $myresp == "" ]] && myresp="e"
       local respregex="^(p|e|s|d)$"
       [[ $edit_type == "existing" ]] && respregex="^(p|e||d)$"

       if [[ ! $myresp =~ $respregex ]]; then
         echo " Error: Invalid response." >&2
         myresp=""
       fi
	  done

    # Now that we have a response, do what you're told.

    # If [e]dit, set to nothing so it'll loop back to the top and open
    # this file for editing again
    [[ $myresp == "e" ]] && myresp=""

    # If [d]iscard was chosen, exit immediately. Trap/cleanup routine
    # will take care of lingering tmp files and such.
    if [[ $myresp == "d" ]]; then
      echo -n "Are you sure you wish to DISCARD you post? (y/n) "
      read -r ynresp
      [[ $ynresp == "y" ]] && exit 1
      myresp=""
    fi

  done

  # [s]ave to draft - only for new files (edit_type=new) or existing
  # draft (edit_type=draft) files. edit_type=existing should never get here
  if [[ $myresp == "s" && $edit_type != "existing" ]]; then
    mkdir -p drafts || errorexit "Error: Unable to create drafts directory."
    chmod 700 drafts # This *should* prevent webserver access to drafts
    if [[ $editfile == "" ]]; then
      thistitle=$(get_title "$thisfile")
      fntitle=$(make_fntitle "$thistitle")
      draftfn="$fntitle.$(randstr 4).md"
      cp "$thisfile" "drafts/$draftfn"
      echo "$thisfile" >> $cleanuplist
      echo "Draft saved to drafts/${draftfn}." >&2
    elif [[ $edit_type == "draft" ]]; then
      cat "$thisfile" > "$editfile"
      echo "$thisfile" >> $cleanuplist
      echo "Draft saved to $editfile." >&2
    else
      cat "$thisfile" > "$editfile"
    fi
  fi

  # [p]ost to blog - edit_type=existing needs to be treated specially
  if [[ $myresp == "p" ]]; then

    if [[ $edit_type == "existing" ]]; then
      # Creating new filename (just in case title was edited)
      newfn="${editfile:0:14}_$(make_fntitle "$(get_title "$thisfile")")"
      # Remove the old fileis before making new from edited content
      rm -f "${editfile%".md"}".*
      # Copy new content into new filename (could be same as old if same title)
      cat "$thisfile" > "${newfn}.md"
      make_postpage "${newfn}.md" skip
    else
      make_postpage "$thisfile"
    fi
    make_indexpage
    make_allpage
    make_rssfeed
    [[ $edit_type == "draft" ]] && echo "$editfile" >> $cleanuplist

  fi

}

do_static() {
  echo "do_static still needs to be created" 
}

do_delete() {
  echo "Delete option not yet implemented. To delete a post manually, simply"
  echo "delete (rm) the associated YYYYMMDDhhmmss_title.md and .html files."
  echo "Run '$0 rebuild' to rebuild the site minus the deleted files."
}

do_rebuild() {
  local fname;

  >&2 echo "Rebuilding individual post pages... "
  # while read fname; do
  for fname in *.md; do
    if [[ $fname =~ $POSTREGEX ]]; then
      >&2 echo "   - ${fname%".md"}"
      make_postpage "$fname" skip
    fi
  done
  # done < <(ls -1 [0-9][0-9][0-9][0-9]*.md | sort -nr)
  >&2 echo "done."

  make_indexpage
  make_allpage
  make_rssfeed

}


#################
## MAIN PROGGY ##
#################

# Always trap first
trap errortrap ERR
trap exittrap EXIT

while getopts ":h :v :H" opt
do
  case $opt in
    h)
      usage
      exit 0
      ;;
    v)
      echo "$progname - version: $version"
      exit 0
      ;;
    H)
      clo_html="yes"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done

# Resetting positon on ARGs
shift $((OPTIND-1))
numopts=$#

# Setting up template file. Inserts TITLE, SUBTITLE, and BASEURL. CONTENT
# is left for later manipulation.
tmptemplate=$(mkstemp)
sed -e "s#~~~TITLE~~~#$blogtitle#g; s#~~~SUBTITLE~~~#$blogsubtitle#g; s#~~~BASEURL~~~#$baseurl#g;" "$templatefile" > "$tmptemplate"
templatefile="$tmptemplate"

case ${1-} in
  new)
    do_edit
    ;;
  static)
    do_static
    ;;
  delete)
    do_delete
    ;;
  rebuild)
    do_rebuild
    ;;
  edit)
    if [[ $numopts -ge 2 ]]; then
      do_edit "$2"
    else
      errorexit "Command 'edit' requires the markdown filename as the argument."
    fi
    ;;
  *)
    >&2 echo -e "Error: you did not provide a valid command." && usage
    exit 1
esac

