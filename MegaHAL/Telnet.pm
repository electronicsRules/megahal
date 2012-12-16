package MegaHAL::Telnet;
use 5.016;
our $VERSION = '0.1';
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use MegaHAL::Interface::Telnet;
use MegaHAL::ACL;
our %clients;
our $nid = 0;

sub init {
    unless (-r 'ssl/megahal.cert' and -r 'ssl/megahal.cert.key') {
        print STDERR "Can't initialise TLSTelnet on port 9000 - no certificate installed!\n";
        return;
    }
    tcp_server(
        undef, 9000,
        sub {
            my ($fh) = @_;
            my $hdl = new AnyEvent::Handle(
                fh      => $fh,
                tls     => 'accept',
                tls_ctx => {
                    cert_file => 'ssl/megahal.cert',
                    key_file  => 'ssl/megahal.cert.key'
                },
            );
            my $id = $nid++;
            $clients{$id} = MegaHAL::Interface::Telnet->new($hdl);
            $hdl->on_error(
                sub {
                    my ($this, $fatal, $msg) = @_;
                    print STDERR "<telnet> $id error: $msg" unless $msg eq 'Broken pipe';
                    delete $clients{$id};
                    $this->destroy();
                }
            );
            $hdl->on_eof(
                sub {
                    my ($this) = @_;
                    #print STDERR "<telnet> $id eof\n";
                    delete $clients{$id};
                    $this->destroy();
                }
            );
            $hdl->push_read(
                line => sub {
                    get_auth_info($id, $_[1]);
                }
            );
        }
    );
}

sub get_auth_info {
    my ($id, $line) = @_;
    my ($user, @rest) = split ':', $line;    #Should be faster than regex.
    my $pass = join ':', @rest;
    if (MegaHAL::ACL::auth_user($user, $pass)) {
        $clients{$id}->{'user'} = $user;
        $clients{$id}->{'auth'} = 1;
        if ($clients{$id}->acan('core', 'telnet') || $clients{$id}->acan('*', '*') || $clients{$id}->acan('core', '*')) {
            $clients{$id}->{'hdl'}->push_write("MegaHAL v${MegaHAL::VERSION} SSL telnet console v$VERSION\n");
            $clients{$id}->{'rlcb'} = sub {
                read_line($id, $_[1]);
            };
            $clients{$id}->{'hdl'}->push_read(line => $clients{$id}->{'rlcb'});
            return;
        }
    }
    $clients{$id}->{'hdl'}->push_write("Authentication failed.\n");
    $clients{$id}->{'hdl'}->on_drain(
        sub {
            $clients{$id}->{'hdl'}->on_stoptls(
                sub {
                    delete $clients{$id}->{'hdl'};
                }
            );
            $clients{$id}->{'hdl'}->stoptls;
        }
    );
}

sub outh {
    my ($str) = @_;
    chomp $str;
    foreach (values %clients) {
        $_->write($str . "\n") if $_->{'auth'};
    }
}

sub errh {
    my ($str) = @_;
    chomp $str;
    foreach (values %clients) {
        $_->write("\cC4" . $str . "\n") if $_->{'auth'};
    }
}

sub read_line {
    my ($id, $line) = @_;
    $clients{$id}->{'hdl'}->push_read(line => $clients{$id}->{'rlcb'});
    main::console($line, $clients{$id}) unless $line eq "";
}
1;
