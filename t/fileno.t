use lib 't', 'lib';
use strict;
use warnings;
use Test::More tests => 7;
use IO::All;
use IO_All_Test;

is(io('-')->mode('<')->open->fileno, 0);
is(io('-')->mode('>')->open->fileno, 1);
is(io('=')->fileno, 2);

is(io->stdin->fileno, 0);
is(io->stdout->fileno, 1);
is(io->stderr->fileno, 2);

ok(io('t/output/xxx')->open('>')->fileno > 2);
