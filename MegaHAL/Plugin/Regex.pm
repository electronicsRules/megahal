package MegaHAL::Plugin::Regex;
use Text::Glob qw(glob_to_regex);
use Safe;
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {}, 'lastmsg' => {}, 'bl' => {} };
    $serv->reg_cb(
        'publicmsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = lc($ircmsg->{'params'}->[0]);
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            if ($self->{'chans'}->{lc($chan)} && !(hmatch($self->{'bl'},$nick,$ident))) {
                if ($message =~ /^ps\/.*\/.*\/[ige]*$/) {
                    my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                    $message =~ s/\\\\/\x{FFFE}/g;
                    $message =~ s/\\\//\x{FFFF}/g;
                    $message =~ /^p(s\/.*\/.*\/[ige]*)$/;
                    my $re = $1;
                    $re =~ s/\x{FFFE}/\\\\/g;
                    $re =~ s/\x{FFFF}/\\\//g;
                    my $s = new Safe;
                    $s->permit(qw(:base_core));
                    if (not defined $self->{'lastmsg'}->{$chan}) {
                        return;
                    }
                    ${ $s->varglob('msg') } = $self->{'lastmsg'}->{$chan}->[1];
                    my $ret;
                    eval {
                        local $SIG{ALRM} = sub { die "Timeout.\n" };
                        alarm 1;
                        local $SIG{FPE} = 'IGNORE';
                        $ret = $s->reval('local $_=$msg;$mtch=' . $re . ';return $_;');
                        alarm 0;
                    };
                    if ($@) {
                        $serv->msg($chan, "Error: ${C}5" . $@);
                    } elsif (${ $s->varglob('mtch') }) {
                        $serv->msg($chan, sprintf(($self->{'lastmsg'}->{$chan}->[2] ? '* %s %s' : '<%s> %s'), $self->{'lastmsg'}->{$chan}->[0], $ret));
                    } else {
                        $serv->msg($chan, $nick . ': No match.');
                    }
                    return;
                }
                $self->{'lastmsg'}->{$chan} = [ $nick, $message ];
            }
        }
    );
    $serv->reg_cb(
        'publicaction' => sub {
            my ($this, $nick, $chan, $message) = @_;
            $chan=lc($chan);
            if (!$serv->is_my_nick($nick) and $self->{'chans'}->{$chan}) {
                $self->{'lastmsg'}->{$chan} = [ $nick, $message, 1 ];
            }
        }
    );
    return bless $self, $class;
}

sub hmatch {
	my ($ref, $nick, $mask)=@_;
	my $mstr=$nick.'!'.$mask;
	foreach (@$ref) {
		$_=new MegaHAL::Regex::CGlobPat($_) if not ref $_;
		return 1 if $mstr=~$_;
	}
	return 0;
}

sub load {
    my ($self, $data) = @_;
    if (ref $data eq 'ARRAY') {
		$self->{'chans'} = $data->[0];
		$self->{'bl'} = $data->[1]->{'bl'};
	}else{
		$self->{'chans'} = $data;
	}
}

sub save {
    my ($self) = @_;
    return [$self->{'chans'},{'bl' => [map {ref $_ ? $_->str : $_} @{$self->{'bl'}}]}];
}

1;

package MegaHAL::Regex::CGlobPat;
use Text::Glob qw(glob_to_regex);

use overload
	'""' => sub {$_[0]->[0]},
	'qr' => sub {$_[0]->[1]},
	'0+' => sub {0+$_[0]->[0]},
	'bool' => sub {$_[0]->[0]};

sub new {
	my ($class,$str,$re)=@_;
	return bless $class, [$str, $re || glob_to_regex($str)];
}

sub str {$_[0]->[0]}
sub re {$_[0]->[1]}

1;
