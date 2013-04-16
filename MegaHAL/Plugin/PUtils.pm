package MegaHAL::Plugin::PUtils;
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = {};
    $serv->reg_cb(
        'iConsoleCommand' => sub {
            my ($this, $iface, $cmd, @args) = @_;
            if ($cmd =~ /^pu(?:til)?s?$/i) {
                if (!$serv->is_loaded($args[0])) {
                    $iface->write("\cC4$args[0] is not the name of a loaded plugin!");
                    return;
                }
                given ($args[1]) {
                    when ('help') {
                        $iface->write(<<'HELP');
<plugin> add <channel> [argument]
<plugin> rem <channel>
<plugin> list
<plugin> set <channel> [argument]
<plugin> +b <mask>
<plugin> -b <mask>
HELP
                    }
                    when ('add') {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'ARRAY') {
                                push @{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} }, $args[2];
                                $iface->write("Added $args[0] [ARRAY] to channel $args[2] successfully.");
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'HASH') {
                                $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->{ $args[2] } = $args[3] || 1;
                                $iface->write("Added $args[0] [HASH] to channel $args[2]" . ($args[3] ? ' with argument "' . $args[3] . '"' : '') . " successfully.");
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported chans structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a chans structure!");
                        }
                    }
                    when ([ 'remove', 'rem' ]) {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'ARRAY') {
                                foreach (0 .. scalar(@{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} })) {
                                    if ($serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->[$_] eq $args[0]) {
                                        splice @{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} }, $_, 1;
                                        $iface->write("Removed $args[0] [ARRAY] from channel $args[2] successfully.");
                                    }
                                }
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'HASH') {
                                delete $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->{ $args[2] };
                                $iface->write("Removed $args[0] [HASH] from channel $args[2] successfully.");
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported chans structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a chans structure!");
                        }
                    }
                    when ('set') {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'ARRAY') {
                                $iface->write("\cC4Can't set an ARRAY chans struct!");
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'HASH') {
                                $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->{ $args[2] } = $args[3] || 1;
                                $iface->write("Set $args[0] [HASH] channel $args[2] argument to \"" . ($args[3] || 1) . "\" successfully");
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported chans structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a chans structure!");
                        }
                    }
                    when ('list') {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'ARRAY') {
                                $iface->write(join " | ", @{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} });
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} eq 'HASH') {
                                $iface->write(join " | ", map { $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->{$_} ne 1 ? $_ . ':"' . $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'}->{$_} . '"' : $_ } %{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'chans'} });
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported chans structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a chans structure!");
                        }
                    }
                    when ('+b') {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} eq 'ARRAY') {
                                push @{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} }, $args[2];
                                $iface->write("Blacklisted $args[2] from plugin $args[0] [ARRAY] successfully.");
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} eq 'HASH') {
                                $iface->write("\cC4No HASH blacklist support yet!");
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported bl structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a bl structure!");
                        }
                    }
                    when ('-b') {
                        if (exists $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'}) {
                            if (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} eq 'ARRAY') {
                                foreach (0 .. scalar(@{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} })) {
                                    if ($serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'}->[$_] eq $args[0]) {
                                        splice @{ $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} }, $_, 1;
                                        $iface->write("Un-blacklisted $args[2] from plugin $args[0] [ARRAY] successfully.");
                                    }
                                }
                            } elsif (ref $serv->{'plugins'}->{'plugins'}->{ $args[0] }->{'bl'} eq 'HASH') {
                                $iface->write("\cC4No HASH blacklist support yet!");
                            } else {
                                $iface->write("\cC4$args[0] does not have a supported bl structure!");
                                return;
                            }
                        } else {
                            $iface->write("\cC4$args[0] does not have a bl structure!");
                        }
                    }
                }
            }
        }
    );
    return bless $self, $class;
}

1;
