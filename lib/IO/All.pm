package IO::All;
use strict;
use warnings;
use 5.006_001;
our $VERSION = '0.18';
use Spiffy 0.16 '-Base', qw(!field);
use Fcntl qw(:DEFAULT :flock);
use Symbol;
use File::Spec;
our @EXPORT = qw(io);

spiffy_constructor 'io';

#===============================================================================
# Basic Setup
#===============================================================================
my $dbm_list;

sub field;
field autoclose => 1;
field block_size => 1024;
field descriptor => undef;
field domain => undef;
field domain_default => 'localhost';
field flags => {};
field handle => undef;
field io_handle => undef;
field is_open => 0;
field mode => undef;
field name => undef;
field perms => undef;
field port => undef;
field separator => $/;
field tied_file => undef;
field type => undef;
field use_lock => 0;
field dbm_list => undef;

sub proxy; 
proxy 'autoflush';
proxy 'eof';
proxy 'fileno';
proxy 'stat';
proxy 'string_ref';
proxy 'tell';
proxy 'truncate';

sub proxy_open; 
proxy_open print => '>';
proxy_open printf => '>';
proxy_open sysread => O_RDONLY;
proxy_open syswrite => O_CREAT | O_WRONLY;
proxy_open seek => '+<';
proxy_open 'getc';
proxy_open 'recv';
proxy_open 'send';

#===============================================================================
# Public class methods
#===============================================================================
sub new() {
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    my ($args) = $self->parse_arguments(@_);
    tie *$self, $self if $args->{-tie};
    $self->use_lock(1) if $args->{-lock};
    $self->init(@_);
}

sub init {
    my ($args, @values) = $self->parse_arguments(@_);
    if (defined $args->{-file_name}) {
        require IO::File;
        $self->io_handle(IO::File->new);
        $self->name($args->{-file_name});
        $self->type('file');
    }
    elsif (defined $args->{-dir_name}) {
        require IO::Dir;
        $self->io_handle(IO::Dir->new);
        $self->name($args->{-dir_name});
        $self->type('dir');
    }
    elsif (defined $args->{-socket_name}) {
        $self->name($args->{-socket_name});
        $self->type('socket');
    }
    elsif (defined $args->{-file_handle}) {
        $self->handle($args->{-file_handle});
        $self->type('file');
    }
    elsif (defined $args->{-dir_handle}) {
        $self->handle($args->{-dir_handle});
        $self->type('dir');
    }
    elsif (defined $args->{-socket_handle}) {
        $self->handle($args->{-socket_handle});
        $self->type('socket');
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
    if (defined (my $name = $self->name)) {
        my $type = 
          $name =~ /(^\|.+|.+\|)$/ ? 'pipe' :
          $name =~ /^[\w\-\.]*:\d{1,5}$/ ? 'socket' :
          -f $name ? 'file' :
          -d $name ? 'dir' :
          -l $name ? 'link' :
          undef;
        $self->type($type);
    }
    return $self;
}

sub dbm {
    if (not ref($self)) {
        $dbm_list = [ @_ ];
        return $self;
    }
    $self->dbm_list([ @_ ]);
    return $self;
}

#===============================================================================
# Tie Interface
#===============================================================================
sub TIEHANDLE() {
    return $_[0] if ref $_[0];
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->init(@_);
}

sub READLINE() {
    goto &getlines if wantarray;
    goto &getline;
}

sub DESTROY {
    no warnings;
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
        close $socket;
        undef $socket;
    }
    my $io = ref($self)->new(-socket_handle => $socket);
    $io->io_handle($socket);
    $io->is_open(1);
    return $io;
}

sub All {
    $self->all('-r');
}

sub all {
    my @args = @_;
    my ($flags) = $self->parse_arguments(@args);
    my @all;
    while (my $io = $self->next) {
        push @all, $io;
        push @all, $io->all('-r')
          if $flags->{-r} and $io->type eq 'dir';
    }
    return @all if $flags->{-no_sort};
    return sort {$a->name cmp $b->name} @all;
}

sub All_Dirs {
    $self->all_dirs(-r => @_);
}

sub all_dirs {
    grep {$_->type eq 'dir'} $self->all(@_);
}

sub All_Files {
    $self->all_files(-r => @_);
}

sub all_files {
    grep {$_->type eq 'file'} $self->all(@_);
}

