package IO::All;
use strict;
use warnings;
use 5.006_001;
use Spiffy qw(-base !attribute);
use Fcntl qw(:DEFAULT :flock);
use Symbol;
use File::Spec;
our $VERSION = '0.14';
our @EXPORT = qw(io);

spiffy_constructor 'io';

#===============================================================================
# Basic Setup
#===============================================================================
sub attribute;
attribute autoclose => 1;
attribute block_size => 1024;
attribute descriptor => undef;
attribute domain => undef;
attribute domain_default => 'localhost';
attribute flags => {};
attribute handle => undef;
attribute io_handle => undef;
attribute tied_file => undef;
attribute is_dir => 0;
attribute is_file => 0;
attribute is_link => 0;
attribute is_open => 0;
attribute is_socket => 0;
attribute is_string => 0;
attribute use_lock => 0;
attribute mode => undef;
attribute name => undef;
attribute perms => undef;
attribute port => undef;

sub proxy; 
proxy 'autoflush';
proxy 'eof';
proxy 'fileno';
proxy 'getc' => '<';
proxy 'seek';
proxy 'stat';
proxy 'string_ref';
proxy 'tell';
proxy 'truncate';

sub proxy_open; 
proxy_open print => '>';
proxy_open printf => '>';
proxy_open sysread => O_RDONLY;
proxy_open syswrite => O_CREAT | O_WRONLY;
proxy_open 'recv';
proxy_open 'send';

#===============================================================================
# Public class methods
#===============================================================================
sub new {
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    my ($args) = $self->parse_arguments(@_);
    tie *$self, $self if $args->{-tie};
    $self->use_lock(1) if $args->{-lock};
    $self->init(@_);
}

sub init {
    my $self = shift;
    my ($args, @values) = $self->parse_arguments(@_);
    if (defined $args->{-file_name}) {
        require IO::File;
        $self->io_handle(IO::File->new);
        $self->name($args->{-file_name});
        $self->is_file(1);
    }
    elsif (defined $args->{-dir_name}) {
        require IO::Dir;
        $self->io_handle(IO::Dir->new);
        $self->name($args->{-dir_name});
        $self->is_dir(1);
    }
    elsif (defined $args->{-socket_name}) {
        $self->name($args->{-socket_name});
        $self->is_socket(1);
    }
    elsif (defined $args->{-file_handle}) {
        $self->handle($args->{-file_handle});
        $self->is_file(1);
    }
    elsif (defined $args->{-dir_handle}) {
        $self->handle($args->{-dir_handle});
        $self->is_dir(1);
    }
    elsif (defined $args->{-socket_handle}) {
        $self->handle($args->{-socket_handle});
        $self->is_socket(1);
    }
    unless (defined $self->name or defined $self->handle) {
        if (@values) {
            my $value = shift @values;
            if (ref $value or ref(\ $value) eq 'GLOB') {
                $self->handle($value);
            }
            else {
                $self->name($value);
            }
            $self->descriptor($value);
        }
        else {
            $self->temporary_file;
        }
    }
    while (defined (my $name = $self->name)) {
        $self->is_socket(1), last if $name =~ /^[\w\-\.]*:\d{1,5}$/;
        $self->is_file(1), last if -f $name;
        $self->is_dir(1), last if -d $name;
        $self->is_link(1), last if -l $name;
        last;
    }
    return $self;
}

sub XXX {
    my $self = shift;
    require Data::Dumper;
    print Data::Dumper::Dumper(@_);
}

#===============================================================================
# Tie Interface
#===============================================================================
sub TIEHANDLE {
    return $_[0] if ref $_[0];
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->init(@_);
}

sub READLINE {
    goto &getlines if wantarray;
    goto &getline;
}

sub DESTROY {
    no warnings;
    my $self = shift;
    untie *$self if tied *$self;
}

sub BINMODE { return }

{
    no warnings;
    *GETC   = \&getc;
    *PRINT  = \&print;
    *PRINTF = \&printf;
    *READ   = \&read;
    *WRITE  = \&write;
    *SEEK   = \&seek;
    *TELL   = \&getpos;
    *EOF    = \&eof;
    *CLOSE  = \&close;
    *FILENO = \&fileno;
}

#===============================================================================
# Public instance methods
#===============================================================================
sub accept {
    my $self = shift;
    $self->assert_open_socket('-listen');
    my ($flags) = $self->parse_arguments(@_);
    my $socket; 
    while (1) {
        $socket = $self->io_handle->accept;
        last unless $flags->{-fork};
        my $pid = fork;
        $self->throw("Unable to fork for IO::All::accept")
          unless defined $pid;
        last unless $pid;
        undef $socket;
    }
    my $io = ref($self)->new(-socket_handle => $socket);
    $io->io_handle($socket);
    $io->is_open(1);
    return $io;
}

sub All {
    my $self = shift;
    $self->all('-r');
}

sub all {
    my $self = shift;
    my @args = @_;
    my ($flags) = $self->parse_arguments(@args);
    my @all;
    while (my $io = $self->next) {
        push @all, $io;
        push @all, $io->all 
          if $flags->{-r} and $io->is_dir;
    }
    return @all if $flags->{-no_sort};
    return sort {$a->name cmp $b->name} @all;
}

