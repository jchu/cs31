#!/usr/bin/perl


my $content;
{
    local $/;
    $content = <>;
}

print post_process($content);

sub post_process {
    my $content = shift;

    $content = transform_code_sections($content);

    return $content;
}

sub transform_code_sections {
    my $content = shift;

    $content =~ s{<pre><code>}{<pre class="brush: cpp; smart-tabs: true; toolbar: false">}g;
    $content =~ s{</code></pre>}{</pre>}g;

    return $content;
}
