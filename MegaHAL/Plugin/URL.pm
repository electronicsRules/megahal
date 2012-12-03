package MegaHAL::Plugin::URL;
use feature 'switch';
use AnyEvent::HTTP;
use JSON::XS;
use Date::Format;
use YAML::Any qw(Dump);
use Time::HiRes qw(time);
use XML::Bare;
use MegaHAL::Cache qw(cache_http);

sub new {
    my ($class, $serv) = @_;
    my $self = { 'chans' => {} };
    bless $self, $class;
    $serv->reg_cb(
        'publicmsg' => sub {
            my ($this, $nick, $ircmsg) = @_;
            #print "Callback $id\n";
            #print Dumper($ircmsg)."\n";
            my ($modes, $nick, $ident) = $this->split_nick_mode($ircmsg->{'prefix'});
            my $command = $ircmsg->{'command'};
            my $chan    = lc($ircmsg->{'params'}->[0]);
            my $message = $ircmsg->{'params'}->[1];
            my $mstr    = join '', keys %{$modes};
            return if $command ne 'PRIVMSG' or $this->is_my_nick($nick);
            #print "1 $chan $message\n";
            if ($self->{'chans'}->{$chan}) {
                #print "2 $chan $message\n";
                my @urls = ($message =~ m#https?://([^ ]+)#g);
                my $n = 0;
                $n = 1 if scalar(@urls) > 1;
                foreach (@urls) {
                    my $prefix = "#$n " if $n > 0;
                    $n++;
                    my $url = $_;
                    #print "3 $chan $url\n";
                    given ($url) {
                        when (m`^(?:[a-zA-Z0-9-_]+\.deviantart\.com/(?:art/[^ ]+)|(?:[^# ]+#/d[^ ]+))|(?:fav\.me/[^ ]+)$`) {
                            if ($self->{'chans'}->{$chan}->{'deviantart'}) {
                                cache_http(
                                    'http://backend.deviantart.com/oembed?url=' . $url,
                                    undef,
                                    60 * 60 * 12,
                                    sub {
                                        my ($data) = @_;
                                        return 0 if not $data;
                                        my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                                        if ($data =~ /^404 Not Found \(/) {
                                            $serv->msg($chan, sprintf "${prefix}${C}4No such deviation, or not a deviation URL!");
                                            return 0;
                                        }
                                        my $o;
                                        eval { $o = decode_json($data); };
                                        if ($@) {
                                            print $@;
                                            return 0;
                                        }
                                        my $favme;
                                        #if ($url!~m#^(?:http://)?fav\.me#) {
                                        #$url=~m##;
                                        #$favme="${U}http://fav.me/$1${O} - " ;
                                        #}
                                        $serv->msg($chan, (sprintf("%s%s${C}2${B}%s${O} by ${C}9${B}%s${O} [${C}6%s${O}]", $prefix, $favme, $o->{'title'}, $o->{'author_name'}, $o->{'category'})));
                                        return 1;
                                    }
                                );
                            }
                        }
                        when (m`^(?:www\.)?fimfiction.net\/story\/(\d+)`) {
                            if ($self->{'chans'}->{$chan}->{'fimfic'}) {
                                cache_http(
                                    'http://fimfiction.net/api/story.php?story=' . $1,
                                    "fimfic:$1",
                                    60 * 30,
                                    sub {
                                        my ($data) = @_;
                                        return 0 if not $data;
                                        my $dat;
                                        eval { $dat = decode_json($data); };
                                        my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                                        if ($dat->{error}) {
                                            $serv->msg($chan, "${prefix}${C}4fimfiction.net API error: " . $dat->{error});
                                            return 0;
                                        }
                                        if ($@) {
                                            print $@;
                                            return 0;
                                        }
                                        my $s    = $dat->{'story'};
                                        my %catc = qw(
                                          Ad 9
                                          Al 14
                                          Co 8
                                          Cr 11
                                          Da 5
                                          Hu 14
                                          Ra 12
                                          Ro 6
                                          Sa 4
                                          Sl 12
                                          Tr 7
                                        );
                                        $catc{'Co'} = "7\cB";
                                        my ($fcl, $sfcl, $scl, $sccl) = ('', '', '', '');
                                        foreach (sort { $a cmp $b } keys %{ $s->{'categories'} }) {
                                            my $c = $s->{'categories'}->{$_};
                                            if ($c) {
                                                $fcl .= $_ . ',';
                                                my $sc = substr $_, 0, 2;
                                                $sfcl .= "\cC" . $catc{$sc} . $_ . "\cO,";
                                                $scl  .= $sc;
                                                $sccl .= "\cC" . $catc{$sc} . $sc . "\cO";
                                            }
                                        }
                                        chop $fcl;
                                        chop $sfcl;
                                        my $oa = sprintf("%s${C}2${B}%s${O} by ${C}9${B}%s${O} [${C}6%s;%s;%sc;%sw;%sv${O}] [${C}6${B}%s${O}] [${C}3+%s${C}4-%s${O}] [%s] ", $prefix, $s->{'title'}, $s->{'author'}->{'name'}, $s->{'content_rating_text'}, $s->{'status'}, metric($s->{'chapter_count'}), metric($s->{'words'}), metric($s->{'total_views'}), time2str('%H%MGMT %d%b%y', $s->{'date_modified'}), metric($s->{'likes'}), metric($s->{'dislikes'}), $sfcl);
                                        #Ballpark guess... might be three lines every now and then
                                        my $sdesc = shorten(remove_bbcode($s->{'description'}));
                                        my $mlen  = 841 - 15;
                                        if (length($sdesc) >= ($mlen - 5) - length($oa)) {
                                            $sdesc = substr($sdesc, 0, ($mlen - 5) - length($oa)) . '[...]';
                                        }
                                        $oa .= $sdesc;
                                        $serv->msg($chan, $oa);
                                        return 1;
                                    }
                                );
                            }
                        }
                        when (m`^derpiboo(?:(?:\.ru)|(?:ru\.org))/(\d+)(?:\?.*)?$`) {
                            if ($self->{'chans'}->{$chan}->{'derpibooru'} && $1) {
                                cache_http(
                                    'http://derpiboo.ru/' . $1 . '.json',
                                    "derpibooru:$1",
                                    60 * 60,
                                    sub {
                                        my ($data) = @_;
                                        return 0 if not $data;
                                        my $o;
                                        eval { $o = decode_json($data); };
                                        if ($@) {
                                            print $@;
                                            return 0;
                                        }
                                        my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                                        $o->{'tags'} =~ s/, /,/g;
                                        $o->{'tags'} = join ',', sort { $b =~ /^artist:/ <=> $a =~ /^artist:/ } sort { $b =~ /(?:(?:foalcon)|(?:suggestive)|(?:grimdark)|(?:questionable))/ <=> $a =~ /(?:(?:foalcon)|(?:suggestive)|(?:grimdark)|(?:questionable))/ } sort { $b =~ /^spoiler:/ <=> $a =~ /^spoiler:/ } split /,/, $o->{'tags'};
                                        $o->{'tags'} =~ s/artist:([^ ,]+?),/artist:${C}06${1}${C}12${B}${B},/g;
                                        $o->{'tags'} =~ s/spoiler:([^ ,]+?),/spoiler:${C}04${1}${C}12${B}${B},/g;
                                        $o->{'tags'} =~ s/((?:foalcon)|(?:suggestive)|(?:grimdark)|(?:questionable)),/${C}05${1}${C}12${B}${B},/g;
                                        $serv->msg($chan, (sprintf("%s#%s (%s x %s) by ${C}9${B}%s${O} [${C}3+%s${C}4-%s${O}] [${C}12%s${O}]", $prefix, $o->{'id_number'}, $o->{'width'}, $o->{'height'}, $o->{'uploader'}, $o->{'upvotes'}, $o->{'downvotes'}, $o->{'tags'})));
                                        return 1;
                                    }
                                );
                            }
                        }
                        when (m`^(?:www\.)?youtu(?:(?:be\.com)|(?:\.be))/`) {
                            if ($self->{'chans'}->{$chan}->{'youtube'}) {
                                $url =~ /[?&]v=([a-zA-Z0-9-_]+)/;
                                $url =~ /youtu\.be\/([a-zA-Z0-9-_]+)/;
                                my $id = $1;
                                cache_http(
                                    'http://gdata.youtube.com/feeds/api/videos/' . $id . '?v=2',
                                    "youtube:$id",
                                    60 * 60,
                                    sub {
                                        my ($data) = @_;
                                        my $xb = new XML::Bare(text => $data);
                                        my $root = $xb->parse();
                                        if ($root->{errors}) {
                                            $serv->msg($chan, "${prefix}${C}4YouTube API error: " . $root->{errors}->{error}->{internalReason}->{value});
                                            return 0;
                                        }
                                        my $e    = $root->{entry};
                                        my $date = $e->{updated}->{value};
                                        #my $title=$e->{'media:group'}->{'media:title'}->{value};
                                        my $title    = $e->{title}->{value};
                                        my $duration = strtime($e->{'media:group'}->{'yt:duration'}->{seconds}->{value});
                                        my $desc     = $e->{'media:group'}->{'media:description'}->{value};
                                        my $upv      = metric($e->{'yt:rating'}->{'numLikes'}->{value});
                                        my $downv    = metric($e->{'yt:rating'}->{'numDislikes'}->{value});
                                        my $cat      = join ",", grep {$_} map { $_->{'label'}->{'value'} } @{ $e->{category} };
                                        $cat =~ s/ ?&amp; ?/&/g;
                                        my $author = $e->{author}->{name}->{value};
                                        my $ncomm  = metric($e->{'gd:comments'}->{'gd:feedLink'}->{countHint}->{value});
                                        my $views  = metric($e->{'yt:statistics'}->{viewCount}->{value});
                                        my $favs   = metric($e->{'yt:statistics'}->{favoriteCount}->{value});
                                        my $cban   = join ",", map { $_->{value} } grep { $_->{type} eq 'country' } (ref $e->{'media:group'}->{'media:restriction'} eq 'ARRAY' ? @{ $e->{'media:group'}->{'media:restriction'} } : $e->{'media:group'}->{'media:restriction'});
                                        my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                                        my $sdesc = shorten($desc);
                                        my $oa    = sprintf "%s${C}2${B}%s${O} by ${C}9${B}%s${O} [%s] [%s] [${C}3+%s${C}4-%s${O},%sc,%sv,%sf]%s ", $prefix, $title, $author, $duration, $cat, $upv, $downv, $ncomm, $views, $favs, ($cban ? " ${C}5$cban${O} " : '');
                                        my $mlen  = 841 - 15;
                                        if (length($sdesc) >= ($mlen - 5) - length($oa)) {
                                            $sdesc = substr($sdesc, 0, ($mlen - 5) - length($oa)) . '[...]';
                                        }
                                        $oa .= $sdesc;
                                        $serv->msg($chan, $oa);
                                        return 1;
                                    }
                                );
                            }
                        }
                        when (m`static\.fjcdn\.com`) {
                            if ($self->{'chans'}->{$chan}->{'nofjcdn'}) {
                                my ($B, $C, $U, $O, $V) = ("\cB", "\cC", "\c_", "\cO", "\cV");
                                $serv->msg($chan, sprintf("%s%s: ${B}Please don't link to images from Funnyjunk directly (${C}12${U}static.fjcdn.com/...${U}${C}), since the link won't work for anyone else. Link the page where you saw the image (${C}12${U}funnyjunk.com/...${U}${C}), instead.", $prefix, $nick));
                            }
                        }
                    }
                }
            }
        }
    );
    return $self;
}

sub load {
    my ($self, $data) = @_;
    $self->{'chans'} = $data;
}

sub save {
    my ($self) = @_;
    return $self->{'chans'};
}

sub metric {
    my ($n) = @_;
    my @suff = ('', 'K', 'M', 'G', 'T');
    while ($n > 1000) {
        $n /= 1000;
        shift @suff;
    }
    if ($n < 10) {
        $n = int($n * 10) / 10;
    } else {
        $n = int($n);
    }
    return $n . $suff[0];
}

sub strtime {
    my ($n) = @_;
    if ($n < 60) {
        return sprintf("0:%02i", $n);
    } elsif ($n < 60 * 60) {
        return sprintf("%02i:%02i", int($n / 60), $n % 60);
    } else {
        return sprintf("%02i:%02i:%02i", int($n / 3600), (($n / 60) % 60), $n % 60);
    }
}

sub shorten {
    my ($str) = @_;
    return if not $str;
    $str =~ s/[\r\n\t]+/;/g;
    $str =~ s/ *([.,!?;()\[\]{}~=_-]+) */$1/g;
    $str =~ s/([ ;-]){2,}/$1/g;
    #horizontal ellipsis
    $str =~ s/\.\.+/\N{U+2026}/g;
    $str =~ s/([?!.:]);/$1/g;
    $str =~ s#(?:http://)?(?:www\.)?fimfiction.net/story/(\d+)(?:\/[a-zA-Z0-9%-]*)?#http://fimfiction.net/story/$1#g;
    return $str;
}

sub remove_bbcode {
    my ($str) = @_;
    $str =~ s#\[url=[^\]]+\](.*?)\[/url\]#$1#g;
    $str =~ s#\[/?[biu]\]##g;
    $str =~ s#\[color=[^\]]+\]##g;
    $str =~ s#\[/color\]##g;
    return $str;
}
1;