sub All_Dirs {
    my $self = shift;
    $self->all_dirs(-r => @_);
}

sub all_dirs {
    my $self = shift;
    grep $_->is_dir, $self->all(@_);
}

sub All_Files {
    my $self = shift;
    $self->all_files(-r => @_);
}

sub all_files {
    my $self = shift;
    grep $_->is_file, $self->all(@_);
}

sub All_Links {
    my $self = shift;
    $self->all_links(-r => @_);
}

sub all_links {
    my $self = shift;
    grep $_->is_link, $self->all(@_);
}

sub append {
    my $self = shift;
    $self->assert_open('>>');
    $self->print(@_);
}

sub appendln {
    my $self = shift;
    $self->assert_open('>>');
    $self->println(@_);
}

sub backwards {
    my $self = shift;
    *$self->{backwards} = 1;
    return $self;
}

sub buffer {
    my $self = shift;
    if (not @_) {
        *$self->{buffer} = do {my $x = ''; \ $x}
          unless exists *$self->{buffer};
        return *$self->{buffer};
    }
    my $buffer_ref = ref($_[0]) ? $_[0] : \ $_[0];
    $$buffer_ref = '' unless defined $$buffer_ref;
    return *$self->{buffer} = $buffer_ref;
}

sub clear {
    my $self = shift;
    my $buffer = *$self->{buffer};
    $$buffer = '';
}

sub close {
    my $self = shift;
    return unless $self->is_open;
    $self->is_open(0);
    $self->shutdown
      if $self->is_socket;
    my $io_handle = $self->io_handle;
    $self->unlock;
    $self->io_handle(undef);
    $io_handle->close(@_);
}

sub getline {
    my $self = shift;
    return $self->getline_backwards
      if *$self->{backwards};
    my ($args, @values) = $self->parse_arguments(@_);
    $self->assert_open('<');
    my $line;
    {
        local $/ = shift(@values) if @values;
        $line = $self->io_handle->getline;
    }
    $self->error_check;
    chomp($line) if $args->{-chomp};
    return defined $line
    ? $line
    : $self->autoclose && $self->close && undef || 
      undef;
}

sub getlines {
    my $self = shift;
    return $self->getlines_backwards
      if *$self->{backwards};
    my ($args, @values) = $self->parse_arguments(@_);
    $self->assert_open('<');
    my @lines;
    {
        local $/ = shift(@values) if @values;
        @lines = $self->io_handle->getlines;
    }
    $self->error_check;
    if ($args->{-chomp}) {
        chomp for @lines;
    }
    return (@lines) or
           $self->autoclose && $self->close && () or
           ();
}

sub length {
    my $self = shift;
    length(${$self->buffer});
}

sub next {
    my $self = shift;
    $self->assert_open_dir;
    my $name = '.'; 
    while ($name =~ /^\.{1,2}$/) {
        $name = $self->io_handle->read;
        unless (defined $name) {
            $self->close;
            return;
        }
    }
    return IO::All->new(File::Spec->catfile($self->name, $name));
}

sub open {
    my $self = shift;
    $self->throw("IO::All object already open")
      if $self->is_open;
    $self->is_open(1);
    my ($mode, $perms) = @_;
    $self->mode($mode) if defined $mode;
    $self->mode('<') unless defined $self->mode;
    $self->perms($perms) if defined $perms;
    my @args;
    unless ($self->is_dir) {
        push @args, $self->mode;
        push @args, $self->perms if defined $self->perms;
    }

    if (defined $self->name) {
        $self->open_name($self->name, @args);
    }
    elsif (defined $self->handle and
           not $self->io_handle->opened
          ) {
        # XXX Not tested
        $self->io_handle->fdopen($self->handle, @args);
    }
    return $self;
}

sub println {
    my $self = shift;
    $self->print(map {/\n\z/ ? ($_) : ($_, "\n")} @_);
}

sub read {
    my $self = shift;
    $self->assert_open('<');
    my $length = (@_ or $self->is_dir)
    ? $self->io_handle->read(@_)
    : $self->io_handle->read(
        ${$self->buffer}, 
        $self->block_size, 
        $self->length,
      );
    $self->error_check;
    return $length || $self->autoclose && $self->close && 0;
}

{
    no warnings;
    *readline = \&getline;
}

sub rmdir {
    my $self = shift;
    rmdir $self->name;
}

sub shutdown {
    my $self = shift;
    my $how = @_ ? shift : 2;
    $self->io_handle->shutdown(2);
}

sub slurp {
    my $self = shift;
    $self->assert_open_file('<');
    local $/;
    my $slurp = $self->io_handle->getline;
    $self->error_check;
    $self->autoclose && $self->close;
    return wantarray ? ($slurp =~ /(.*\n)/g) : $slurp;
}

sub temporary_file {
    my $self = shift;
    require IO::File;
    my $temp_file = IO::File::new_tmpfile()
      or $self->throw("Can't create temporary file");
    $self->io_handle($temp_file);
    $self->error_check;
    $self->autoclose(0);
    $self->is_open(1);
}

sub unlink {
    my $self = shift;
    unlink $self->name;
}

