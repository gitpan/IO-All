use lib 't', 'lib';
use strict;
use warnings;
use Test::More tests => 2;
use IO::All;

ok(io->is_spiffy);
my $dull = bless {}, 'Dull';
ok(not $dull->is_spiffy);
