$| = 1;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::ReadLine::Gnu;
use MegaHAL::Filehandle;
use Term::ReadLine::Gnu;
our ($name, $host, $port);
$host = $ARGV[0];
die if not $host;
$host =~ /^([^\@]+)\@(.*)(?::(\d+))?$/;
($name, $host, $port) = ($1, $2, $3);
$port = 9000 if not $port;
die if not $host;
if ($ENV{TERM} eq 'screen' || $ENV{TERM} eq 'tmux') {
    $0 = "tlstelnet";
    print "\e]0${name}\@${host}" . ($port != 9000 ? ':' . $port : '') . "\7";
}
our $old_stdout;
open($old_stdout, '>&STDOUT') or die "Can't dup STDOUT!\n";
our $rl;
our $katmr;
our $password = ReadPassword("Password for $name\@$host: ");
$rl = AnyEvent::ReadLine::Gnu->new(
    prompt  => '... ',
    on_line => \&input,
    out     => $old_stdout
);
tie(*STDOUT, 'MegaHAL::Filehandle', *STDOUT, $rl, sub { });
tie(*STDERR, 'MegaHAL::Filehandle', *STDERR, $rl, sub { });
print "Connecting...";
our $hdl;
our $hdl = AnyEvent::Handle->new(
    'connect' => [ $host, $port ],
    #peername    => $host,
    tls      => 'connect',
    on_error => sub {
        warn "Error: $_[2]\n";
        $cv->send;
    },
    on_eof => sub {
        warn "EOF.\n";
        $cv->send;
    },
    on_read => sub {
        print $_[0]->{rbuf};
        $_[0]->{rbuf} = "";
    },
    on_connect => sub {
        print "\rConnected!   \nAuthenticating...";
    }
);
$hdl->push_write($name . ':' . $password . "\n");
$hdl->push_read(
    line => sub {
        print "\rAuthenticated!       \n";
        setprompt("> ");
        $katmr = AnyEvent->timer(
            after    => 60,
            interval => 60,
            cb       => sub {
                $hdl->push_write("\n");
            }
        );
    }
);
our $cv = AnyEvent->condvar;
$cv->recv;

sub setprompt {
    my ($prompt) = @_;
    $AnyEvent::ReadLine::Gnu::prompt = $prompt;
    unless ($AnyEvent::ReadLine::Gnu::hidden) {
        $rl->rl_set_prompt($prompt);
        $rl->rl_redisplay();
    }
}

sub input {
    my ($line) = @_;
    $hdl->push_write($line . "\n");
}

sub ReadPassword {
    my $term = new Term::ReadLine 'megahal-telnet';
    $term->MinLine(undef);
    $term->ornaments('md,me,,');
    my $attr = $term->Attribs();
    local $attr->{redisplay_function} = $attr->{shadow_redisplay};
    my $ret = $term->readline($_[0]);
    $term->MinLine(1);
    return $ret;
}