sub unlock {
    my $self = shift;
    my $io_handle = $self->io_handle;
    if ($self->use_lock) {
        flock $io_handle, LOCK_UN;
    }
}

sub write {
    my $self = shift;
    $self->assert_open_file('>');
    my $length = @_
    ? $self->io_handle->write(@_)
    : $self->io_handle->write(${$self->buffer}, $self->length);
    $self->error_check;
    $self->clear unless @_;
    return $length;
}

#===============================================================================
# Implementation methods. Subclassable.
#===============================================================================
sub throw {
    my $self = shift;
    require Carp;
    Carp::croak(@_);
}

#===============================================================================
# Private instance methods
#===============================================================================
sub assert_dirpath {
    my $self = shift;
    my $dir_name = $self->name
      or $self->throw("No directory name for IO::All object");
    return $dir_name if -d $dir_name or
      mkdir($self->name, $self->perms || 0755) or
      do {
          require File::Path;
          mkpath($dir_name);
      } or
      $self->throw("Can't make $dir_name"); 
}

sub assert_open {
    my $self = shift;
    return if $self->is_open;
    return $self->assert_open_file(@_) if $self->is_file;
    return $self->assert_open_dir(@_) if $self->is_dir;
    return $self->assert_open_socket(@_) if $self->is_socket;
    return $self->assert_open_file(@_); # XXX guess
}

sub assert_open_backwards {
    my $self = shift;
    return if $self->is_open;
    require File::ReadBackwards;
    my $file_name = $self->name;
    my $io_handle = File::ReadBackwards->new($file_name)
      or $self->throw("Can't open $file_name for backwards:\n$!");
    $self->io_handle($io_handle);
    $self->is_open(1);
}

sub assert_open_dir {
    my $self = shift;
    return if $self->is_open;
    require IO::Dir;
    $self->is_dir(1);
    $self->io_handle(IO::Dir->new)
      unless defined $self->io_handle;
    $self->open;
}

sub assert_open_file {
    my $self = shift;
    return if $self->is_open;
    $self->is_file(1);
    require IO::File;
    $self->io_handle(IO::File->new)
      unless defined $self->io_handle;
    $self->mode(shift) unless $self->mode;
    $self->open;
}

sub assert_open_socket {
    my $self = shift;
    return if $self->is_open;
    $self->is_socket(1);
    $self->is_open(1);
    require IO::Socket;
    my ($flags) = $self->parse_arguments(@_);
    $self->get_socket_domain_port;
    my @args = $flags->{-listen}
    ? (
        LocalHost => $self->domain,
        LocalPort => $self->port,
        Proto => 'tcp',
        Listen => 1,
        Reuse => 1,
    )
    : (
        PeerAddr => $self->domain,
        PeerPort => $self->port,
        Proto => 'tcp',
    );
    my $socket = IO::Socket::INET->new(@args)
      or $self->throw("Can't open socket");
    $self->io_handle($socket);
}

sub assert_tied_file {
    my $self = shift;
    return $self->tied_file || do {
        eval {require Tie::File};
        $self->throw("Tie::File required for file array operations") if $@;
        my $array_ref = do { my @array; \@array };
        tie @$array_ref, 'Tie::File', $self->name;
        $self->tied_file($array_ref);
    };
}

sub boolean_arguments {
    my $self = shift;
    (
        qw(
            -a -r 
            -lock -chomp -fork -tie
            -no_sort -listen
        ),
        $self->SUPER::boolean_arguments,
    )
}

sub error_check {
    my $self = shift;
    return unless $self->io_handle->can('error');
    return unless $self->io_handle->error;
    $self->throw($!);
}

sub copy {
    my $self = shift;
    my $copy;
    for (keys %{*$self}) {
        $copy->{$_} = *$self->{$_};
    }
    $copy->{io_handle} = 'defined'
      if defined $copy->{io_handle};
    return $copy;
}

sub get_socket_domain_port {
    my $self = shift;
    my ($domain, $port);
    ($domain, $port) = split /:/, $self->name
      if defined $self->name;
    $self->domain($domain) unless defined $self->domain;
    $self->domain($self->domain_default) unless $self->domain;
    $self->port($port) unless defined $self->port;
}

sub getline_backwards {
    my $self = shift;
    $self->assert_open_backwards;
    return $self->io_handle->readline;
}

sub getlines_backwards {
    my $self = shift;
    my @lines;
    while (defined (my $line = $self->getline_backwards)) {
        push @lines, $line;
    }
    return @lines;
}

sub lock {
    my $self = shift;
    return unless $self->use_lock;
    my $io_handle = $self->io_handle;
    my $flag = $self->mode =~ /^>>?$/
    ? LOCK_EX
    : LOCK_SH;
    flock $io_handle, $flag;
}

sub open_file {
    my $self = shift;
    require IO::File;
    my $handle = IO::File->new;
    $self->io_handle($handle);
    $handle->open(@_) 
      or $self->throw($self->open_file_msg);
    $self->lock;
}