sub All_Links {
    $self->all_links(-r => @_);
}

sub all_links {
    grep {$_->type eq 'link'} $self->all(@_);
}

sub append {
    $self->assert_open('>>');
    $self->print(@_);
}

sub appendln {
    $self->assert_open('>>');
    $self->println(@_);
}

sub backwards {
    *$self->{backwards} = 1;
    return $self;
}

sub buffer {
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
    my $buffer = *$self->{buffer};
    $$buffer = '';
}

sub close {
    return unless $self->is_open;
    $self->is_open(0);
    $self->shutdown
      if $self->is_socket;
    my $io_handle = $self->io_handle;
    $self->unlock;
    $self->io_handle(undef);
    $self->mode(undef);
    $io_handle->close(@_);
}

sub device    { my $x = (stat($self->io_handle || $self->name))[0] }
sub inode     { my $x = (stat($self->io_handle || $self->name))[1] }
sub modes     { my $x = (stat($self->io_handle || $self->name))[2] }
sub nlink     { my $x = (stat($self->io_handle || $self->name))[3] }
sub uid       { my $x = (stat($self->io_handle || $self->name))[4] }
sub gid       { my $x = (stat($self->io_handle || $self->name))[5] }
sub device_id { my $x = (stat($self->io_handle || $self->name))[6] }
sub size      { my $x = (stat($self->io_handle || $self->name))[7] }
sub atime     { my $x = (stat($self->io_handle || $self->name))[8] }
sub mtime     { my $x = (stat($self->io_handle || $self->name))[9] }
sub ctime     { my $x = (stat($self->io_handle || $self->name))[10] }
sub blksize   { my $x = (stat($self->io_handle || $self->name))[11] }
sub blocks    { my $x = (stat($self->io_handle || $self->name))[12] }

