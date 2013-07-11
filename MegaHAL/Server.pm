package MegaHAL::Server;
use feature 'switch';
use utf8;
use AnyEvent;
use AnyEvent::IRC::Client;
use YAML::Any qw(LoadFile DumpFile Dump);
use AnyEvent::ReadLine::Gnu;
use Text::ParseWords;
use Getopt::Long qw(GetOptionsFromArray);
use MegaHAL::Plugins;
use Scalar::Util qw(weaken);
use Carp qw(carp croak cluck confess);
use Time::HiRes qw(time);

sub new {
    my ($class, $opt) = @_;
    my $self = {
        'ctimer'   => {},
        'timer'    => [],
        'session'  => {},
        'lastmsg'  => 0,
        'msgcache' => [],
      ##'scap' => {}
    };
    bless $self, $class;
    #$self->{'plugins'} = MegaHAL::Plugins->new($self);
    #$self->{'plugins'}->new_hook($_) foreach qw(auth_ok auth_fail connecting connect disconnect reconnect pingTimeout consoleCommand iConsoleCommand stdout stderr tick publicaction);
    my %def = (
        'port'      => '6667',
        'ssl'       => '0',
        'nick'      => 'MegaHAL',
        'user'      => 'megahal',
        'real'      => 'MegaHAL',
        'pass'      => '',
        'auth'      => 'nickserv',
        'authpw'    => '',
        'name'      => '',
        'reconnect' => -1,
        'ping'      => 60,
        'oper'      => '',
        'ip'        => undef,
        'extip'     => undef
    );
    $self->{$_} = defined($opt->{$_}) ? $opt->{$_} : $def{$_} foreach keys %def;
    $self->{'dc'}        = \(undef);
    $self->{'expect_dc'} = 0;
    return $self;
}

foreach (qw(send_raw send_msg send_dcc_chat set_nick_change_cb nick is_my_nick channel_list nick_modes send_srv clear_srv_queue send_chan clear_chan_queue send_long_message lower_case eq_str isupport split_nick_mode map_prefix_to_mode map_mode_to_prefix available_nick_modes is_channel_name nick_ident away_status ctcp_auto_reply dcc_initiate dcc_disconnect dcc_accept unreg_cb unreg_me)) {
    eval '*' . $_ . q# = sub {
        my ($self,@args)=@_;
        return ($self->{'con'} ? $self->{'con'}-># . $_ . q#(@args) : undef);
    };#;
    die $@ if $@;
}

sub extip {
    my ($self) = @_;
    return $self->{'extip'} || $main::extip;
}

sub msg {
    my ($self, $target, $msg) = @_;
    if ((time - $self->{'lastmsg'}) >= 1) {
        $self->{'lastmsg'} = time;
        $self->{'lastmsg'} += 0.5 * (2**(length($msg) / 512)) if length($msg) > 380;
        $self->send_long_message('utf8', 0, 'PRIVMSG' => $target, $msg);
      ##print "Instant msg!\n";
      ##print ($self->{'lastmsg'}-time)."\n";
    } else {
        push @{ $self->{'msgcache'} }, [ $target, $msg ];
      ##print "Delayed msg!\n";
    }
}

sub name {
    my ($self) = @_;
    return $self->{'name'};
}

sub is_connected {
    my ($self) = @_;
    return 1 if $self->{'status'} > 1;
    return 0;
}

sub is_connecting {
    my ($self) = @_;
    return 1 if $self->{'status'} > 0;
    return 0;
}

sub registered {
    my ($self) = @_;
    return 1 if $self->{'status'} > 2;
    return 0;
}

sub is_oper {
    my ($self) = @_;
    return 1 if $self->{'oper'} ne '' and $self->{'status'} > 3;
}

foreach (qw(load_plugin unload_plugin new_hook call_hook list_plugin_hooks list_hook_plugins list_plugins is_loaded error_cb has_hook)) {
    eval '*' . $_ . q# = sub {
        my ($self,@args)=@_;
        return $self->{'plugins'}-># . $_ . q#(@args);
    };#;
}

