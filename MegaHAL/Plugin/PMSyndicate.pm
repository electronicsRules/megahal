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
            $serv->msg($_, " <\cC5$source\cO> $message") foreach @{ $self->{'chans'} };
        }
    );
    $serv->reg_cb(
        ctcp => sub {
            my ($this, $src, $target, $tag, $msg, $type) = @_;
            if ($tag eq 'ACTION' && $type eq 'PRIVMSG' and not $serv->is_channel_name($target)) {
                $serv->msg($_, " * \cC5$src\cO $msg") foreach @{ $self->{'chans'} };
            }
        }
    );
    $serv->reg_cb(
        'iConsoleCommand' => sub {
            my ($this, $i, $cmd, @args) = @_;
            my $nick = $i->source();
            my $tgt  = shift @args;
            my $msg  = join ' ', @args;
            if ($cmd eq 'msg') {
                $serv->msg($_, "\cC3$nick\cO -> $tgt $msg") foreach @{ $self->{'chans'} };
                $serv->msg($tgt, $msg);
            } elsif ($cmd eq 'help') {
                my $sn = $serv->name();
                $i->write(
                    "MegaHAL help (temporary command from PMSyndicate.pm):
Syndicated commands:
c $sn msg #channel message
Direct commands:
raw $sn privmsg #channel message
raw $sn notice #channel message
Quoting rules:
To send apostrophes, wrap them in \"double quotes\"
To send double quotes, wrap them in \'single quotes\'
"
                );
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
