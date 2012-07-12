#!/usr/bin/perl

# - always run from the same dir as the file you're converting
# - be sure you're ok with an "images" directory in that dir
# - correct usage:
#       < input Markdown.pl | $0 image_dir [prefix] > something.html

# this program performs takes Markdown generated HTML with embedded graphviz
# OR ditaa pictures, and spits out the pictures for either of them, and
# changes the links accordingly.

# each block is a Markdown code block.  It starts with ".gv", or ".aa",
# followed by an optional size, optional "file=name", and an optional title
# string (no quotes).  The filename can be used for later reference.  (You can
# reuse an image simply by starting the same sort of .gv or .aa line but
# without giving it a body).

# The size has to start with a digit, and the rest of the non-space-word is
# passed straight to graphviz as 'size='.  Size is ignored if passed to aa;
# only gv looks it.

# for ditaa, no *other* processing is done, but for gv we do a *lot*; in fact
# that's the bulk of the code.  Documentation for that is inline; look for
# lines starting with '# GV::

use strict;
use warnings;

# GV:: color codes to be used later
my %colors = (
    b   =>  'deepskyblue',      B   =>  'blue3',
    c   =>  'cyan',             C   =>  'cyan4',
    g   =>  'green',            G   =>  'darkgreen',
    m   =>  'magenta',
    o   =>  'orange',           O   =>  'darkorange',
    r   =>  'red',              R   =>  'red3',
    w   =>  'white',
    y   =>  'yellow',
);

# the image directory, but we don't mkdir it right away; only when an image is
# actually written out
my $image_dir = shift or die "need an image directory name\n";

# the prefix for the fig filenames
my $fig_prefix = shift;
$fig_prefix ||= "fig";
# sometimes the prefix we're passed has slashes in it...
$fig_prefix =~ s(/)(_)g;

my $figno=0;
my $html;

undef $/; $html = <>;
$html =~ s(((<pre><code>)?\.(aa|gv)\s.*?((?=\.(aa|gv))|</code></pre>\n)))(fig($1))msge;

sub fig {
    my $fig = shift;
    $fig =~ s/^<pre><code>\s*//;
    $fig =~ s(</code></pre>$)();

    $figno++;

    my ($title, $size, $filename);
    # chop off the first line after taking what you need
    my ($type, $options) = ($1, $2) if $fig =~ s/^\.(gv|aa)(.*)\n*//;
    $size = $1 if $options =~ s/^ (\d\S*)(.*)/$2/;
    $filename = $1 if $options =~ s/^ file=(\S+)(.*)/$2/;
    $title = $1 if $options =~ s/ (\S.*)\s*//;

    $size ||= "8";
    $title ||= "Figure $figno"; $title =~ s/ fig0*/ /;
    $filename ||= "$fig_prefix-" . sprintf "%04d", $figno;

    my $ret .= "<img src=\"$image_dir/$filename\" title=\"$title\" />\n";

    unless ( -d $image_dir ) {
        system("mkdir -p $image_dir") and die "mkdir -p $image_dir failed\n";
    }

    $^W = 1;

    $fig =~ s/\&amp;/\&/g;
    $fig =~ s/\&lt;/</g;
    $fig =~ s/\&gt;/>/g;

    # generate the picture files and store them (there is no data to be
    # returned, please note)
    if ($type eq 'aa') {
        gen_aa_fig($filename, $fig, $size);
    } elsif ($type eq 'gv') {
        gen_gv_fig($filename, $fig, $size);
    }

    return $ret;
}

print $html;

# ------------------

sub gen_aa_fig {
    my ($figno, $fig, $size) = @_;
    return unless $fig;

    # TODO use mktemp later; this bloody thing does not use STDIN!
    open(AA, ">", "/tmp/.$ENV{USER}.ditaa.in") or die "open tmp failed: $!\n";
    print AA $fig; close AA;
    system("java -jar /usr/share/java/ditaa/ditaa-0_9.jar /tmp/.$ENV{USER}.ditaa.in $image_dir/$figno -o -E >&2") and die "ditaa failed\n";
}

