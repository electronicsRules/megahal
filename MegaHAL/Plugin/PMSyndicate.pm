package MegaHAL::Plugin::PMSyndicate;

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => [] };
    $serv->reg_cb(
        privatemsg => sub {
            my ($this, $nick, $ircmsg) = @_;
            my $command = $ircmsg->{'command'};
            my $message = $ircmsg->{'params'}->[1];
            return if $command ne 'PRIVMSG';
            my ($modes, $source, $ident) = $this->split_nick_mode($ircmsg->{'prefix'});
            $serv->send_long_message('utf8', 0, NOTICE => $_, " <\cC5$source\cO> $message") foreach @{ $self->{'chans'} };
        }
    );
    $serv->reg_cb(
        ctcp => sub {
            my ($this, $src, $target, $tag, $msg, $type) = @_;
            if ($tag eq 'ACTION' && $type eq 'PRIVMSG' and not $serv->is_channel_name($target)) {
                $serv->send_long_message('utf8', 0, NOTICE => $_, " * \cC5$src\cO $msg") foreach @{ $self->{'chans'} };
            }
        }
    );
    $serv->reg_cmd([ {
                name => [ 'msg',    'say', 'privmsg' ],
                args => [ 'target', 'string+' ],
                cb   => sub {
                    my ($i, $pd, $opts, @args) = @_;
                    my $nick    = $i->source();
                    my $ownnick = $serv->nick();
                    my $tgt     = shift @args;
                    my $msg     = join ' ', @args;
                    $serv->send_long_message('utf8', 0, PRIVMSG => $_, "\cC3$nick\cO -> $tgt $msg") foreach @{ $self->{'chans'} };
                    $serv->msg($tgt, $msg);
                  }
            },
            {   name => [ 'act',    'action', 'me' ],
                args => [ 'target', 'string+' ],
                cb   => sub {
                    my ($i, $pd, $opts, @args) = @_;
                    my $nick    = $i->source();
                    my $ownnick = $serv->nick();
                    my $tgt     = shift @args;
                    my $msg     = join ' ', @args;
                    $serv->send_long_message('utf8', 0, PRIVMSG => $_, "\cC3$nick\cO -> $tgt * $ownnick $msg") foreach @{ $self->{'chans'} };
                    $serv->msg($tgt, "\cAACTION $msg\cA");
                  }
            }
        ]
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
