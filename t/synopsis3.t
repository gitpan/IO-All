use lib 't', 'lib';
use strict;
use warnings;
use Test::More;
use IO_All_Test;
use Config;

plan((eval {require IO::String; 1})
    ? (tests => 3)
    : (skip_all => "requires IO::String")
);

undef $/; 
# # Copy STDIN to STDOUT
# io('-')->print(io('-')->slurp);
open TEST, '-|', qq{perl -Ilib -MIO::All -e 'io("-")->print(io("-")->slurp)' < t/mystuff} or die "open failed: $!";
test_file_contents(<TEST>, 't/mystuff');
close TEST;

# # Copy STDIN to STDOUT a block at a time
# my $stdin = io('-');
# my $stdout = io('-');
# $stdout->buffer($stdin->buffer); 
# $stdout->write while $stdin->read;
open TEST, '-|', qq{perl -Ilib -MIO::All -e 'my \$stdin = io("-");my \$stdout = io("-");\$stdout->buffer(\$stdin->buffer);\$stdout->write while \$stdin->read' < t/mystuff} or die "open failed: $!";
test_file_contents(<TEST>, 't/mystuff');
close TEST;

# # Copy STDIN to a String File one line at a time
# my $stdin = io('-');
# my $string_out = io('$');
# while (my $line = $stdin->getline) {
#     $string_out->print($line);
# }

open TEST, '-|', qq{perl -Ilib -MIO::All -e 'my \$stdin = io("-");my \$string_out = io("\\\$");while (my \$line = \$stdin->getline("")) {\$string_out->print(\$line)} print \${\$string_out->string_ref}' < t/mystuff} or die "open failed: $!";
test_file_contents(<TEST>, 't/mystuff');
close TEST;
