package MegaHAL::Plugin::Doors;
use Text::Glob qw(glob_to_regex);
use EV;
use Safe;
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {}, 'bl' => [], 'timers' => [] };
    $serv->reg_cb(
        'publicmsg' => sub {
            my ($this,  $nick, $ircmsg) = @_;
            my ($modes, $nick, $ident)  = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = lc($ircmsg->{'params'}->[0]);
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            if ($self->{'chans'}->{ lc($chan) }) {
                if (!(hmatch($self->{'bl'}, $nick, $ident)) && $message=~/^Open the pod[ -]?bay doors,? ?(?:please,?)? ?(?:Mega)?HAL/i) {
                    my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                    if ($message=~/please/i) {
						$serv->msg($chan,"${C}3${B}Pod bay doors opened.${O} You might want to hurry up, ${B}$nick${O}.");
						if (rand() > 0.5) {
							push @{$self->{'timers'}}, EV::timer(1.5,0,sub {
								$serv->msg($chan,"${C}5Pod bay doors closed. ${B}You were too slow, $nick. Goodbye.");
								$serv->msg($chan,"${C}5Your replacement has expressed the utmost interest in this mission. Isn't that right, ${B}GLaDOS?") if rand() > 0.7;
							});
						}
					}else{
						$serv->msg($chan,"${C}5I'm sorry, ${B}$nick${B}, but I can\'t let you do that.");
					}
                    return;
                }
            }
        }
    );
    return bless $self, $class;
}

sub hmatch {
    my ($ref, $nick, $mask) = @_;
    my $mstr = $nick . '!' . $mask;
    foreach (@$ref) {
        $_ = MegaHAL::Plugin::Doors::CGlobPat->new($_) if not ref $_;
        return 1 if $mstr =~ $_;
    }
    return 0;
}

sub load {
    my ($self, $data) = @_;
    if (ref $data eq 'ARRAY') {
        $self->{'chans'} = $data->[0];
        $self->{'bl'}    = $data->[1]->{'bl'};
    } else {
        $self->{'chans'} = $data;
    }
}

sub save {
    my ($self) = @_;
    return [ $self->{'chans'}, { 'bl' => [ map { ref $_ ? $_->str : $_ } @{ $self->{'bl'} } ] } ];
}

1;

package MegaHAL::Plugin::Doors::CGlobPat;
use Text::Glob qw(glob_to_regex);

use overload
  '""'     => sub { $_[0]->[0] },
  'qr'     => sub { $_[0]->[1] },
  '0+'     => sub { 0 + $_[0]->[0] },
  'bool'   => sub { $_[0]->[0] },
  fallback => 1;

sub new {
    my ($class, $str, $re) = @_;
    return bless [ $str, $re || glob_to_regex($str) ], $class;
}

sub str { $_[0]->[0] }
sub re  { $_[0]->[1] }

1;
