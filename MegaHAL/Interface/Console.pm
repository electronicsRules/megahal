package MegaHAL::Interface::Console;
use base qw(MegaHAL::Interface);
use Term::ANSIColor;

sub _write {
    my $self = shift;
    chomp $_[0];
    print ::CONOUT $_[0], color('reset');
}
sub type        {"Console"}
sub source      {"Console"}
sub atype       {'always'}
sub ansicolorok {1}

sub colour {
    (   "\cB" => color('bold'),
        "\cC" => \&_colour,
        "\cU" => color('underline'),
        "\cR" => color('reverse'),
        "\c_" => color('underline'),
        "\c]" => '',                   #italics
        "\cO" => color('reset')
    );
}
our %fgc = (
    0  => color('white'),
    1  => color('black'),
    2  => color('blue'),
    3  => color('green'),
    4  => color('bright_red'),
    5  => color('red'),
    6  => color('magenta'),
    7  => color('yellow'),
    8  => color('bright_yellow'),
    9  => color('bright_green'),
    10 => color('cyan'),
    11 => color('bright_cyan'),
    12 => color('bright_blue'),
    13 => color('bright_magenta'),
    14 => '',                        #gray
    15 => ''                         #light gray
);
our %bgc = (
    0  => '',                           #light gray
    1  => color('on_black'),
    2  => color('on_blue'),
    3  => color('on_green'),
    4  => color('on_bright_red'),
    5  => color('on_red'),
    6  => color('on_magenta'),
    7  => color('on_yellow'),
    8  => color('on_bright_yellow'),
    9  => color('on_bright_green'),
    10 => color('on_cyan'),
    11 => color('on_bright_cyan'),
    12 => color('on_bright_blue'),
    13 => color('on_bright_magenta'),
    14 => color('on_black'),
    15 => ''                            #light gray
);

sub _colour {
    my ($str) = @_;
    my ($fg, $bg) = split ',', (substr $str, 1);
    return $fgc{$fg} . $bgc{$bg};
}
1;
