package MegaHAL::Shellquote;
use Carp qw(carp croak cluck confess);

sub new {
    my ($class, $bqcb) = @_;
    my $self = { 'bqcb' => $bqcb };
    return bless $self, $class;
}

sub bqcb {
    my ($self, $bqcb) = @_;
    $self->{'bqcb'} = $bqcb;
}

sub split {
    my ($self, $text) = @_;
    my @prt = split //, $text;
    my @ret;
    my $qt;
    my $acc;
    my $bqacc;
    my $esc;
    foreach (@prt) {
        if (!$esc) {
            if ($_ eq '\\') {
                $esc = 1;
            } elsif ($_ eq "'") {
                if ($qt eq 's') {
                    $qt = '';
                } elsif ($qt eq '') {
                    $qt = 's';
                } else {
                    $acc .= "'";
                }
            } elsif ($_ eq '"') {
                if ($qt eq 'd') {
                    $qt = '';
                } elsif ($qt eq '') {
                    $qt = 'd';
                } else {
                    $acc .= '"';
                }
            } elsif ($_ eq '`') {
                if ($qt eq 'b') {
                    $qt = '';
                    if ($self->{'bqcb'}) {
                        $bqacc .= $self->{'bqcb'}->($acc);
                    } else {
                        $bqacc .= '`' . $acc . '`';
                    }
                    $acc   = $bqacc;
                    $bqacc = '';
                } elsif ($qt eq '') {
                    $qt    = 'b';
                    $bqacc = $acc;
                    $acc   = '';
                } else {
                    $acc .= '`';
                }
            } elsif ($qt eq '' and $_ eq ' ') {
                push @ret, $acc;
                $acc = '';
            } else {
                $acc .= $_;
            }
        } elsif ($esc == 2) {
            if (/[A-Za-z]/) {
                $acc .= chr(ord(uc($_)) - 65);
            } else {
                $acc .= '\\c' . $_;
            }
            $esc = 0;
        } else {
            if ($qt eq 'd' and $_ eq 'c') {    #\cX
                $esc = 2;
            } elsif ($qt eq 's' and $_ ne "'" and $_ ne '\\' and $_ ne '"' and $_ ne '`') {
                $acc .= '\\' . $_;
                $esc = 0;
            } else {
                $acc .= $_;
                $esc = 0;
            }
        }
    }
    return @ret, $acc;
}
1;