sub getline {
    return $self->getline_backwards
      if *$self->{backwards};
    my ($args, @values) = $self->parse_arguments(@_);
    $self->assert_open('<');
    my $line;
    {
        local $/ = @values ? shift(@values) : $self->separator;
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
    return $self->getlines_backwards
      if *$self->{backwards};
    my ($args, @values) = $self->parse_arguments(@_);
    $self->assert_open('<');
    my @lines;
    {
        local $/ = @values ? shift(@values) : $self->separator;
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

sub is_dir {
    ($self->type || '') eq 'dir';
}

sub is_file {
    ($self->type || '') eq 'file';
}

sub is_link {
    ($self->type || '') eq 'link';
}

sub is_socket {
    ($self->type || '') eq 'socket';
}

sub is_string {
    ($self->type || '') eq 'string';
}

sub length {
    length(${$self->buffer});
}

sub next {
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
    return $self if $self->is_open;
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
    $self->print(map {/\n\z/ ? ($_) : ($_, "\n")} @_);
}

sub read {
    $self->assert_open('<');
    my $length = (@_ or $self->type eq 'dir')
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
    rmdir $self->name;
}

sub scalar {
    $self->assert_open('<');
    local $/;
    my $scalar = $self->io_handle->getline;
    $self->error_check;
    $self->autoclose && $self->close;
    return $scalar;
}

sub shutdown {
    my $how = @_ ? shift : 2;
    $self->io_handle->shutdown(2);
}

sub slurp {
    my $slurp = $self->scalar;
    return $slurp unless wantarray;
    my $separator = $self->separator;
    split /(?<=\Q$separator\E)/, $slurp;
}

sub temporary_file {
    require IO::File;
    my $temp_file = IO::File::new_tmpfile()
      or $self->throw("Can't create temporary file");
    $self->io_handle($temp_file);
    $self->error_check;
    $self->autoclose(0);
    $self->is_open(1);
}

sub unlink {
    unlink $self->name;
}

sub unlock {
    my $io_handle = $self->io_handle;
    if ($self->use_lock) {
        flock $io_handle, LOCK_UN;
    }
}

sub write {
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
    require Carp;
    Carp::croak(@_);
#     Carp::confess(@_);
}

#===============================================================================
# Private instance methods
#===============================================================================
sub assert_dirpath {
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
    return if $self->is_open;
    my $type = $self->type || '';
    return $self->assert_open_file(@_) unless $type; 
    my $method = "assert_open_$type";
    return $self->$method(@_);
}

sub assert_open_backwards {
    return if $self->is_open;
    require File::ReadBackwards;
    my $file_name = $self->name;
    my $io_handle = File::ReadBackwards->new($file_name)
      or $self->throw("Can't open $file_name for backwards:\n$!");
    $self->io_handle($io_handle);
    $self->is_open(1);
}

sub assert_open_dbm {
    my $tied_file = $self->tied_file;
    return $tied_file if $tied_file;
    my $list = $self->dbm_list || $dbm_list || [];
    my @list = @$list ? @$list :
      (qw(DB_File GDBM_File NDBM_File ODBM_File SDBM_File));
    my $class;
    for my $module (@list) {
        if (defined $INC{"$module.pm"} or eval "require $module; 1") {
            $class = $module;
            last;
        }
    }
    $self->throw("No module available for IO::All DBM operation")
      unless defined $class;
    my $hash;
    my $filename = $self->name;
    tie %$hash, $class, $filename, O_RDWR|O_CREAT, 0666
      or $self->throw("Can't open '$filename' as DBM file:\n$!");
    $self->tied_file($hash);
}

sub assert_open_dir {
    return if $self->is_open;
    require IO::Dir;
    $self->type('dir');
    $self->io_handle(IO::Dir->new)
      unless defined $self->io_handle;
    $self->open;
}

sub assert_open_file {
    return if $self->is_open;
    $self->type('file');
    require IO::File;
    $self->io_handle(IO::File->new)
      unless defined $self->io_handle;
    $self->mode(shift) unless $self->mode;
    $self->open;
}

sub assert_open_pipe {
    return if $self->is_open;
    require IO::Handle;
    $self->io_handle(IO::Handle->new)
      unless defined $self->io_handle;
    my $command = $self->name;
    $command =~ s/(^\||\|$)//;
    my $mode = shift;
    my $pipe_mode = 
      $mode eq '>' ? '|-' :
      $mode eq '<' ? '-|' :
      $self->throw("Invalid usage mode '$mode' for pipe");
    CORE::open($self->io_handle, $pipe_mode, $command);
}

sub assert_open_socket {
    return if $self->is_open;
    $self->type('socket');
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
    return $self->tied_file || do {
        eval {require Tie::File};
        $self->throw("Tie::File required for file array operations") if $@;
        my $array_ref = do { my @array; \@array };
        tie @$array_ref, 'Tie::File', $self->name;
        $self->tied_file($array_ref);
    };
}

sub boolean_arguments {
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
    return unless $self->io_handle->can('error');
    return unless $self->io_handle->error;
    $self->throw($!);
}

sub copy {
    my $copy;
    for (keys %{*$self}) {
        $copy->{$_} = *$self->{$_};
    }
    $copy->{io_handle} = 'defined'
      if defined $copy->{io_handle};
    return $copy;
}

sub get_socket_domain_port {
    my ($domain, $port);
    ($domain, $port) = split /:/, $self->name
      if defined $self->name;
    $self->domain($domain) unless defined $self->domain;
    $self->domain($self->domain_default) unless $self->domain;
    $self->port($port) unless defined $self->port;
}

sub getline_backwards {
    $self->assert_open_backwards;
    return $self->io_handle->readline;
}

sub getlines_backwards {
    my @lines;
    while (defined (my $line = $self->getline_backwards)) {
        push @lines, $line;
    }
    return @lines;
}

sub lock {
    return unless $self->use_lock;
    my $io_handle = $self->io_handle;
    my $flag = $self->mode =~ /^>>?$/
    ? LOCK_EX
    : LOCK_SH;
    flock $io_handle, $flag;
}

sub open_file {
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
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    my $direction = defined $mode_msg{$self->mode}
      ? ' for ' . $mode_msg{$self->mode}
      : '';
    return qq{Can't open file$name$direction:\n$!};
}

sub open_dir {
    require IO::Dir;
    my $handle = IO::Dir->new;
    $self->io_handle($handle);
    $handle->open(@_)
      or $self->throw($self->open_dir_msg);
}

sub open_dir_msg {
    my $name = defined $self->name
      ? " '" . $self->name . "'"
      : '';
    return qq{Can't open directory$name:\n$!};
}

sub open_name {
    return $self->open_std if $self->descriptor eq '-';
    return $self->open_stderr if $self->descriptor eq '=';
    return $self->open_string if $self->descriptor eq '$';
    return $self->open_file(@_) unless defined $self->type;
    return $self->open_file(@_) if $self->type eq 'file';
    return $self->open_dir(@_) if $self->type eq 'dir';
    return if $self->type eq 'socket';
    return $self->open_file(@_);
}

sub open_std {
    my $fileno = $self->mode eq '>'
    ? fileno(STDOUT)
    : fileno(STDIN);
    $self->io_handle->fdopen($fileno, $self->mode);
}

sub open_stderr {
    $self->io_handle->fdopen(fileno(STDERR), '>');
}

sub open_string {
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
sub field() {
    my $package = caller;
    my ($field, $default) = @_;
    no strict 'refs';
    return if defined &{"${package}::$field"};
    *{"${package}::$field"} =
      sub {
          my $self = shift;
          unless (exists *$self->{$field}) {
              *$self->{$field} = 
                ref($default) eq 'ARRAY' ? [] :
                ref($default) eq 'HASH' ? {} : 
                $default;
          }
          return *$self->{$field} unless @_;
          *$self->{$field} = shift;
      };
}

sub proxy() {
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

sub proxy_open() {
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
use overload '|' => 'overload_bitwise_or';
use overload '<<' => 'overload_left_bitshift';
use overload '>>' => 'overload_right_bitshift';
use overload '<' => 'overload_less_than';
use overload '>' => 'overload_greater_than';
use overload '${}' => 'overload_string_deref';
use overload '@{}' => 'overload_array_deref';
use overload '%{}' => 'overload_hash_deref';
use overload '&{}' => 'overload_code_deref';

sub overload_bitwise_or { $self->overload_handler(@_, '|') }
sub overload_left_bitshift { $self->overload_handler(@_, '<<') }
sub overload_right_bitshift { $self->overload_handler(@_, '>>') }
sub overload_less_than { $self->overload_handler(@_, '<') }
sub overload_greater_than { $self->overload_handler(@_, '>') }
sub overload_string_deref { $self->overload_handler(@_, '${}') }
sub overload_array_deref { $self->overload_handler(@_, '@{}') }
sub overload_hash_deref { $self->overload_handler(@_, '%{}') }
sub overload_code_deref { $self->overload_handler(@_, '&{}') }

sub overload_table {
    *$self->{overload_table} ||= {
        'file < scalar' => 'overload_scalar_to_file',
        'file > scalar' => 'overload_file_to_scalar',

        'file << scalar' => 'overload_scalar_addto_file',
        'file >> scalar' => 'overload_file_addto_scalar',

        'file > file' => 'overload_file_to_file',
        'file < file' => 'overload_file_from_file',
        'file >> file' => 'overload_file_addto_file',
        'file << file' => 'overload_file_addfrom_file',

        '${} file' => 'overload_file_as_scalar',
        '@{} file' => 'overload_file_as_array',
        '@{} dir' => 'overload_dir_as_array',
        '%{} file' => 'overload_file_as_dbm',
        '%{} dir' => 'overload_dir_as_hash',
        
        'file | scalar' => 'overload_pipe_to',
        'file | scalar swap' => 'overload_pipe_from',
        
        'socket < file' => 'overload_file_to_socket',
        'file > socket' => 'overload_file_to_socket',
        '&{} socket' => 'overload_socket_as_code',
    };
}

sub overload_handler() {
    my ($self) = @_;
    my $method = $self->get_overload_method(@_);
    $self->$method(@_);
}

my $op_swap = {
    '>' => '<', '>>' => '<<',
    '<' => '>', '<<' => '>>',
};
sub get_overload_method() {
    my ($self, $arg1, $arg2, $swap, $operator) = @_;
    if ($swap) {
        $operator = $op_swap->{$operator} || $operator;
    }
    my $arg1_type = $self->get_argument_type($arg1);
    my $key = ($operator =~ /\{\}$/)
    ? "$operator $arg1_type"
    : do {
        my $arg2_type = $self->get_argument_type($arg2);
        "$arg1_type $operator $arg2_type";
    };
    my $table = $self->overload_table;
    return defined $table->{$key} 
      ? $table->{$key}
      : $self->overload_undefined($key);
}

sub get_argument_type {
    my $argument = shift;
    my $ref = ref($argument);
    return 'scalar' unless $ref;
    return 'code' if $ref eq 'CODE';
    return 'array' if $ref eq 'ARRAY';
    return 'hash' if $ref eq 'HASH';
    return 'ref' unless $argument->isa('IO::All');
    my $type = $argument->type;
    return defined $argument->name ? 'file' : 'unknown' 
      unless defined $type;
    return 'file' if $type eq 'pipe';
    return $type;
}

sub overload_stringify {
    my $name = $self->name;
    return defined($name) ? $name : overload::StrVal($self);
}

sub overload_undefined {
    my $key = shift;
    warn "Undefined behavior for overloaded IO::All operation: '$key'";
    return 'overload_noop';
}

sub overload_noop {
    return;
}

sub overload_scalar_addto_file() {
    $_[1]->append($_[2]);
    $_[1];
}

sub overload_file_addto_file() {
    $_[2]->append($_[1]->scalar);
}

sub overload_file_addfrom_file() {
    $_[1]->append($_[2]->scalar);
}

sub overload_file_to_file() {
    require File::Copy;
    File::Copy::copy($_[1]->name, $_[2]->name);
    return $_[2];
}

sub overload_file_from_file() {
    require File::Copy;
    File::Copy::copy($_[2]->name, $_[1]->name);
    return $_[1];
}

sub overload_dir_as_array() {
    [ $_[1]->all ];
}

sub overload_dir_as_hash() {
    +{ 
        map {
            (my $name = $_->name) =~ s/.*[\/\\]//;
            ($name, $_);
        } $_[1]->all 
    };
}

sub overload_file_as_array() {
    $_[1]->assert_tied_file;
}

sub overload_file_as_dbm() {
    $_[1]->assert_open_dbm;
}

sub overload_scalar_to_file() {
    local $\;
    $_[1]->print($_[2]);
    $_[1];
}

sub overload_file_as_scalar() {
    my $scalar = $_[1]->scalar;
    return \$scalar;
}

sub overload_file_to_scalar() {
    $_[2] = $_[1]->scalar;
}

sub overload_file_addto_scalar() {
    $_[2] .= $_[1]->scalar;
}

sub overload_socket_as_code {
    sub {
        my $coderef = shift;
        while ($self->is_open) {
            $_ = $self->getline;
            &$coderef($self);
        }
    }
}

sub overload_file_to_socket() {
    local $\;
    $_[1]->print($_[2]->scalar);
    $_[1]->close;
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
    io('./allstuff') << $stuff;

or:

    ${io('./stuff')} . ${io('./morestuff')} > io('./allstuff');

=head1 SYNOPSIS II

    use IO::All;

    # Print name and first line of all files in a directory
    my $dir = io('./mydir'); 
    while (my $io = $dir->next) {
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

    # And STDERR too
    "Warning Danger Abort!\n" > io'=';

=head1 SYNOPSIS IV

    use IO::All;
    
    # A forking socket server that writes to a log
    my $server = io('server.com:9999');
    my $socket = $server->accept('-fork');
    while (my $msg = $socket->getline) {
        io('./mylog')->appendln(localtime() . ' - $msg');
    }
    $socket->close;

    # A single statement web server for static files and cgis too
    io(":8080")->accept("-fork")->
      (sub { $_[0] < io(-x $1 ? "./$1 |" : $1) if /^GET \/(.*) / });

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
IO::String, Tie::File and File::ReadBackwards; as well as the DBM
modules. You can use most of the methods found in these classes and in
IO::Handle (which they inherit from). IO::All is easily subclassable.
You can override any methods and also add new methods of your own.

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

    my $stuff < io'./mystuff';

And that is a B<good thing>!

=head1 USAGE

The use statement for IO::All can be passed several options:

    use IO::All;
    use IO::All '-tie';
    use IO::All '-lock';
    use IO::All '-base';

With the exception of '-base', these options are simply defaults that
are passed on to every C<io> function within the program.

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

=item * -base

Boolean. This option which is inherited from Spiffy, makes the current
package a subclass of IO::All (which is a subclass of Spiffy). The
option is also available to packages that want to use the new subclass
as a base class.

    package IO::Different;
    use IO::All '-base';

=back

=head1 COOKBOOK

This section describes some various things that you can easily cook up
with IO::All.

=head2 Operator Overloading

IO::All objects stringify to their file or directory name. Here we print the
contents of the current directory:

    perl -MIO::All -le 'print for io(".")->all'

or:

    perl -MIO::All -le 'print for @{io"."}'

'>' and '<' move data between strings and files:

    $content1 < io('file1');
    $content1 > io('file2');
    io('file2') > $content3;
    io('file3') < $content3;
    io('file3') > io('file4');
    io('file5') < io('file4');

'>>' and '<<' do the same thing except the recipent string or file is
appended to.

An IO::All file used as an array reference becomes tied using Tie::File:

    $file = io'file';
    # Print last line of file
    print $file->[-1];
    # Insert new line in middle of file
    $file->[$#$file / 2] = 'New line';

An IO::All directory used as an array reference, will expose each file or
subdirectory as an element of the array.

    print "$_\n" for @{io 'dir'};

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

    my $io = io'file1.txt';
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

=head2 DBM Files

IO::All file objects used as a hash reference, treat the file as a DBM tied to
a hash. Here I write my DB record to STDERR:

    io("names.db")->{ingy} > io'=';

Since their are several DBM formats available in Perl, IO::All picks the first
one of these that is installed on your system:

    DB_File GDBM_File NDBM_File ODBM_File SDBM_File

You can override which DBM you want, either globally:

    IO::All->dbm('NDBM_File');

or per IO::All object:

    my @keys = keys %{io('mydbm')->dbm('SDBM_File')};

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
        '=',
        '$',
        -file_name => $file_name,
        -file_handle => $file_handle,
        -dir_name => $directory_name,
        -dir_handle => $directory_handle,
        '-tie',
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

=item * atime()

Last access time in seconds since the epoch (from stat)

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

=item * blksize()

Preferred block size for file system I/O (from stat)

=item * blocks()

Actual number of blocks allocated (from stat)

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

=item * ctime()

Inode change time in seconds since the epoch (from stat)

=item * dbm()

This method takes the names of one or more DBM modules. The first one that is
available is used to process the dbm file. The method returns the IO::All
object so that you can chain it.

    io('mydbm')->dbm('NDBM_File', 'SDBM_File')->{author} = 'ingy';

=item * device()

Device number of filesystem (from stat)

=item * device_id()

Device identifier for special files only (from stat)

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

=item * gid()

Numeric group id of file's owner (from stat)

=item * hash()

This method will return a reference to a tied hash representing the
directory. This allows you to treat a directory like a hash, where the
keys are the file names, and the values call lstat, and deleting a key
deletes the file.

See IO::Dir for more information on Tied Directories.

=item * inode()

Inode number (from stat)

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

=item * modes()

File mode - type and permissions (from stat)

=item * mtime()

Last modify time in seconds since the epoch (from stat)

=item * name()

Return the name of the file or directory represented by the IO::All
object.

=item * next()

For a directory, this will return a new IO::All object for each file
or subdirectory in the directory. Return undef on EOD.

=item * nlink()

Number of hard links to the file (from stat)

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

=item * scalar()

Same as slurp, but ignores list context and always returns one string. Nice to
use when you, for instance, want to use as a function argument where list
context is implied:

    compare(io('file1')->scalar, io('file2')->scalar);

=item * seek()

Proxy for IO::Handle::seek(). If you use seek on an unopened file, it will be
opened for both read and write.

=item * send()

Proxy for IO::Socket::send()

=item * shutdown()

Proxy for IO::Socket::shutdown()

=item * size()

Total size of file in bytes (from stat)

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

=item * type()

Returns a string indicated the type of io object. Possible values are:

    file
    dir
    link
    socket
    string
    pipe

Returns undef if type is not determinable.

=item * uid()

Numeric user id of file's owner (from stat)

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

IO is tricky stuff. There is definitely more work to be done. On the
other hand, this module relies heavily on very stable existing IO
modules; so it may work fairly well.

I am sure you will find many unexpected "features". Please send all
problems, ideas and suggestions to ingy@cpan.org.

=head2 Known Bugs and Deficiencies

Not all possible combinations of objects and methods have been tested. There
are many many combinations. All of the examples have been tested. If you find
a bug with a particular combination of calls, let me know.

If you call a method that does not make sense for a particular object,
the result probably won't make sense. No attempt is made to check for
improper usage.

Support for format_write and other format stuff is not supported yet.

=head1 SEE ALSO

IO::Handle, IO::File, IO::Dir, IO::Socket, IO::String, IO::ReadBackwards,
Tie::File

Also check out the Spiffy module if you are interested in extending this
module.

=head1 AUTHOR

Brian Ingerson <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2004. Brian Ingerson. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
