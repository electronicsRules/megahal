use feature 'switch';
use utf8;
use EV;
use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::HTTP;
use YAML::Any qw(LoadFile DumpFile Dump);
use AnyEvent::ReadLine::Gnu;
use Text::ParseWords;
use Getopt::Long qw(GetOptionsFromArray);
use MegaHAL::Filehandle;
use MegaHAL::Server;
use MegaHAL::Interface::Console;
use MegaHAL::ACL;
use MegaHAL::Shell;
use Term::ANSIColor qw(colorstrip);
use MegaHAL::Telnet;
our $VERSION = '1.5';
our @cmdt;
my $old_stdout;
open($old_stdout, '>&STDOUT') or die "Can't dup STDOUT!\n";
my $c = AnyEvent->condvar;
our %srv;
our $cif = MegaHAL::Interface::Console->new();
if (1 || !defined(&DB::DB)) {
    our $rl = AnyEvent::ReadLine::Gnu->new(
        prompt  => '> ',
        on_line => sub {
            console($_[0], $cif);
        },
        out => $old_stdout
    );
    tie(*STDOUT, 'MegaHAL::Filehandle', *STDOUT, $rl, \&outh);
    tie(*STDERR, 'MegaHAL::Filehandle', *STDERR, $rl, \&errh);
} else {
    my $t;
    $t = AnyEvent->timer(after => 1, interval => 1, cb => sub { $t; &dbghook });
}

sub dbghook {
    print '';
}
our %outh;
our $inouth = 0;
sub hout { $outh{ $outhn++ } = $_[0]; return $outhn - 1 }

sub outh {
    my ($str) = @_;
    return if $inouth;
    local $inouth = 1;
    MegaHAL::Telnet::outh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stdout', $str); };
    }
    $_->($str) foreach values %outh;
}
our @errh;
our $inerrh = 0;
sub herr { $errh{ $errhn++ } = $_[0]; return $errhn - 1 }

sub errh {
    my ($str) = @_;
    return if $inerrh;
    local $inerrh = 1;
    MegaHAL::Telnet::errh($str);
    foreach (values %srv) {
        eval { $_->call_hook('stderr', $str); };
    }
    $_->($str) foreach values %errh;
}

our $cfg = {};
our $extip;

sub init {
    load();
    MegaHAL::ACL::init();    #Connect to ACL database
    MegaHAL::Telnet::init();
    $c->recv;
}

sub load {
    if (-e 'megahal.yml') {
        $cfg   = LoadFile('megahal.yml');
        $extip = $cfg->{'extip'};
        foreach (keys %{ $cfg->{'servers'} }) {
            $srv{$_} = new MegaHAL::Server() if not $srv{$_};
            $srv{$_}->load($cfg->{'servers'}->{$_});
            $srv{$_}->{'name'} = $_;
        }
    }
    if (!$extip) {
        http_get 'http://automation.whatismyip.com/n09230945.asp', sub {
            $extip = $_[0];
          }
    }
}

sub save {
    $cfg->{'servers'} = { map { ($_, $srv{$_}->save()) } keys %srv };
    DumpFile('megahal.yml', $cfg);
}

sub a2h {
    my %h;
    foreach (@_) { $h{$_}++; }
    return %h;
}

END {
    $rl->hide if $rl;
}

#$iface, $pd, $opts, @args
our $core_cmds = [
    {},
    {   name => [ 'quit', 'q' ],
        cb   => sub       { exit; }
    },
    {   name => [ 'connect', 'con' ],
        args => ['server'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $::srv{ $pd->{server} }->connect();
          }
    },
    {   name => [ 'disconnect', 'dis' ],
        args => [ 'cserver',    'string?' ],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $::srv{ $pd->{server} }->disconnect($args[0]);
          }
    },
    {   name => [ 'eval', 'e' ],
        args => ['string+'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $i->write(eval $args[0]);
          }
    },
    {   name => [ 'print', 'p' ],
        args => ['string+'],
        cb   => sub {
            my ($i, $pd, $opts, @args) = @_;
            $i->write(Dump @args);
          }
    },
    {   name => [ 'help', 'h' ],
        args => ['*'],
        cb   => sub {
            my ($iface, $pd, $opts, @args) = @_;
            $iface->write(MegaHAL::Shell::help(cmdtree(), @args));
          }
    }
];

sub console {
    my ($line, $iface) = @_;
    MegaHAL::Shell::parse($iface, $line, [ $core_cmds, map { $_->commands() } values %srv ], {});
}
init();
