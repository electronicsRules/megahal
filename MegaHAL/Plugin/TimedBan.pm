package MegaHAL::Plugin::TimedBan;
use Text::Glob qw(glob_to_regex);
use Time::Period;
use EV;
use utf8;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {} };
    $serv->reg_cb(
        'iConsoleCommand' => sub {
            my ($this, $iface, $cmd, @args) = @_;
            if ($cmd=~/^t(?:imed)?b(?:an)?$/) {
                if ($args[0] eq 'help' or not defined $args[0]) {
                    $iface->write(<<'HELP');
add [chan] [startmode] [endmode] [range]
del [chan] [n]
del [chan]
list
HELP
;return
                }
                given ($args[0]) {
                    when ('add') {
                        if (!$self->channel($args[1])) {
                            $iface->write("\cC4I am not in channel $args[1], can't apply modes to it!");
                            return;
                        }
                        if (not $self->nick_modes($args[1],$self->nick)->{'o'}) {
                            $iface->write("\cC4I don't have OP (+o) in channel $args[1], I probably shouldn't apply modes to it!");
                            return;
                        }
                        if (inPeriod(0,$args[2]) == -1) {
                            $iface->write("\cC4Invalid range!");
                            return;
                        }
                        push @{$self->{'chans'}->{$args[1]}}, {
                            range => $args[4],
                            start => $args[2],
                            end => $args[3],
                            state => -1
                        };
                    }
                    when ('del') {
                        if ($args[2]) {
                            my $obj=splice @{$self->{'chans'}->{$args[1]}}, $args[2]-1, 1;
                            $iface->write(sprintf('Removed timed mode %s %s start: [%s] end: [%s]',$args[1],$obj->{'range'},$obj->{'start'},$obj->{'end'}));
                        }else{
                            delete $self->{'chans'}->{$args[1]};
                            $iface->write("Removed all timed modes from channel $args[1]");
                        }
                    }
                    when ('list') {
                        $iface->write('Timed modes:');
                        foreach my $c (keys %{$self->{'chans'}}) {
                            my $n=1;
                            foreach my $m (@{$self->{'chans'}->{$c}}) {
                                my $state='???';
                                $state='on ' if $m->{'state'}==1;
                                $state='off' if $m->{'state'}==0;
                                $iface->write(sprintf("#%s %s %s {cur: %s} \cBstart:\cB [%s] \cBend:\cB [%s]", $n++, $c, $m->{'range'}, $state, $m->{'start'}, $m->{'end'}));
                            }
                        }
                    }
                }
            }
        }
    );
    $serv->reg_cb('tick' => sub {
        foreach my $c (keys %{$self->{'chans'}}) {
            my $n=0;
            foreach my $obj (@{$self->{'chans'}->{$c}}) {
                my $rst=inPeriod(time(),$obj->{'range'});
                if ($rst == -1) {
                    warn "TimedBan: Invalid range!\n";
                    splice @{$self->{'chans'}->{$c}}, $n, 1;
                    return;
                }
                if ($obj->{'state'} == -1) {
                    $obj->{'state'}=!$rst;
                }
                my $mode;
                if ($rst == 0 && $obj->{'state'} == 1) {
                    $mode=$obj->{'end'};
                }
                if ($rst == 1 && $obj->{'state'} == 0) {
                    $mode=$obj->{'start'};
                }
                if ($mode && (time - $self->{'lastmsg'}) >= 1) {
                    if (!$self->channel($args[1])) {
                        warn "I am not in channel $args[1], can't apply modes to it!";
                        next;
                    }
                    if (not $self->nick_modes($args[1],$self->nick)->{'o'}) {
                        warn "I don't have OP (+o) in channel $args[1], I probably shouldn't apply modes to it!";
                        next;
                    }
                    $serv->send_srv('MODE', $c, (split / /, $mode));
                    $self->{'lastmsg'}=time;
                    $obj->{'state'}=$rst;
                    return;
                }
                $n++;
            }
        }
    });
    return bless $self, $class;
}

sub hmatch {
    my ($ref, $nick, $mask) = @_;
    my $mstr = $nick . '!' . $mask;
    foreach (@$ref) {
        $_ = MegaHAL::Plugin::TimedBan::CGlobPat->new($_) if not ref $_;
        return 1 if $mstr =~ $_;
    }
    return 0;
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data;
}

sub save {
    my ($self) = @_;
    #return [ $self->{'chans'}, { 'bl' => [ map { ref $_ ? $_->str : $_ } @{ $self->{'bl'} } ] } ];
    return $self->{'chans'};
}

1;

package MegaHAL::Plugin::TimedBan::CGlobPat;
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
