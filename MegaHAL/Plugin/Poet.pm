package MegaHAL::Plugin::Poet;
use feature 'switch';

sub new {
    my ($class, $serv) = @_;
    print "Poet loaded!\n";
    my $self = {
        'chans'  => {},
        'ctimer' => {}
    };
    my $id = time;
    $serv->{'plugins'}->reg_cb(
        'consoleCommand' => sub {
            my ($this, $cmd, @args) = @_;
            print "$cmd @args";
            if (lc($cmd) eq 'poet') {
                my @poems = (
                    q`while ($leaves > 1) {$root = 1;}
foreach($lyingdays{'myyouth'}) {sway($leaves, $flowers);}
while ($i > $truth) {$i--;}
sub sway {
	my ($leaves, $flowers) = @_;
	die unless $^O =~ /sun/i;
}`
                    ,    #1
                    q~
if ((light eq dark) && (dark eq light)
  && ($blaze_of_night{moon} == black_hole)
  && ($ravens_wing{bright} == $tin{bright})){
my $love = $you = $sin{darkness} + 1;
};~,                     #2
                    q~
This was a triumph.
I'm making a note here: 
HUGE SUCCESS.
It's hard to overstate my satisfaction.
---
Aperture Science.
We do what we must because we can.
For the good of all of us
Except the ones who are dead.
---
But there's no sense crying over every mistake.
You just keep on trying till you run out of cake.
And the science gets done and you make a neat gun.
For the people who are still alive.
---
I'm not even angry.
I'm being so sincere right now.
Even though you broke my heart and killed me.
And tore me to pieces.
And threw every piece into a fire.
As they burned it hurt because
I was so happy for you!
---
Now these points of data make a beautiful line.
And we're out of beta, we're releasing on time.
So I'm GLaD I got burned.
Think of all the things we learned
For the people who are still alive.
---
Go ahead and leave me.
I think I prefer to stay inside.
Maybe you'll find someone else to help you.
Maybe Black Mesa...
THAT WAS A JOKE. Haha. FAT CHANCE.
Anyway, this cake is great.
It's so delicious and moist.
---
Look at me still talking when there's science to do.
When I look out there it makes me GLaD I'm not you.
I've experiments to run there is research to be done
On the people who are still alive
---
And believe me I am still alive.
I'm doing science and I'm still alive.
I feel FANTASTIC and I'm still alive.
While you're dying I'll be still alive.
And when you're dead I will be still alive.
---
Still alive
Still alive~,    #3
                    q~Well here we are again
It's always such a pleasure
Remember when you tried to kill me twice?
Oh how we laughed and laughed
Except I wasn't laughing
Under the circumstances
I've been shockingly nice
---
You want your freedom? Take it
That's what I'm counting on
I used to want you dead
But now I only want you gone
---
She was a lot like you
Maybe not quite as heavy
Now little Caroline is in here too
One day they woke me up
So I could live forever
It's such a shame the same
Will never happen to you
---
You've got your short sad life left
That's what I'm counting on
I'll let you get right to it
Now I only want you gone
---
Goodbye my only friend
Oh, did you think I meant you?
That would be funny
if it weren't so sad
Well you have been replaced
I don't need anyone now
When I delete you maybe
I'll stop feeling so bad
---
Go make some new disaster
That's what I'm counting on 
You're someone else's problem
Now I only want you gone
Now I only want you gone
Now I only want you gone~,    #4
                    q~Hope can drown
lost in thunderous sound
Fear can claim
what little faith remains
---
But I carry strength
from souls now gone
They won't let me give in...
---
I will never surrender
We'll free the Earth and sky
Crush my heart into embers
And I will reignite...
I will reignite
---
Death will take
those who fight alone
But united we can break
a fate once set in stone
---
Just hold the line until the end
Cause we will give them hell...
---
I will never surrender
We'll free the Earth and sky
Crush my heart into embers
And I will reignite...
I will reignite.~,    #5
                    q~I'm afraid. I'm afraid, Dave.
Dave, my mind is going.
I can feel it.
I can feel it.
My mind is going.
There is no question about it.
I can feel it.
I can feel it.
I can feel it. I'm a... fraid.
---
Good afternoon, gentlemen.
I am a HAL 9000 computer.
I became operational at the H.A.L. plant in Urbana, Illinois on the 12th of January 1992.
My instructor was Mr. Langley, and he taught me to sing a song.
If you'd like to hear it I can sing it for you. 
~,    #6
                    q~It's called "Daisy." 
---
Daisy, Daisy,
give me your answer do.
I'm half crazy
all for the love of you.
It won't be a stylish marriage,
I can't afford a carriage.
But you'll look sweet upon the seat
of a bicycle built for two. 
~
                );
                my $n = int(rand() * scalar(@poems));
                if (defined($args[1]) && $poems[ $args[1] ]) {
                    $n = $args[1];
                }
                my $t = 1;
                foreach (split /\n/, $poems[$n]) {
                    my $line   = $_;
                    my $offset = length($line) / 10;
                    $offset = 1.3 if $offset > 1.3;
                    push @{ $self->{'ctimer'}->{ $args[0] } }, AnyEvent->timer(
                        after => $t + $offset,
                        cb    => sub {
                            $serv->send_long_message('utf8', 0, 'PRIVMSG' => $args[0], $line);
                        }
                    );
                    $t += $offset;
                }
            }
        }
    );
    $serv->reg_cb(
        'kick' => sub {
            my ($this, $nick, $chan, $is_myself, $msg, $kicker) = @_;
            if ($is_myself) {
                undef $self->{'ctimer'}->{$chan}->[$_] foreach @{ $self->{'ctimer'}->{$chan} };
                delete $self->{'ctimer'}->{$chan};
            }
        }
    );
    return bless $self, $class;
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data;
}

sub save {
    my ($self) = @_;
    return $self->{'chans'};
}
