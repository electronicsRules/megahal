package MegaHAL::Plugin::ChanRedir;
sub new {
    my ($class,$serv)=@_;
    print "ChanRedir loaded!\n";
    my $self={
        'chans' => {}
        };
    $serv->reg_cb('join' => sub {
        my ($this,$nick,$chan,$is_myself)=@_;
        if ($self->{'chans'}->{$chan} and !$is_myself and $nick!~/Serv$/) {
            if ($serv->is_oper()) {
                print "[$$serv{name}] Redirecting $nick from $chan to ".$self->{'chans'}->{$chan};
                $serv->send_srv('SAJOIN' => $nick,$self->{'chans'}->{$chan});
                $serv->send_srv('KICK' => $nick);
            }
        }
    });
    return bless $self,$class;
}

sub load {
    my ($self,$data)=@_;
    $self->{'chans'}=$data;
}

sub save {
    my ($self)=@_;
    return $self->{'chans'};
}