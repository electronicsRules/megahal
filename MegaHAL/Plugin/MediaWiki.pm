package MegaHAL::Plugin::MediaWiki;
use AnyEvent::Handle::UDP;
use Scalar::Util qw(weaken);

sub new {
    my ($class, $serv) = @_;
    my $self = {
        'wiki'  => {},
        'chans' => {},
        'sock'  => {}
    };
    $self->{'serv'} = $serv;
    weaken $self->{'serv'};
    return bless $self, $class;
}

sub upd_sockets {
    my ($self) = @_;
    my $sn = $self->{'serv'}->name();
    foreach (keys $self->{'sock'}) {
        if (not exists $self->{'wiki'}->{$_}) {
            print "[$sn] {MediaWiki:$_} Closing socket...\n";
            $self->{'sock'}->{$_}->destroy();
            delete $self->{'sock'}->{$_};
        }
    }
    foreach (keys $self->{'wiki'}) {
        if (not exists $self->{'wiki'}->{$_}) {
            print "[$sn] {MediaWiki:$_} Opening socket...\n";
            my $wiki = $_;
            $self->{'sock'}->{$_} = AnyEvent::Handle::UDP->new(
                bind    => $self->{'wiki'}->{$_},
                on_recv => sub {
                    my ($dgram, $hdl, $addr) = @_;
                    $self->recv($wiki, $dgram);
                },
                on_error => sub {
                    my ($hdl, $fatal, $error) = @_;
                    $self->error($wiki, $error, $fatal);
                },
            );
        }
    }
}

sub recv {
    my ($self, $wiki, $dgram) = @_;
    my $serv = $self->{'serv'};
    my $sn   = $serv->name();
    print "[$sn] {MediaWiki:$wiki} $dgram\n";
    $serv->msg($_, "[$wiki] " . $dgram) foreach grep { $self->{'chans'}->{$_}->{$wiki} } keys %{ $self->{'chans'} };
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data->{'chans'};
    $self->{'wiki'}  = $data->{'wiki'};
    $self->upd_sockets();
}

sub save {
    my ($self) = @_;
    return { 'chans' => $self->{'chans'}, 'wiki' => $self->{'wiki'} };
}

sub cleanup {
    my ($self) = @_;
    $_->destroy() foreach values $self->{'sock'};
    delete $self->{'serv'};
}
1;
