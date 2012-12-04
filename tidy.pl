use File::Find;
use File::Copy;
use Perl::Tidy;
use threads;
use Thread::Queue;
$|=1;
my $iq=Thread::Queue->new();
my @wrk;
our $len=42;
find({wanted => sub {
    if (-f and -r and /\.(?:(?:p[lm]x?)|t)$/) {
        $_=~s/^\.\///;
        return if $_ eq $0;
        $iq->enqueue($_);
    }
}, no_chdir => 1},'.');
my $n=$iq->pending;
our $pbw=$n > 80 ? 80 : $n;
foreach (1..8) {
    push @wrk,threads->create('worker',$iq,$n);
}
$iq->enqueue(undef) foreach @wrk;
our @ret;
push @ret, $_->join foreach @wrk;
our ($same,$diff,$err)=(0,0,0);
foreach (@ret) {
    if ($_ == 1) {$diff++}
    if ($_ == 0) {$same++}
    if ($_ == -1) {$err++}
}
printf "%-${len}s          \n",(sprintf "%02i changed, %02i unchanged, %02i errors",$diff,$same,$err);
sub worker {
    my ($iq,$n)=@_;
    my @ret;
    while (defined(my $i=$iq->dequeue())) {
        my $name=$i;
        $name=~s/\//::/g if $name=~s/\.pm$//;
        #printf "[%-${len}s] Running perltidy...\n",$name;
        my $err=Perl::Tidy::perltidy(
            source => $i,
            destination => "$i.tdy",
            argv => '-pro=.../.perltidyrc'
        );
        threads::yield();
        if ($err) {
            printf "[%-${len}s] Error.\n",$name;
            push @ret,-1;
        }else{
            #printf "[%-${len}s] Comparing to original...\n",$name;
            if (`diff -q $i $i.tdy`) {
                printf "[%-${len}s] Changed\n",$name;
                copy($i.'.tdy',$i);
                push @ret, 1;
            }else{
                printf "[%-${len}s] Same    [%-${pbw}s]\r",$name,('=' x ((1-(($iq->pending()-1)/$n)) * ($pbw)));
                push @ret, 0;
            }
            unlink($i.".tdy");
        }
    }
    return @ret;
}