sub reg_cb {
    my ($self, $hook, $cb) = @_;
    if ($self->has_hook($hook) && MegaHAL::Plugins->c_is_pl()) {
        $self->{'plugins'}->reg_cb($hook, $cb, 2);
    } else {
        if (MegaHAL::Plugins->c_is_pl()) {
            my $g = $self->{'con'}->reg_cb($hook, $cb);
            my $plugin = (substr caller, length('MegaHAL::Plugin::'));
            print "[$$self{name}] Hooking $hook for $plugin\n";
            push @{ $self->{'plugins'}->{'reghooks'}->{$plugin} }, $g;
            return $g;
        } else {
            if (defined wantarray()) {
                return $self->{'con'}->reg_cb($hook, $cb);
            } else {
                $self->{'con'}->reg_cb($hook, $cb);
            }
        }
    }
}

sub connect {
    my ($self) = @_;
    my $ret;
    $self->{'con'} = AnyEvent::IRC::Client->new(send_initial_whois => 1);
    $self->{'plugins'} = MegaHAL::Plugins->new($self);
    $self->{'plugins'}->new_hook($_) foreach qw(auth_ok auth_fail connecting connect disconnect reconnect pingTimeout consoleCommand iConsoleCommand stdout stderr tick publicaction);
    if ($self->{'ssl'}) {
        $self->{'con'}->enable_ssl();
    }
    if ($self->{'pldata'}) {
        my $r = $self->{'plugins'}->load($self->{'pldata'});
        if ($r != 0) {
            $ret = $r;
        }
        #delete $self->{'pldata'};
    }
    $self->{'con'}->reg_cb(
        connect => sub {
            if ($_[1]) {
                $self->{'status'} = 0;
                warn "[$$self{name}] Failed to connect: $_[1]\n";
            } else {
                $self->{'status'} = 2;
                print "[$$self{name}] Connected\n";
                $self->call_hook('connect', $_[1]);
            }
        }
    );
    $self->{'con'}->reg_cb(
        disconnect => sub {
            $self->{'status'}  = 0;
            $self->{'timer'}   = [];
            $self->{'session'} = {};
            if ($_[1] ne $self->{'dc'} and not($self->{'expect_dc'} and $_[1] =~ /^EOF from server/)) {
                warn "[$$self{name}] Disconnected: $_[1]\n";
                $self->call_hook('disconnect', $_[1]);
                if ($self->{'reconnect'} >= 0) {
                    push @{ $self->{'timer'} }, AnyEvent->timer(
                        after => $self->{'reconnect'},
                        cb    => sub {
                            print "[$$self{name}] Reconnecting...\n";
                            $self->call_hook('reconnect');
                            $self->connect();
                        }
                    );
                }
            } else {
                print "[$$self{name}] disconnected\n";
                $self->{'expect_dc'}->();
                $self->call_hook('disconnect');
            }
        }
    );
    $self->{'status'} = 1;
    $self->call_hook('connecting');
    $self->{'con'}->connect(
        $self->{'ip'},
        $self->{'port'},
        {   nick => $self->{'nick'},
            user => $self->{'user'},
            real => $self->{'real'},
            ($self->{'pass'} ne '' ? (password => $self->{'pass'}) : ())
        }
    );
    $self->{'con'}->reg_cb(
        error => sub {
            my ($this, $code, $message, $ircmsg) = @_;
            print "[$$self{name}] Error $code: ($message) " . (join ',', @{ $ircmsg->{'params'} }) . "\n";
        }
    );
    $self->{'con'}->reg_cb(
        privatemsg => sub {
            my ($this, $nick, $ircmsg) = @_;
            my $command = $ircmsg->{'command'};
            my $message = $ircmsg->{'params'}->[1];
            my ($modes, $source, $ident) = $this->split_nick_mode($ircmsg->{'prefix'});
            print "[$$self{name}] $source -> $nick: $message\n";
        }
    );
    $self->{'con'}->reg_cb(
        ctcp => sub {
            my ($this, $src, $target, $tag, $msg, $type) = @_;
            if (uc($tag) eq 'ACTION' && $type eq 'PRIVMSG' and not $self->{'con'}->is_channel_name($target)) {
                print "[$$self{name}] $src -> $target [ACTION]: $msg\n";
            }
            #print "CTCP: [src=$src,target=$target,tag=$tag,msg=$msg,type=$type]\n";
            if (uc($tag) eq 'ACTION' && $type eq 'PRIVMSG' and $self->{'con'}->is_channel_name($target)) {
                $self->call_hook('publicaction', $src => $target, $msg);
            }
        }
    );
    $self->{'con'}->reg_cb(
        registered => sub {
            $self->{'status'} = 3;
            $_[0]->unreg_me;
            push @{ $self->{'timer'} }, AnyEvent->timer(
                after    => 0.5,
                interval => 0.5,
                cb       => sub {
                    $self->call_hook('tick');
                    if (scalar(@{ $self->{'msgcache'} }) > 0 && (time - $self->{'lastmsg'}) >= 1) {
                        my ($tgt, $msg) = @{ shift @{ $self->{'msgcache'} } };
                        $self->send_long_message('utf8', 0, 'PRIVMSG' => $tgt, $msg);
                        $self->{'lastmsg'} = time;
                        $self->{'lastmsg'} += 0.5 * (2**(length($msg) / 512)) if length($msg) > 380;
                      ##print ($self->{'lastmsg'}-time)."\n";
                    }
                }
            );
            if ($self->{'auth'} && $self->{'authpw'}) {
                given ($self->{'auth'}) {
                    when ('nickserv') {
                        $self->{'auth_ok'} = 0;
                        my $grd = $self->{'con'}->reg_cb(
                            privatemsg => sub {
                                my ($this, $nick, $ircmsg) = @_;
                                my $command = $ircmsg->{'command'};
                                my $message = $ircmsg->{'params'}->[1];
                                if ($nick eq $self->nick() && ($message =~ /^You are now identified for / || $message =~ /Password accepted/)) {
                                    $self->{'auth_ok'} = 1;
                                    print "[$$self{name}] NickServ auth OK\n";
                                    $self->call_hook('auth_ok');
                                    $this->unreg_me;
                                }
                            }
                        );
                        my $tmr = AnyEvent->timer(
                            after => 15,
                            cb    => sub {
                                if (!$self->{'auth_ok'}) {
                                    $self->{'auth_ok'} = -1;
                                    warn "[$$self{name}] NickServ auth failed!\n";
                                    $self->call_hook('auth_fail');
                                    $self->{'con'}->unreg_cb($grd);
                                }
                            }
                        );
                        push @{ $self->{'timer'} }, $tmr;
                        $self->send_msg('NS' => 'IDENTIFY', $self->{'authpw'});
                    }
                    default {
                        cluck "Unknown authentication method: ${$self->{'auth'}}\n";
                    }
                }
            } else {
                $self->call_hook('auth_ok');
            }
            if ($self->{'oper'} ne '') {
                $self->send_srv('OPER', split / /, $self->{'oper'});
                print "[$$self{name}] Opering up...\n";
                $self->{'con'}->reg_cb(
                    irc_381 => sub {
                        $_[0]->unreg_me;
                        print "[$$self{name}] Opered up successfully!\n";
                        $self->{'status'} = 4;
                    }
                );
            }
            if ($self->{'ping'} > 0) {
                $self->{'con'}->enable_ping(
                    $self->{'ping'},
                    sub {
                        warn "[$$self{name}] Disconnected: Ping timeout\n";
                        $self->call_hook('pingTimeout');
                        $self->call_hook('disconnect', 'Ping timeout');
                        if ($self->{'reconnect'} >= 0) {
                            push @{ $self->{'timer'} }, AnyEvent->timer(
                                after => $self->{'reconnect'},
                                cb    => sub {
                                    print "[$$self{name}] Reconnecting...\n";
                                    $self->call_hook('reconnect');
                                    $self->connect();
                                }
                            );
                        }
                    }
                );
            }
        }
    );
    $self->{'con'}->reg_cb(
        'join' => sub {
            my ($this, $nick, $chan, $is_myself) = @_;
            if (!$is_myself) {
                if ($self->{'session'}->{$nick}->{'status'} eq 'waiting_chanauth' or $self->{'session'}->{$nick}->{'status'} eq 'chanauth') {
                    $self->{'session'}->{$nick}->{'channels'}++;
                } elsif ($self->{'session'}->{$nick}->{'status'} eq 'waiting_auth' or $self->{'session'}->{$nick}->{'status'} eq 'auth') {
                    $self->{'session'}->{$nick}->{'status'} =~ s/auth$/chanauth/;
                    $self->{'session'}->{$nick}->{'channels'}++;
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        part => sub {
            my ($this, $nick, $chan, $is_myself, $msg) = @_;
            if (!$is_myself) {
                if ($self->{'session'}->{$nick}->{'status'} eq 'waiting_chanauth' or $self->{'session'}->{$nick}->{'status'} eq 'chanauth') {
                    $self->{'session'}->{$nick}->{'channels'}--;
                    delete $self->{'session'}->{$nick} if $self->{'session'}->{$nick}->{'channels'} < 1;
                }
            } else {
                delete $self->{'ctimer'}->{$chan};
                foreach (keys %{ $self->{'session'} }) {
                    next unless $self->{'session'}->{$_}->{'status'} eq 'waiting_chanauth' or $self->{'session'}->{$_}->{'status'} eq 'chanauth';
                    my $n = $self->common_chans($_);
                    if ($n > 0) {
                        $self->{'session'}->{$_}->{'channels'} = $n;
                    } else {
                        delete $self->{'session'}->{$_};
                    }
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        quit => sub {
            my ($this, $nick, $msg) = @_;
            delete $self->{'session'}->{$nick};
        }
    );
    $self->{'con'}->reg_cb(
        kick => sub {
            my ($this, $nick, $chan, $is_myself, $msg, $kicker) = @_;
            if (!$is_myself) {
                if ($self->{'session'}->{$nick}->{'status'} eq 'waiting_chanauth' or $self->{'session'}->{$nick}->{'status'} eq 'chanauth') {
                    $self->{'session'}->{$nick}->{'channels'}--;
                    delete $self->{'session'}->{$nick} if $self->{'session'}->{$nick}->{'channels'} < 1;
                }
            } else {
                delete $self->{'ctimer'}->{$chan};
                foreach (keys %{ $self->{'session'} }) {
                    next unless $self->{'session'}->{$_}->{'status'} eq 'waiting_chanauth' or $self->{'session'}->{$_}->{'status'} eq 'chanauth';
                    my $n = $self->common_chans($_);
                    if ($n > 0) {
                        $self->{'session'}->{$_}->{'channels'} = $n;
                    } else {
                        delete $self->{'session'}->{$_};
                    }
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        nick_change => sub {
            my ($this, $old_nick, $new_nick, $is_myself) = @_;
            if (!$is_myself) {
                if ($self->{'session'}->{$old_nick}) {
                    $self->{'session'}->{$new_nick} = $self->{'session'}->{$old_nick};
                    delete $self->{'session'}->{$old_nick};
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        irc_307 => sub {
            my ($this, $msg) = @_;
            my $sysmsg = $msg->{params}->[-1];
            my $nick   = $msg->{params}->[-2];
            if ((substr $self->{'session'}->{$nick}->{'status'}, 0, length('waiting')) eq 'waiting') {
                if ((time - $self->{'session'}->{$nick}->{'ts'}) < 30) {
                    my $new = substr $self->{'session'}->{$nick}->{'status'}, length('waiting_');
                    $self->{'session'}->{$nick}->{'status'} = $new;
                    print "[$$self{name}] NickServ authentication OK for $nick\n";
                    $_->done() foreach @{ $self->{'session'}->{$nick}->{'cb'} };
                    delete $self->{'session'}->{'cb'};
                } else {
                    print "[$$self{name}] Recieved VERY LATE (>30sec) WHOIS 307 numeric for $nick, ignoring!\n";
                    $self->send_srv('NOTICE' => $nick, "NickServ authentication timed out.");
                    $_->fail("Timed out",1) foreach @{ $self->{'session'}->{$nick}->{'cb'} };
                    delete $self->{'session'}->{$nick};
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        irc_330 => sub {
            my ($this, $msg) = @_;
            my $sysmsg = $msg->{params}->[-1];
            my $nick   = $msg->{params}->[-3];
            my $nsnick = $msg->{params}->[-2];
            if ((substr $self->{'session'}->{$nick}->{'status'}, 0, length('waiting')) eq 'waiting') {
                if ((time - $self->{'session'}->{$nick}->{'ts'}) < 30) {
                    my $new = substr $self->{'session'}->{$nick}->{'status'}, length('waiting_');
                    $self->{'session'}->{$nick}->{'status'} = $new;
                    $self->{'session'}->{$nick}->{'nsnick'} = $nsnick;
                    $self->send_srv('NOTICE' => $nick, "NickServ authentication OK");
                    print "[$$self{name}] NickServ authentication OK for $nick\n";
                    $_->(1) foreach @{ $self->{'session'}->{$nick}->{'cb'} };
                    delete $self->{'session'}->{'cb'};
                } else {
                    print "[$$self{name}] Recieved VERY LATE (>30sec) WHOIS 330 numeric for $nick, ignoring!\n";
                    $self->send_srv('NOTICE' => $nick, "NickServ authentication timed out.");
                    $_->fail("Timed out",1) foreach @{ $self->{'session'}->{$nick}->{'cb'} };
                    delete $self->{'session'}->{$nick};
                }
            }
        }
    );
    $self->{'con'}->reg_cb(
        irc_318 => sub {
            my ($this, $msg) = @_;
            my $nick = $msg->{params}->[-2];
            if ((substr $self->{'session'}->{$nick}->{'status'}, 0, length('waiting')) eq 'waiting') {
                delete $self->{'session'}->{$nick};
                print "[$$self{name}] NickServ authentication for $nick failed\n";
                $_->fail("Authentication failed!",0) foreach @{ $self->{'session'}->{$nick}->{'cb'} };
                $self->send_srv('NOTICE' => $nick, "\cB\cC4NickServ authentication failed!\cO");
            }
        }
    );
    return $ret;
}

sub common_chans {
    my ($self, $nick) = @_;
    my %chans = $self->channel_list();
    return scalar(
        map {
            grep { $_ eq $nick }
              keys %$_
        } values %chans
    );
}

sub auth {
    my ($self, $nick, $chan, $cb) = @_;
    my $fut=new Future;
    $fut->on_ready($cb) if $cb;
    if ($self->{'session'}->{$nick}) {    # 2 minute session timeout
        if ($self->{'session'}->{$nick}->{'status'} eq 'auth' and ((time - $self->{'session'}->{$nick}->{'ts'}) < 120)) {
            $self->{'session'}->{$nick}->{'ts'} = time;
            return $fut->done(1);
        } elsif ($self->{'session'}->{$nick}->{'status'} ne 'chanauth' and (time - $self->{'session'}->{$nick}->{'ts'}) > 120) {
            delete $self->{'session'}->{$nick};
            return $fut->fail("Session timed out",1);
        } elsif ($self->{'session'}->{$nick}->{'status'} eq 'chanauth') {
            return $fut->done(1);
        } elsif ((substr $self->{'session'}->{$nick}->{'status'}, 0, length('waiting')) eq 'waiting') {
            push @{ $self->{'session'}->{$nick}->{'cb'} }, $fut;
            return $fut;
        } else {
            print "[$$self{name}] Unknown session state for $nick: " . ($self->{'session'}->{$nick}->{'status'});
            return $fut->fail("Unknown session state!",0);
        }
    } else {
        my $chans = $self->channel_list();
        my $n = scalar(grep { $_ eq $nick } map { keys %$_ } values %$chans);
        if ($n > 0) {    #At least one common channel
            $self->{'session'}->{$nick} = {
                'ts'       => time,
                'status'   => 'waiting_chanauth',
                'channels' => $n,
                'cb'       => [$fut]
            };
            print "Chanauth for $nick in progress...\n";
        } else {
            $self->{'session'}->{$nick} = {
                'ts'     => time,
                'status' => 'waiting_auth',
                'cb'     => [$fut]
            };
            print "Sessionauth for $nick in progress...\n";
        }
        $self->send_srv('WHOIS' => $nick);
        return $fut;
    }
}

sub disconnect {
    my ($self, $msg, $fast, $cb) = @_;
    $cb = $fast if ref($fast) eq 'CODE';
    return $cb->() unless $self->is_connecting();
    if ((not $fast) and ($self->registered())) {
        print "Quitting...\n";
        $self->{'expect_dc'} = $cb;
        $self->{'plugins'}->cleanup();
        $self->send_srv(QUIT => $msg);
        push @{ $self->{'timer'} }, AnyEvent->timer(
            after => 2,
            cb    => sub {
                $self->{'expect_dc'} = undef;
                $self->{'plugins'} = undef;
                $self->disconnect($msg, 1, $cb);
            }
        );
    } else {
        $self->{'con'}->disconnect();
        $cb->() if $cb;
    }
}

sub save {
    my ($self) = @_;
    my %ser;
    $ser{$_} = $self->{$_} foreach qw(port ssl nick user real pass auth authpw reconnect ping ip oper extip);
    $ser{'plugins'} = ($self->{'pldata'} ? $self->{'pldata'} : $self->{'plugins'}->save());
    return \%ser;
}

sub load {
    my ($self, $data) = @_;
    $self->{$_} = $data->{$_} foreach qw(port ssl nick user real pass auth authpw reconnect ping ip oper extip);
    if ($self->{'con'}) {
        return $self->{'plugins'}->load($data->{'plugins'});
    } else {
        $self->{'pldata'} = $data->{'plugins'};
    }
}

1;
