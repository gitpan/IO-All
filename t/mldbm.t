use lib 't', 'lib';
use strict;
use warnings;
use Test::More;
use IO::All;
use IO_All_Test;

plan((eval {require MLDBM; 1})
    ? (tests => 3)
    : (skip_all => "requires MLDBM")
);

my $io = io('t/output/mldbm')->mldbm;
$io->{test} = { qw( foo foolsgold bar bargain baz bazzarro ) };
$io->{test2} = \%ENV;
$io->close;

my $io2 = io('t/output/mldbm')->mldbm;
is(scalar(@{[%$io2]}), 4);
is(scalar(@{[%{$io2->{test}}]}), 6);
is($io2->{test}{bar}, 'bargain');
