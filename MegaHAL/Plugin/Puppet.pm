package MegaHAL::Plugin::Puppet;
use feature 'switch';
use YAML::Any qw(Dump);
use MegaHAL::ACL;
use MegaHAL::Interface::PM;
use Text::ParseWords;

sub new {
    my ($class, $serv) = @_;
    my $self = { 'users' => {} };
    $serv->reg_cb(
        'privatemsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $serv->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %$modes;
            return if $command ne 'PRIVMSG';
            my ($cmd, @args) = shellwords($message);
            $self->{'users'}->{$nick} = new MegaHAL::Interface::PM($serv->name(), $nick) if not $self->{'users'}->{$nick};
            given ($cmd) {
                when ('say') {
                    my $chan = $self->{'users'}->{$nick}->{'pchan'} ? $self->{'users'}->{$nick}->{'pchan'} : $args[0];
                    return unless $serv->is_channel_name($chan);
                    my $msg = join(' ', (splice @args, ($self->{'users'}->{$nick}->{'pchan'} ? 0 : 1)));
                    $self->{'users'}->{$nick}->acan(
                        'Puppet', 'say',
                        $args[0]
                    )->on_done(sub {
                        return if not $_[0];
                        $serv->msg($chan, $msg);
                        print "$nick -> $chan: $msg\n";
                    });
                }
                when ('act') {
                    return unless $serv->is_channel_name($args[0]);
                    $self->{'users'}->{$nick}->acan(
                        'Puppet', 'act',
                        $args[0]
                    )->on_done(sub {
                        return if not $_[0];
                        $serv->msg($chan, ("\001ACTION $msg\001"));
                        print "$nick -> $chan [ACTION]: $msg\n";
                    });
                }
                when ('pchan') {
                    if ($args[0]) {
                        $self->{'users'}->{$nick}->{'pchan'} = $args[0];
                        $self->{'users'}->{$nick}->write("say/act channel set to $args[0] - those commands now expect just a message.\nSay 'pchan' with no arguments to revert this behaviour.");
                    } else {
                        delete $self->{'users'}->{$nick}->{'pchan'};
                        $self->{'users'}->{$nick}->write("say/act channel unset.");
                    }
                }
            }
        }
    );
    return bless $self, $class;
}
