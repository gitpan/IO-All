#!/usr/lang/perl/5.8.2/bin/perl
use IO::All;
my $html < io('index.html');
$html =~ s/statically/dynamically/;
print $html;
