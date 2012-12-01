package MegaHAL::Plugin::autojoin;
use AnyEvent;

sub new {
    my ($class, $serv) = @_;
    my $self = {
        'chans'  => [],
        'timers' => []
    };
    $serv->reg_cb(
        'auth_ok' => sub {
            my $chans = $serv->channel_list();
            print "autojoin triggered - " . scalar(@{ $self->{'chans'} });
            my $t = 0;
            foreach (@{ $self->{'chans'} }) {
                next if $chans->{ lc $_ };
                my $chan = $_;
                push @{ $self->{'timers'} }, AnyEvent->timer(
                    after => $t += 1.5,
                    cb => sub {
                        $serv->send_srv(JOIN => (lc $chan));
                        print '[' . $serv->name() . "] Joining $chan...\n";
                    }
                );
            }
        }
    );
    $serv->reg_cb(
        'consoleCommand' => sub {
            my ($this, $cmd, @args) = @_;
            if ($cmd eq 'aj') {
                if ($args[0] eq 'add' && scalar(grep { $_ eq lc $args[1] } @{ $self->{'chans'} })) {
                    push @{ $self->{'chans'} }, $args[1];
                }
                if ($args[0] eq 'del') {
                    foreach (0 .. scalar(@{ $self->{'chans'} })) {
                        if ($self->{'chans'}->[$_] eq lc $args[1]) {
                            splice @{ $self->{'chans'} }, $_, 1;
                        }
                    }
                }
            }
        }
    );
    return bless $self, $class;
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data;
}

sub save {
    my ($self) = @_;
    return $self->{'chans'};
}
