#!/usr/bin/perl -w

use POSIX qw(floor);
use strict;

sub get_meta {
    my ($tag, $file) = @_;

    open (FILE, $file) || die "Cannot open $file.";
    my @input = <FILE>;
    close (FILE);
    foreach (@input) {
        if (/\@$tag=([^@]+)@/) {
            return $1;
        }
    }
    die "`$tag' is not defined in file `$file'\n";
}

sub get_tags {
    my ($file) = @_;

    my @tags = split (",", get_meta ("tags", $file));
    return @tags;
}

sub make_tagslist {
    my @tags = @_;
    my $tags = "";
    $tags = "<ul>\n";
    foreach my $tag (@tags) {
        my $tag_file = $tag;
        $tag_file =~ s/ /_/g;
        $tag_file =~ s#/#_#g;
        $tags.= '<li><a href="tag_' . $tag_file . '.html">' . $tag . "</a></li>\n";
    }
    $tags.= "</ul>\n";
    return $tags;
}

sub make_template {
    my ($blog_title, $tags_list, $postlist) = @_;
    open (TPL, "plog.tpl") || die "plog.tpl couldn't be found.";
    my @template = <TPL>;
    close (TPL);
    
    my ($header_tag, $header_end);
    foreach my $line (@template) {
        #print "$line", "\n";
        chomp $line;
        if ($line eq '@end header@') {
            $header_tag++;
            last;
        }
        $header_end++;
    }
    
    if (!$header_tag) {
        die "There is no header end tag in file `plog.tpl'\n";
    }
    
    @template = @template[$header_end + 1 .. $#template];

    foreach (@template) {
        s/%blogtitle%/$blog_title/g;
        s/%taglist%/$tags_list/g;
        s/%postlist%/$postlist/g;
    }
    return join ("", @template);
}

sub get_content {
    my ($file) = @_;
    open (FILE, $file) || die "$file cannot be opened.";
    my @file = <FILE>;
    close (FILE);

    my ($content_tag, $content_pos, $content);
    foreach my $line (@file) {
        chomp $line;
        if ($line eq '@content@') {
            $content_tag++;
            last;
        }
        $content_pos++;
    }
    
    if (!$content_tag) {
        die "There is no content tag in file `$file'\n";
    }
    
    return join ("", @file[$content_pos + 1 .. $#file]);
}

sub make_post {
    my ($file, $master_tpl) = @_;

    my $title = get_meta ("title", $file);
    my $tags = make_tagslist (get_tags ($file));
    open (FILE, $file) || die "Cannot open $file.";
    my @post = <FILE>;
    close (FILE);
    
    my $content = get_content ($file);

    #templating.
    open (TPL, 'post.tpl') || die "Cannot open file `post.tpl'";
    my @post_tpl = <TPL>;
    close (TPL);
    foreach (@post_tpl) {
        s/%this%/$file/g;
        s/%title%/$title/g;
        s/%tags%/$tags/g;
        s/%content%/$content/g;
    }
    return (join ("", @post_tpl));
}

#Getting the output dir
my $outdir;
if (@ARGV == 2 && $ARGV[0] eq "-out") {
    $outdir = $ARGV[1];
} else {
    $outdir = "out";
}

#Checking the outdir.
$outdir =~ s#/$##;

#Getting the list of files
opendir (CUR_DIR, "./");
my @posts = grep (/^post.+\.html$/, readdir CUR_DIR);

@posts = sort (@posts);
@posts = reverse @posts;

#Working out the postlist
my (%postlist, @content, %tags, $url);
my ($tags, $blog_title, $postlist, $rss);
$postlist = "<ul>\n";
foreach my $post (@posts) {
    $postlist{$post} = get_meta ("title", $post);
    $postlist.= '<li><a href="' . $post . '">' . get_meta ("title", $post) . "</a></li>\n";
}
$postlist.= "</ul>\n";


# getting the url.
$url = get_meta ("url", 'plog.tpl');
$_ = $url;
if (/[^\/]$/) {
    $url.= "/";
}

# Generating the master template
# Getting the tags
foreach my $post (keys %postlist) {
    foreach my $tag (get_tags ($post)) {
        $tags{$tag}++;
    }
}
# Generating tags list
$tags = make_tagslist (keys %tags);

$blog_title = get_meta ("blogtitle", "plog.tpl");

# Generating the rss feed.
$rss = '<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">

  <channel>
    <title>'. $blog_title .'</title>
    <link>'. $url .'</link>
    <language>en</language>';

foreach my $post (@posts) {
    $rss.= "<item>\n";
    $rss.= "<title>". $postlist{$post} ."</title>\n";
    $rss.= "<link>". $url . $post ."</link>\n";
    my $summary = get_content ($post);
    $summary =~ s/<[^>]*>//g;
    if (length ($summary) > 500) {
        $summary = substr ($summary, 0, 500);
        $summary.= "[...]";
    }
    $rss.= "<description>". $summary ."</description>\n";
    $rss.= "</item>\n";
}

$rss.= "</channel>\n</rss>\n";

print "Generated rss feed.\n";

my $master_tpl = make_template ($blog_title, $tags, $postlist);

# Cleaning up the output.
if (-e $outdir) {
    if (-d $outdir) {
        # Deleting the out directory.
        my @files = glob ("$outdir/*");
        foreach my $weed (@files) {
            unlink $weed;
        }
        rmdir $outdir;
    } else {
        die "'$outdir' is not a directory.";
    }
}
mkdir $outdir;

# Generating posts pages.
%tags = ();
my $i = 0;
foreach my $post (@posts) {
    my $o_post = make_post ($post, $master_tpl);
    $content[$i++] = $o_post;
    # Writing post.
    open (POST, ">$outdir/" . $post);
    $_ = $master_tpl;
    s/%file%/$post/g;
    s/%content%/$o_post/g;
    s/%btnnext%//g;
    s/%btnback%//g;
    print POST $_;
    close (POST);
    print "Written $outdir/$post\n";
    foreach my $tag (get_tags ($post)) {
        if ($tags{$tag}) {
            $tags{$tag} .= "," . $post;
        } else {
            $tags{$tag} = $post;
        }
    }
}

# Generating the tags pages.
foreach my $tag (keys %tags) {
    my @tags_posts = split (",", $tags{$tag});
    my $tag_file = "tag_" . $tag . ".html";
    $tag_file =~ s/ /_/g;
    $tag_file =~ s#/#_#g;
    my $tag_page = "<h2>tag: $tag</h2>\n<ul>";
    foreach my $in_post (@tags_posts) {
        $tag_page.= '<li><a href="' . $in_post . '">' . get_meta ("title", $in_post) . "</a></li>\n";
    }
    $tag_page.= "</ul>";
    open (TAG_FILE, ">$outdir/" . $tag_file) || die "`$outdir/$tag_file' cannot be opened.";
    $_ = $master_tpl;
    s/%file%/$tag_file/g;
    s/%content%/$tag_page/g;
    s/%btnnext%//g;
    s/%btnback%//g;
    print TAG_FILE $_;
    print "written $outdir/$tag_file\n";
    close (TAG_FILE);
}

# Generating the index pages.
my $iter = floor (@content / 5);
my ($content, $btnback, $btnnext, $file);
for (my $i = 0; $i < $iter; $i++) {
    my $start = $i * 5;
    my $end = $i * 5 + 4;
    my @slice = @content[$start..$end];
    $content = join ("", @slice);
    if ($i == 0) {
        $file = "index.html";
        # Creates the "next" button.
        if (@content > 5) {
            $btnback = '<a href="index_1.html">&lt;&lt; Older entries</a>';
        } else {
            $btnback = "";
        }
        $btnnext = "";
    } else {
        $file = "/index_$i.html";
        # Creates the page buttons.
        if (@content > $i + 5) {
            $btnback = '<a href="index_'. ($i + 1) .'.html">&lt;&lt; Older entries</a>';
        } else {
            $btnback = "";
        }
        
        if ($i == 1) {
            $btnnext = '<a href="index.html">Newer entries &gt;&gt;</a>';
        } else {
            $btnnext = '<a href="index_'. ($i - 1) .'.html">Newer entries &gt;&gt;</a>';
        }
    }

    open (INDEX, ">$outdir/$file") || die "Impossible to open `$outdir/$file'";
    my $page = $master_tpl;
    $page =~ s/%file%/$file/g;
    $page =~ s/%content%/$content/g;
    $page =~ s/%btnback%/$btnback/g;
    $page =~ s/%btnnext%/$btnnext/g;
    print INDEX $page;
    close (INDEX);
    print "Written $outdir/$file\n";
}
# Now the last piece...
print "Number of archive pages: $iter\n";
if ($iter == 0) {
    $content = join ("", @content);
    $file = "index.html";
    $btnnext = "";
} else {
    my $start = $iter * 5;
    my $end = ($iter * 5) + $#content % 5;
    my @slice = @content[$start..$end];
    $content = join ("", @slice);
    $file = "index_$iter.html";
    if ($iter == 1) {
        $btnnext = '<a href="index.html">Newer entries &gt;&gt;</a>';
    } else {
        $btnnext = '<a href="index_'. ($iter - 1) .'.html">Newer entries &gt;&gt;</a>';
    }
}
open (INDEX, ">$outdir/$file");
$btnback = "";
my $page = $master_tpl;
$page =~ s/%file%/$file/g;
$page =~ s/%content%/$content/g;
$page =~ s/%btnback%/$btnback/g;
$page =~ s/%btnnext%/$btnnext/g;
print INDEX $page;
close (INDEX);
print "Written $outdir/$file\n";

open (RSS, ">$outdir/feed.xml") || die "`$outdir/feed.xml' cannot be accessed.";
print RSS $rss;
close (RSS);

`cp *.css $outdir/`;
print "copied css files.\n";
`cp -r res/* $outdir/`;
print "copied resource files.";

