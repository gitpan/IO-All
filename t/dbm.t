use lib 't', 'lib';
use strict;
use warnings;
use Test::More;
use IO::All;
use IO_All_Test;

plan(($^O eq 'MSWin32')
    ? (skip_all => "Unresolved bug for dbm on MSWin32")
    : (tests => 2)
);

IO::All->dbm('SDBM_File');
my $db = io('t/output/mydbm');
$db->{fortytwo} = 42;
$db->{foo} = 'bar';

is(join('', sort keys %$db), 'foofortytwo');
is(join('', sort values %$db), '42bar');
