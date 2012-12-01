package MegaHAL::ACL;
use DBI;
use Digest::SHA qw(sha512);
our $db;
our %sth;

sub init {
    $db = DBI->connect("dbi:SQLite:dbname=./ACL.db", "", "");
    $db->do(
        'CREATE TABLE IF NOT EXISTS ircacl
(
server varchar(255) NOT NULL,
nick varchar(255) NOT NULL,
channel varchar(255),
plugin varchar(255),
node varchar(255) NOT NULL
)'
    );
    $db->do(
        'CREATE TABLE IF NOT EXISTS acl
(
user varchar(255) NOT NULL,
plugin varchar(255),
node varchar(255) NOT NULL
)'
    );
    $db->do(
        'CREATE TABLE IF NOT EXISTS user
(
user varchar(255) NOT NULL PRIMARY KEY,
pass char(64) NOT NULL
)'
    );
    $sth{'new_user'}    = $db->prepare('INSERT INTO user(user,pass) VALUES (?,?)');
    $sth{'auth_user'}   = $db->prepare('SELECT pass FROM user WHERE user=?');
    $sth{'exists_user'} = $db->prepare('SELECT user FROM user WHERE user=?');
    $sth{'chpass_user'} = $db->prepare('UPDATE user SET pass=? WHERE user=?');
    $sth{'del_user'}    = $db->prepare('DELETE FROM user WHERE user=?');

    $sth{'add_acl'}      = $db->prepare('INSERT INTO acl(user,plugin,node) VALUES (?,?,?)');
    $sth{'get_nodes'}    = $db->prepare('SELECT plugin,node FROM acl WHERE user=?');
    $sth{'has_node'}     = $db->prepare('SELECT user FROM acl WHERE user=? AND plugin=? AND node=?');
    $sth{'del_acl'}      = $db->prepare('DELETE FROM acl WHERE user=? AND plugin=? AND node=?');
    $sth{'del_acl_user'} = $db->prepare('DELETE FROM acl WHERE user=?');

    $sth{'add_ircacl'}      = $db->prepare('INSERT INTO ircacl(server,nick,plugin,node,channel) VALUES (?,?,?,?,?)');
    $sth{'get_ircnodes'}    = $db->prepare('SELECT plugin,node,channel FROM ircacl WHERE server=? AND nick=?');
    $sth{'has_ircnode'}     = $db->prepare('SELECT nick,channel FROM ircacl WHERE server=? AND nick=? AND plugin=? AND node=?');
    $sth{'del_ircnode'}     = $db->prepare('DELETE FROM ircacl WHERE server=? AND nick=? AND plugin=? AND node=?');
    $sth{'del_chanircnode'} = $db->prepare('DELETE FROM ircacl WHERE server=? AND nick=? AND channel=? AND plugin=? AND node=?');
}

sub new_user {
    my ($user, $pass) = @_;
    return $sth{'new_user'}->execute($user, sha512($pass));
}

sub auth_user {
    my ($user, $pass) = @_;
    $sth{'auth_user'}->execute($user) or return 0;
    my ($cpass) = $sth{'auth_user'}->fetchrow_array();
    if ($cpass eq sha512($pass)) {
        return 1;
    }
    return 0;
}

sub exists_user {
    my ($user) = @_;
    $sth{'exists_user'}->execute($user) or return 0;
    return scalar(@{ $sth{'exists_user'}->fetchall_arrayref() });
}

sub chpass_user {
    my ($user, $pass) = @_;
    return $sth{'chpass_user'}->execute(sha512($pass), $user);
}

sub del_user {
    my ($user) = @_;
    return $sth{'del_user'}->execute($user) && $sth{'del_acl_user'}->execute($user);
}

sub add_acl {
    my ($user, $plugin, $node) = @_;
    return $sth{'add_acl'}->execute($user, $plugin, $node);
}

sub get_nodes {
    my ($user) = @_;
    $sth{'get_nodes'}->execute($user) or return 0;
    return $sth{'get_nodes'}->fetchall_arrayref();
}

sub has_node {
    my ($user, $plugin, $node) = @_;
    $sth{'has_node'}->execute($user, $plugin, $node) or return 0;
    return scalar(@{ $sth{'has_node'}->fetchall_arrayref() });
}

sub del_acl {
    my ($user, $plugin, $node) = @_;
    return $sth{'del_acl'}->execute($user, $plugin, $node);
}

sub clear_acl {
    my ($user) = @_;
    return $sth{'del_acl_user'}->execute($user);
}

sub add_ircacl {
    my ($server, $nick, $plugin, $node, $channel) = @_;
    return $sth{'add_ircacl'}->execute($server, $nick, $plugin, $node, $channel);
}

sub get_ircnodes {
    my ($server, $nick) = @_;
    $sth{'get_ircnodes'}->execute($server, $nick) or return 0;
    return $sth{'get_ircnodes'}->fetchall_arrayref();
}

sub has_ircnode {
    my ($server, $nick, $plugin, $node, $channel) = @_;
    $sth{'has_ircnode'}->execute($server, $nick, $plugin, $node);
    my $aref = $sth{'has_ircnode'}->fetchall_arrayref();
    if ($channel) {
        return scalar(grep { not defined $_->[2] or $_->[2] eq $channel } @$aref);
    } elsif (defined $channel) {
        return scalar(grep { not defined $_->[2] } @$aref);
    } else {
        return $aref;
    }
}

sub del_ircacl {
    my ($server, $nick, $plugin, $node) = @_;
    return $sth{'del_ircnode'}->execute($server, $nick, $plugin, $node);
}

sub del_chanircacl {
    my ($server, $nick, $plugin, $node, $channel) = @_;
    return $sth{'del_ircnode'}->execute($server, $nick, $channel, $plugin, $node);
}
1;
