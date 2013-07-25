package MegaHAL::Plugin::Dicebot;
use Math::BigInt try => 'GMP';
use Math::BigInt::Random qw(random_bigint);
use Text::Glob qw(glob_to_regex);
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {}, 'bl' => [] };
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
                if (!(hmatch($self->{'bl'}, $nick, $ident)) && $message =~ /^!\d+d(?:\d+|%)(?:[+-]\d+)?$/) {
                    my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                    $message =~ /^!(\d+)d(\d+|%)(?:([+-])(\d+))?/;
                    my ($n,$s,$o,$ov)=($1,$2,$3,$4);
                    my $repl = "Roll:";
					#$repl = "Roll: ".(join ', ',map {($s eq '%' ? int(rand() * 100) : int(1+rand() * $s)) + ($o ? ($o eq '+' ? $ov : -$ov) : 0)} 1..$n);
                    eval {
                        local $SIG{ALRM}=sub {die "Timeout!\n"};
                        my @repl;
                        alarm 1;
                        foreach (1..$n) {
                            push @repl, ($s eq '%' ? Math::BigInt->new(int(rand() * 100)) : ($s > 1 ? random_bigint(min => 1,max => $s) : $s) + ($o ? ($o eq '+' ? $ov : -$ov) : 0));
                        }
                        alarm 0;
                        $repl=join ", ", @repl;
                    };
                    alarm 0;
                    if ($@) {
                        if ($@=~/Timeout/) {
                            $serv->msg($chan,"The calculation timed out, sorry!");
                        }else{
                            $serv->msg($chan,"ERROR: $@");
                            print STDERR $@;
                        }
                    } else {
                        if (length($repl) < 512) {
                            $serv->msg($chan,$repl);
                        }else{
                            $serv->msg($chan,"Result too long, sorry!");
                        }
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
        $_ = MegaHAL::Plugin::Dicebot::CGlobPat->new($_) if not ref $_;
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

package MegaHAL::Plugin::Dicebot::CGlobPat;
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

