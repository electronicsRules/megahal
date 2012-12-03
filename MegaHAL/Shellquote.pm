package MegaHAL::Shellquote;
use Carp qw(carp croak cluck confess);
use Text::Balanced qw(extract_multiple extract_delimited);

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
    my @fields=extract_multiple($text,[
        {SQ => sub {extract_delimited($_[0],q{''})}},
        {DQ => sub {extract_delimited($_[0],q{""})}},
        {BQ => sub {extract_delimited($_[0],q{``})}}
    ]);
    my @ret;
    my $was_spc;
    my $lwspc;
    foreach (@fields) {
        my $r=ref $_;
        my ($s,@other);
        if ($r) {
            $s=$$_;
            $s=~s/^['"`](.*)['"`]$/$1/;
            if ($r eq 'BQ') {
                $s=($self->{'bqcb'}->($s))[0];
            }
        }else{
            if ($_=~/^ +/) {
                $_=~/^( +)[^ ]?/;
                $was_spc=$1;
                $lwspc=$1 if $was_spc ne $_;
            }
            s/^ *([^ ].*[^ ]?) *$/$1/;
            ($s,@other)=split / /, $_;
        }
        if (!$lwspc && $ret[-1]) {
            $ret[-1].=$lwspc.$s;
        }elsif ($s) {
            push @ret, $s;
        }
        push @ret,@other;
        $lwspc=$was_spc;
        $was_spc=0;
    }
    return @ret;
}
1;