my %mode_msg = (
    '>' => 'output',
    '<' => 'input',
    '>>' => 'append',
);
sub open_file_msg {
    my $self = shift;
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    my $direction = defined $mode_msg{$self->mode}
      ? ' for ' . $mode_msg{$self->mode}
      : '';
    return qq{Can't open file$name$direction:\n$!};
}

sub open_dir {
    my $self = shift;
    require IO::Dir;
    my $handle = IO::Dir->new;
    $self->io_handle($handle);
    $handle->open(@_)
      or $self->throw($self->open_dir_msg);
}

sub open_dir_msg {
    my $self = shift;
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    return qq{Can't open directory$name:\n$!};
}

sub open_name {
    my $self = shift;
    return $self->open_std if $self->descriptor eq '-';
    return $self->open_string if $self->descriptor eq '$';
    return $self->open_file(@_) if $self->is_file;
    return $self->open_dir(@_) if $self->is_dir;
    return if $self->is_socket;
    return $self->open_file(@_);
}

sub open_std {
    my $self = shift;
    my $fileno = $self->mode eq '>'
    ? fileno(STDOUT)
    : fileno(STDIN);
    $self->io_handle->fdopen($fileno, $self->mode);
}

sub open_string {
    my $self = shift;
    require IO::String;
    $self->io_handle(IO::String->new);
}

sub paired_arguments {
    qw( 
        -errors
        -file_name -file_handle 
        -dir_name -dir_handle 
        -socket_name -socket_handle 
    )
}

#===============================================================================
# Closure generating functions
#===============================================================================
sub attribute {
    my $package = caller;
    my ($attribute, $default) = @_;
    no strict 'refs';
    return if defined &{"${package}::$attribute"};
    *{"${package}::$attribute"} =
      sub {
          my $self = shift;
          unless (exists *$self->{$attribute}) {
              *$self->{$attribute} = 
                ref($default) eq 'ARRAY' ? [] :
                ref($default) eq 'HASH' ? {} : 
                $default;
          }
          return *$self->{$attribute} unless @_;
          *$self->{$attribute} = shift;
      };
}

sub proxy {
    my $package = caller;
    my ($proxy) = @_;
    no strict 'refs';
    return if defined &{"${package}::$proxy"};
    *{"${package}::$proxy"} =
      sub {
          my $self = shift;
          my @return = $self->io_handle->$proxy(@_);
          $self->error_check;
          wantarray ? @return : $return[0];
      };
}

sub proxy_open {
    my $package = caller;
    my ($proxy, @args) = @_;
    no strict 'refs';
    return if defined &{"${package}::$proxy"};
    *{"${package}::$proxy"} =
      sub {
          my $self = shift;
          $self->assert_open(@args);
          my @return = $self->io_handle->$proxy(@_);
          $self->error_check;
          wantarray ? @return : $return[0];
      };
}

#===============================================================================
# overloading
#===============================================================================
my $old_warn_handler = $SIG{__WARN__}; 
$SIG{__WARN__} = sub { 
    if ($_[0] !~ /^Useless use of .+ \(.+\) in void context/) {
        goto &$old_warn_handler if $old_warn_handler;
        warn(@_);
    }
};
    
use overload '""' => 'overload_stringify';
use overload '<<' => 'overload_left_bitshift';
use overload '>>' => 'overload_right_bitshift';
use overload '<' => 'overload_less_than';
use overload '>' => 'overload_greater_than';
use overload '${}' => 'overload_string_deref';
use overload '@{}' => 'overload_array_deref';
use overload '%{}' => 'overload_hash_deref';

sub overload_table {
    return {
        'file < scalar' => 'overload_print',
        'file < scalar swap' => 'overload_slurp_to',
        'file << scalar' => 'overload_append',
        'file << scalar swap' => 'overload_slurp_append',

        'file > scalar' => 'overload_slurp_to',
        'file > scalar swap' => 'overload_print',
        'file >> scalar' => 'overload_slurp_append',
        'file >> scalar swap' => 'overload_append',

        'file > file' => 'overload_copy_to',
        'file < file' => 'overload_copy_from',
        'file >> file' => 'overload_cat_to',
        'file << file' => 'overload_cat_from',

        'file ${} scalar' => 'overload_slurp_ref',
        'file @{} scalar' => 'overload_file_tie',
        'dir @{} scalar' => 'overload_dir_all',
        'dir %{} scalar' => 'overload_dir_hash',
#         'file %{} scalar' => 'overload_file_stat',
    };
}

sub overload_left_bitshift { shift->overload_handler(@_, '<<') }
sub overload_right_bitshift { shift->overload_handler(@_, '>>') }
sub overload_less_than { shift->overload_handler(@_, '<') }
sub overload_greater_than { shift->overload_handler(@_, '>') }
sub overload_string_deref { shift->overload_handler(@_, '${}') }
sub overload_array_deref { shift->overload_handler(@_, '@{}') }
sub overload_hash_deref { shift->overload_handler(@_, '%{}') }

sub overload_handler {
    my ($self) = @_;
    my $method = $self->get_overload_method(@_);
    $self->$method(@_);
}

sub get_overload_method {
    my ($x, $self, $other, $swap, $operator) = @_;
    my $arg1_type = 
      $self->is_file ? 'file' :
      $self->is_dir ? 'dir' :
      $self->is_socket ? 'socket' :
      defined $self->name ? 'file' :
      'unknown';
    my $arg2_type =
      not(ref $other) ? 'scalar' :
      not($other->isa('IO::All')) ? 'ref' :
      $other->is_file ? 'file' :
      $other->is_dir ? 'dir' :
      $other->is_socket ? 'socket' :
      defined $self->name ? 'file' :
      'unknown';
    my $key = "$arg1_type $operator $arg2_type" . ($swap ? ' swap' : '');
    my $table = $self->overload_table;
    return defined $table->{$key} 
      ? $table->{$key}
      : $self->overload_undefined($key);
}

sub overload_stringify {
    my $self = shift;
    my $name = $self->name;
    return defined($name) ? $name : overload::StrVal($self);
}

sub overload_undefined {
    my $self = shift;
    my $key = shift;
    warn "Undefined behavior for overloaded IO::All operation: '$key'";
    return 'overload_noop';
}

sub overload_noop {
    return;
}

sub overload_slurp_ref {
    my $slurp = $_[1]->slurp;
    return \$slurp;
}

sub overload_slurp_to {
    $_[2] = $_[1]->slurp;
}

sub overload_slurp_append {
    $_[2] .= $_[1]->slurp;
}

sub overload_print {
    $_[1]->print($_[2]);
}

sub overload_append {
    $_[1]->append($_[2]);
}

sub overload_file_tie {
    $_[1]->assert_tied_file;
}

sub overload_dir_all {
    [ $_[1]->all ];
}

sub overload_dir_hash {
    +{ 
        map {
            (my $name = $_->name) =~ s/.*\///;
            ($name, $_);
        } $_[1]->all 
    };
}

sub overload_copy_to {
    $_[2]->print(scalar $_[1]->slurp);
}

sub overload_copy_from {
    $_[1]->print(scalar $_[2]->slurp);
}

sub overload_cat_to {
    $_[2]->append(scalar $_[1]->slurp);
}

sub overload_cat_from {
    $_[1]->append(scalar $_[2]->slurp);
}

1;
__END__

=head1 NAME

IO::All - IO::All of it to Graham and Damian!

=head1 NOTE

If you've just read the perl.com article at
L<http://www.perl.com/pub/a/2004/03/12/ioall.html>, there have already been
major additions thanks to the great feedback I've gotten from the Perl
community. Be sure and read the latest doc. Things are changing fast.

Many of the changes have to do with operator overloading for IO::All objects,
which results in some fabulous new idioms.

=head1 SYNOPSIS

    use IO::All;

    my $my_stuff = io('./mystuff')->slurp;  # Read a file
    my $more_stuff < io('./morestuff');     # Read another file

    io('./allstuff')->print($my_stuff, $more_stuff);  # Write to new file

or like this:

    io('./mystuff') > io('./allstuff');
    io('./morestuff') >> io('./allstuff');

or:

    my $stuff < io('./mystuff');
    io('./morestuff') >> $stuff;
    io(./allstuff') << $stuff;

or:

    ${io('./stuff')} . ${io('./morestuff')} > io('./allstuff');

=head1 SYNOPSIS II

    use IO::All;

    # Print name and first line of all files in a directory
    my $dir = io('./mydir'); 
    while (my $io = $dir->read) {
        print $io->name, ' - ', $io->getline
          if $io->is_file;
    }

    # Print name of all files recursively
    print "$_\n" for io('./mydir')->All_Files;

=head1 SYNOPSIS III

    use IO::All;
    
    # Various ways to copy STDIN to STDOUT
    io('-') > io('-');
    
    io('-') < io('-');
    
    io('-')->print(io('-')->slurp);
    
    my $stdin = io('-');
    my $stdout = io('-');
    $stdout->buffer($stdin->buffer);
    $stdout->write while $stdin->read;
    
    # Copy STDIN to a String File one line at a time
    my $stdin = io('-');
    my $string_out = io('$');
    while (my $line = $stdin->getline) {
        $string_out->print($line);
    }

=head1 SYNOPSIS IV

    use IO::All;
    
    # A forking socket server that writes to a log
    my $server = io('server.com:9999');
    my $socket = $server->accept('-fork');
    while (my $msg = $socket->getline) {
        io('./mylog')->appendln(localtime() . ' - $msg');
    }
    $socket->close;

=head1 SYNOPSIS V

    use IO::All;

    # Write some data to a temporary file and retrieve all the paragraphs.
    my $temp = io;
    $temp->print($data);
    $temp->seek(0, 0);
    my @paragraphs = $temp->getlines('');

=head1 DESCRIPTION

"Graham Barr for doing it all. Damian Conway for doing it all different."

IO::All combines all of the best Perl IO modules into a single Spiffy
object oriented interface to greatly simplify your everyday Perl IO
idioms. It exports a single function called C<io>, which returns a new
IO::All object. And that object can do it all!

The IO::All object is a proxy for IO::File, IO::Dir, IO::Socket,
IO::String, Tie::File and File::ReadBackwards. You can use most of the
methods found in these classes and in IO::Handle (which they all inherit
from). IO::All is easily subclassable. You can override any methods and
also add new methods of your own.

Optionally, every IO::All object can be tied to itself. This means that
you can use most perl IO builtins on it: readline, <>, getc, print,
printf, syswrite, sysread, close. (Due to an unfortunate bug in Perl
5.8.0 only, this option is turned off by default. See below.)

The distinguishing magic of IO::All is that it will automatically
open (and close) files, directories, sockets and io-strings for you.
You never need to specify the mode ('<', '>>', etc), since it is
determined by the usage context. That means you can replace this:

    open STUFF, '<', './mystuff'
      or die "Can't open './mystuff' for input:\n$!";
    local $/;
    my $stuff = <STUFF>;
    close STUFF;

with this:

    my $stuff < io('./mystuff');

And that is a B<good thing>!

=head1 USAGE

The use statement for IO::All can be passed several options:

    use IO::All (-tie => 
                 -lock => 1,
                );

All options begin with a '-' and come in two flavors: boolean options
and key/value pair options. Boolean options can be followed by a C<0>
or a C<1>, or can stand alone; in which case they have an assumed
value of C<1>. You can specify all options in any order without
confusing IO::All.

These options are simply defaults that are passed on to every C<io> function
within the program.

=head2 Options

=over 4

=item * -tie

Boolean. This option says that all objects created by the C<io> function
should be tied to themselves.

    use IO::All qw(-tie);
    my $io = io('file1');
    my @lines = <$io>;
    $io->close;

As you can see, you can use both method calls and builtin functions on
the same object.

NOTE: If you use the C<-tie> option with Perl 5.8.0, you need may need
to call the close function explicitly. Due to a bug, these objects will
not go out of scope properly, thus the files opened for output will not
be closed. This is not a problem in Perl 5.6.1 or 5.8.1 and greater.

=item * -lock

Boolean. This option tells the object to flock the filehandle after open.

=back

=head1 COOKBOOK

This section describes some various things that you can easily cook up
with IO::All.

=head2 Operator Overloading

IO::All objects stringify to their file or directory name. This command is a
long way of doing C<ls -1>:

    perl -MIO::All -le 'print for io(".")->all'

'>' and '<' move data between strings and files:

    $content < io('file1');
    $content > io('file2');
    io('file2') > $content2;
    io('file3') < $content2;
    io('file3') > io('file4');
    io('file5') < io('file4');

'>>' and '<<' do the same thing except the recipent string or file is
appended to.

An IO::All file used as an array reference becomes tied using Tie::File:

    $file = io('file');
    # Print last line of file
    print $file->[-1];
    # Insert new line in middle of file
    $file->[$#{$file} / 2] = 'New line';

IO::All directories used as hashes have file names as keys, and IO::All
objects as values:

    print io('dir')->{'foo.txt'}->slurp;

Files used as scalar references get slurped:

        print ${io('dir')->{'foo.txt'}};

=head2 File Locking

IO::All makes it very easy to lock files. Just use the C<-lock> flag. Here's a
standalone program that demonstrates locking for both write and read:

    use IO::All;
    my $io1 = io(-lock => 'myfile');
    $io1->println('line 1');

    fork or do {
        my $io2 = io(-lock => 'myfile');
        print $io2->slurp;
        exit;
    };

    sleep 1;
    $io1->println('line 2');
    $io1->println('line 3');
    $io1->unlock;

There are a lot of subtle things going on here. An exclusive lock is
issued for C<$io1> on the first C<println>. That's because the file
isn't actually opened until the first IO operation.

When the child process tries to read the file using C<$io2>, there is
a shared lock put on it. Since C<$io1> has the exclusive lock, the
slurp blocks.

The parent process sleeps just to make sure the child process gets a
chance. The parent needs to call C<unlock> or C<close> to release the
lock. If all goes well the child will print 3 lines.

=head2 Round Robin

This simple example will read lines from a file forever. When the last
line is read, it will reopen the file and read the first one again.

    my $io = io('file1.txt');
    $io->autoclose(1);
    while (my $line = $io->getline || $io->getline) {
        print $line;
    }

=head2 Reading Backwards

If you call the C<backwards()> method on an IO::All object, the
C<getline()> and C<getlines()> will work in reverse. They will read the
lines in the file from the end to the beginning.

    my @reversed;
    my $io = io('file1.txt');
    $io->backwards;
    while (my $line = $io->getline) {
        push @reversed, $line;
    }

or more simply:

    my @reversed = io('file1.txt')->backwards->getlines;

The C<backwards()> method returns the IO::All object so that you can
chain the calls.

NOTE: This operation requires that you have the File::ReadBackwards 
module installed.
    
=head2 Client/Server Sockets

IO::All makes it really easy to write a forking socket server and a
client to talk to it.

In this example, a server will return 3 lines of text, to every client
that calls it. Here is the server code:

    use IO::All;

    my $socket = io(':12345')->accept('-fork');
    $socket->print($_) while <DATA>;
    $socket->close;

    __DATA__
    On your mark,
    Get set,
    Go!

Here is the client code:

    use IO::All;

    my $io = io('localhost:12345');
    print while $_ = $io->getline;

You can run the server once, and then run the client repeatedly (in
another terminal window). It should print the 3 data lines each time.

Note that it is important to close the socket if the server is forking,
or else the socket won't go out of scope and close.

=head2 File Subclassing

Subclassing is easy with IO::All. Just create a new module and use
IO::All as the base class. Since IO::All is a Spiffy module, you do it
like this:

    package NewModule;
    use IO::All '-base';

You need to do it this way so that IO::All will export the C<io> function.
Here is a simple recipe for subclassing:

IO::Dumper inherits everything from IO::All and adds an extra method
called C<dump()>, which will dump a data structure to the file we
specify in the C<io> function. Since it needs Data::Dumper to do the
dumping, we override the C<open> method to C<require Data::Dumper> and
then pass control to the real C<open>.

First the code using the module:

    use IO::Dumper;
    
    io('./mydump')->dump($hash);

And next the IO::Dumper module itself:

    package IO::Dumper;
    use IO::All '-base';
    use Data::Dumper;
    
    sub dump {
        my $self = shift;
        $self->print(Data::Dumper::Dumper(@_));
        return $self;
    }
    
    1;

=head2 Inline Subclassing

This recipe does the same thing as the previous one, but without needing
to write a separate module. The only real difference is the first line.
Since you don't "use" IO::Dumper, you need to still call its C<import>
method manually.

    IO::Dumper->import;
    io('./mydump')->dump($hash);
    
    package IO::Dumper;
    use IO::All '-base';
    use Data::Dumper;
    
    sub dump {
        my $self = shift;
        $self->print(Data::Dumper::Dumper(@_));
        return $self;
    }
    
=head1 OPERATION NOTES

=over 4

=item *

IO::All will automatically be opened when the first read or write
happens. Mode is determined heuristically unless specified explicitly.

=item *

For input, IO::All objects will automatically be closed after EOF (or
EOD). For output, the object closes when it goes out of scope.

To keep input objects from closing at EOF, do this:

    $io->autoclose(0);

=item * 

You can always call C<open> and C<close> explicitly, if you need that
level of control.

=back

=head1 CONSTRUCTOR

NOTE: The C<io> function takes all the same parameters as C<new>.

=over 4

=item * new()

    new(file_descriptor,
        '-',
        '$',
        -file_name => $file_name,
        -file_handle => $file_handle,
        -dir_name => $directory_name,
        -dir_handle => $directory_handle,
       );
            
File descriptor is a file/directory name or file/directory handle or
anything else that can be used in IO operations. 

IO::All will use STDIN or STDOUT (depending on context) if file
descriptor is '-'. It will use an IO::String object if file
descriptor is '$'.

If file_descriptor is missing and neither C<-file_handle> nor
C<-dir_handle> is specified, IO::All will create a temporary file
which will be opened for both input and output.

C<-tie> uses the tie interface for a single object.

=back

=head1 INSTANCE METHODS

IO::All provides lots of methods for making your daily programming tasks
simpler. If you can't find what you need, just subclass IO::All and
add your own.

=over 4

=item * accept()

For sockets. Opens a server socket (LISTEN => 1, REUSE => 1). Returns an
IO::All socket object that you are listening on.

If the '-fork' option is specified, the process will automatically be forked
for every connection.

=item * all()

Return a list of IO::All objects for all files and subdirectories in a
directory. 

'.' and '..' are excluded.

The C<-r> flag can be used to get all files and subdirectories recursively.

The items returned are sorted by name unless the C<-no_sort> flag is used.

=item * All()

Same as C<all('-r')>.

=item * all_dirs()

Same as C<all()>, but only return directories.

=item * All_Dirs()

Same as C<all_dirs('-r')>.

=item * all_files()

Same as C<all()>, but only return files.

=item * All_Files()

Same as C<all_files('-r')>.

=item * all_links()

Same as C<all()>, but only return links.

=item * All_Links()

Same as C<all_links('-r')>.

=item * append()

Same as print, but sets the file mode to '>>'.

=item * appendf()

Same as printf, but sets the file mode to '>>'.

=item * appendln()

Same as println, but sets the file mode to '>>'.

=item * autoclose()

By default, IO::All will close an object opened for input when EOF is
reached. By closing the handle early, one can immediately do other
operations on the object without first having to close it.

If you don't want this behaviour, say so like this:

    $io->autoclose(0);

The object will then be closed when C<$io> goes out of scope, or you
manually call C<<$io->close>>.

=item * autoflush()

Proxy for IO::Handle::autoflush()

=item * backwards()

Sets the object to 'backwards' mode. All subsequent C<getline>
operations will read backwards from the end of the file.

Requires Uri Guttman's File::ReadBackwards CPAN module.

=item * block_size()

The default length to be used for C<read()> and C<sysread()> calls.
Defaults to 1024.

=item * buffer()

Returns a reference to the internal buffer, which is a scalar. You can
use this method to set the buffer to a scalar of your choice. (You can
just pass in the scalar, rather than a reference to it.)

This is the buffer that C<read()> and C<write()> will use by default.

You can easily have IO::All objects use the same buffer:

    my $input = io('abc');
    my $output = io('xyz');
    my $buffer;
    $output->buffer($input->buffer($buffer));
    $output->write while $input->read;

=item * clear()

Clear the internal buffer. This method is called by write() after it writes
the buffer.

=item * close()

Proxy for IO::Handle::close()

=item * domain()

Set the domain name or ip address that a socket should use.

=item * domain_default()

The domain to use for a socket if none is specified. Defaults to
'localhost'.

=item * eof()

Proxy for IO::Handle::eof()

=item * fileno()

Proxy for IO::Handle::fileno()

=item * getc()

Proxy for IO::Handle::getc()

=item * getline()

Calls IO::File::getline(). You can pass in an optional record separator.

=item * getlines()

Calls IO::File::getlines(). You can pass in an optional record separator.

=item * hash()

This method will return a reference to a tied hash representing the
directory. This allows you to treat a directory like a hash, where the
keys are the file names, and the values call lstat, and deleting a key
deletes the file.

See IO::Dir for more information on Tied Directories.

=item * io_handle()

Direct access to the actual IO::Handle object being used.

=item * is_dir()

Returns boolean telling whether or not the IO::All object represents
a directory.

=item * is_file()

Returns boolean telling whether or not the IO::All object
represents a file.

=item * is_link()

Returns boolean telling whether or not the IO::All object represents
a symlink.

=item * is_open()

Find out it the IO::All is currently open for input/output.

=item * is_socket()

Returns boolean telling whether or not the IO::All object represents
a socket.

=item * is_string()

Returns boolean telling whether or not the IO::All object represents
an IO::String object.

=item * length()

Return the length of the internal buffer.

=item * mode()

Set the mode for which the file should be opened. Examples:

    $io->mode('>>');
    $io->mode(O_RDONLY);

=item * name()

Return the name of the file or directory represented by the IO::All
object.

=item * next()

For a directory, this will return a new IO::All object for each file
or subdirectory in the directory. Return undef on EOD.

=item * open()

Open the IO::All object. Takes two optional arguments C<mode> and
C<perms>, which can also be set ahead of time using the C<mode()> and
C<perms()> methods.

NOTE: Normally you won't need to call open (or mode/perms), since this
happens automatically for most operations.

=item * perms()

Sets the permissions to be used if the file/directory needs to be created.

=item * port()

Set the port number that a socket should use.

=item * print()

Proxy for IO::Handle::print()

=item * printf()

Proxy for IO::Handle::printf()

=item * println()

Same as print(), but adds newline to each argument unless it already
ends with one.

=item * read()

This method varies depending on its context. Read carefully (no pun
intended).

For a file, this will proxy IO::File::read(). This means you must pass
it a buffer, a length to read, and optionally a buffer offset for where
to put the data that is read. The function returns the length actually
read (which is zero at EOF).

If you don't pass any arguments for a file, IO::All will use its own
internal buffer, a default length, and the offset will always point at
the end of the buffer. The buffer can be accessed with the C<buffer()>
method. The length can be set with the C<block_size> method. The default
length is 1024 bytes. The C<clear()> method can be called to clear
the buffer.

For a directory, this will proxy IO::Dir::read().

=item * readline()

Same as C<getline()>.

=item * recv()

Proxy for IO::Socket::recv()

=item * rewind()

Proxy for IO::Dir::rewind()

=item * rmdir()

Delete the directory represented by the IO::All object.

=item * seek()

Proxy for IO::Handle::seek()

=item * send()

Proxy for IO::Socket::send()

=item * shutdown()

Proxy for IO::Socket::shutdown()

=item * slurp()

Read all file content in one operation. Returns the file content
as a string. In list context returns every line in the file.

=item * stat()

Proxy for IO::Handle::stat()

=item * string_ref()

Proxy for IO::String::string_ref()

Returns a reference to the internal string that is acting like a file.

=item * sysread()

Proxy for IO::Handle::sysread()

=item * syswrite()

Proxy for IO::Handle::syswrite()

=item * tell()

Proxy for IO::Handle::tell()

=item * throw()

This is an internal method that gets called whenever there is an error.
It could be useful to override it in a subclass, to provide more control
in error handling.

=item * truncate()

Proxy for IO::Handle::truncate()

=item * unlink

Unlink (delete) the file represented by the IO::All object.

NOTE: You can unlink a file after it is open, and continue using it
until it is closed.

=item * unlock

Release a lock from an object that used the C<-lock> flag.

=item * write

Opposite of C<read()> for file operations only.

NOTE: When used with the automatic internal buffer, C<write()> will
clear the buffer after writing it.

=back

=head1 STABILITY

The goal of the IO::All project is to continually refine the module
to be as simple and consistent to use as possible. Therefore, in the
early stages of the project, I will not hesitate to break backwards
compatibility with other versions of IO::All if I can find an easier
and clearer way to do a particular thing.

This is the first revision of this module. IO is tricky stuff. There is
definitely more work to be done. On the other hand, this module relies
heavily on very stable existing IO modules; so it may work fairly well.

I am sure you will find many unexpected "features". Please send all
problems, ideas and suggestions to INGY@cpan.org.

=head2 Known Bugs and Deficiencies

Not all possible combinations of objects and methods have been tested. There
are many many combinations. All of the examples have been tested. If you find
a bug with a particular combination of calls, let me know.

If you call a method that does not make sense for a particular object,
the result probably won't make sense. No attempt is made to check for
improper usage.

Support for format_write and other format stuff is not supported yet.

=head1 SEE ALSO

IO::Handle, IO::File, IO::Dir, IO::Socket, IO::String, IO::ReadBackwards

Also check out the Spiffy module if you are interested in extending this
module.

=head1 AUTHOR

Brian Ingerson <INGY@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
