use strict;
use Test::More tests => 3;
use IO::All;
use lib 't';
use IO_All_Test;

my $io1 = io(-lock => 't/output/foo');
$io1->println('line 1');

fork and do {
    my $io2 = io(-lock => 't/output/foo');
    is($io2->getline, "line 1\n");
    is($io2->getline, "line 2\n");
    is($io2->getline, "line 3\n");
    exit;
};

sleep 1;
$io1->println('line 2');
$io1->println('line 3');
$io1->unlock;

1;
