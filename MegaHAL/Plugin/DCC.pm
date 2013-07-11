package MegaHAL::Plugin::DCC;
use YAML::Any qw(Dump);
use MegaHAL::ACL;
use MegaHAL::Interface::DCC;

sub new {
    my ($class, $serv) = @_;
    my $self = { 'i' => {} };
    $serv->reg_cb(
        'privatemsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $serv->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %$modes;
            return if $command ne 'PRIVMSG';
            if ($message eq 'dcc') {
                $serv->auth($nick, undef)->on_done(
                    sub {
                        if ($_[0] && MegaHAL::ACL::has_ircnode($serv->name(), $nick, 'DCC', 'request', '')) {
                            my $id = $serv->dcc_initiate($nick, 'CHAT', 300, $serv->extip(), undef);
                            $self->{'i'}->{$id} = new MegaHAL::Interface::DCC($serv->name(), $nick, $id);
                        } else {
                            $serv->send_long_message('utf8', 0, 'PRIVMSG' => $nick, ($_[0] ? 'ACL fail!' : 'NS auth fail!'));
                        }
                    }
                  )->on_fail(
                    sub {
                        $serv->msg($nick, "\cC4Authentication error: $_[0]");
                    }
                  );
            }
        }
    );
    $serv->reg_cb(
        dcc_accepted => sub {
            my ($this, $id, $type, $hdl) = @_;
            $self->{'i'}->{$id}->write("Welcome to MegaHAL debug console!");
            $self->{'i'}->{$id}->{'auth'} = 1;
        }
    );
    $serv->reg_cb(
        dcc_chat_msg => sub {
            my ($this, $id, $msg) = @_;
            if ($self->{'i'}->{$id}) {
                printf "[%s] DCC#%s <%s> %s", $serv->name(), $id, $self->{'i'}->{$id}->{'nick'}, $msg;
                main::console($msg, $self->{'i'}->{$id});
            } else {
                $serv->send_dcc_chat($id, "This connection has been invalidated for whatever reason, please reconnect.");
            }
        }
    );
    $serv->reg_cb(
        dcc_close => sub {
            my ($this, $id, $type, $reason) = @_;
            delete $self->{'i'}->{$id};
        }
    );
    $serv->reg_cb(
        'iConsoleCommand' => sub {
            my ($this, $i, $cmd, @args) = @_;
            if ($cmd eq 'dcc' && $args[0] eq 'list') {
                $i->write(sprintf "[%s]%s#%s\n", $serv->name(), $self->{'i'}->{$_}->{'nick'}, $_) foreach keys %{ $self->{'i'} };
            }
        }
    );
    #$serv->reg_cb(stdout => sub {
    #    my ($this,$str)=@_;
    #    chomp $str;
    #    foreach (keys %{$self->{'i'}}) {
    #        $self->{'i'}->{$_}->write('<conout> '.$str);
    #    }
    #});
    #$serv->reg_cb(stderr => sub {
    #    my ($this,$str)=@_;
    #    chomp $str;
    #    foreach (keys %{$self->{'i'}}) {
    #        $self->{'i'}->{$_}->write("\cC4<conerr> ".$str);
    #    }
    #});
    return bless $self, $class;
}

sub DESTROY {
    my ($self, $serv) = @_;
    $serv->send_dcc_chat($_, "MegaHAL DCC plugin is being unloaded or reloaded. Contact your administrator for more information. Your session has been terminated. Goodbye.") foreach keys %{ $self->{'i'} };
    $serv->dcc_disconnect($_, "DCC plugin unloaded!") foreach keys %{ $self->{'i'} };
}