sub gen_gv_fig {
    my ($figno, $fig, $size) = @_;
    return unless $fig;
    $fig = gv_expand($fig, $size);
    print STDERR $fig if exists $ENV{D};
    open(DOT, "|/usr/bin/dot -Tpng -o $image_dir/$figno") or die "$!";
        print DOT $fig and close DOT;
}

sub gv_expand {
    local $_ = shift;
    my $size = shift;

    # this contains a full gv in my mini language

    my $prefix = "digraph G {\nsize=$size\nrankdir=TB\ngraph [ labelloc = t ]\n\nnode[fontsize=12 height=0.1]\n\nbgcolor=\"deepskyblue\"";
    my $suffix = "}";

    # normalise whitespace
    s/\h+/ /g;
    s/^ //;
    s/ $//;

    # GV:: any dq string at the start of the line is a graph label.  It can be
    # multi-line -- it ends with the closing dq, wherever that is.
    if (/^"([^"]*)"$/m) {
        my $mlgl = $1;
        $mlgl =~ s/\v/\\n/g;
        s/^"([^"]*)"$/graph [ label = "$mlgl" ]/m;
    }

    # GV:: there's a lot of magic to do with edges

        # GV:: ".ie" at the start of a line gets you an invisible edge.  This
        # is used to equalise weights with some other picture where that edge
        # was visible.  Without this, dot often distracts the viewer with
        # unnecessary differences between these two pictures due to edges
        # being pulled differently.
        s/^\.ie (.*)$/$1 [ style = invis ]/mg;

        # GV:: ".le" at the start of a line indicates a "light edge" (i.e., an
        # edge whose weight is zero).  Note that this is kinda the opposite of
        # the previous one.  In the previous one, you wanted to add a weight
        # without showing an edge.  Here you want to show an edge without
        # using its weight.
        s/^\.le (.*)$/$1 [ constraint = false ]/mg;

        # GV:: ".he" at the start gets you a "heavy edge", which tends to be
        # shorter, straighter, and more vertical
        s/^\.he (.*)$/$1 [ weight = 50 ]/mg;

        # GV:: ".eq" at the start is used to give the same rank to the nodes
        # whose names follow.  This may be needed to fix up skews caused by ".le"
        s/^\.eq (.*)$/{ rank=same $1 }/mg;

        # GV:: .. becomes -> (this is *purely* for typing convenience)
        s/ \.\. / -> /g;

        # GV:: -- as the first arrow gets you a dashed edge
        s/^(\S+) -- (.*)$/$1 -> $2 [style = dashed, dir = none]/gm;

    # GV:: node attributes

        # GV:: [] at the start of a line gets you a box
        s/^\[\] (.*)$/$1 [ shape = box ]/mg;

        # GV:: <> at the start of a line gets you a diamond
        s/^\<\> (.*)$/$1 [ shape = diamond ]/mg;

        # GV:: [r] <space> nodename means fill color is red; similarly g/b
        s/^\[([A-Za-z])\] (.*)$/"$2 [style=filled, fillcolor=" . ($colors{$1} || 'pink') . "]"/gme;

        # GV:: [yr] <space> nodename means yellow on red
        s/^\[([A-Za-z])([A-Za-z])\] (.*)$/"$3 [style=filled, fillcolor=" . ($colors{$2} || 'pink') . ", fontcolor=" .  ($colors{$1} || 'blue') . "]"/gme;

        #GV:: [true] maroon color edge+label
        s/\[true\]/color="darkgreen", fontcolor="darkgreen"/mg;

        #GV:: [false] maroon color edge+label
        s/\[false\]/color="maroon", fontcolor="maroon"/mg;

    $_ = "$prefix\n$_$suffix\n";
    return $_;
}
