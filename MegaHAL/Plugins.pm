# Plugin management system for MegaHAL
# Copyright 2012 SAL9000 <gosha.tugai@gmail.com>
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
package MegaHAL::Plugins;
use YAML::Any qw(LoadFile DumpFile);
use Carp qw(longmess shortmess carp croak cluck confess);
use Scalar::Util qw(weaken);
our $VERSION = '1.7';

sub new {
    my ($class, $serv) = @_;
    my $self = {
        'plugins'  => {},
        'hooks'    => {},
        'errcb'    => sub { goto &confess },
        'serv'     => $serv,
        'reghooks' => {},
        'commands' => {}
    };
    weaken($self->{'serv'});
    return bless $self, $class;
}

sub _warn ($) {
    my $lm = longmess($_[0]);
    #print STDERR $lm;
    return [ shortmess($_[0]), $lm ];
}

sub reg_cmd {
    my ($self, $cmds, $lvl) = @_;
    if ($self->c_is_pl($lvl)) {
        my $plugin = substr caller($lvl - 1), length("MegaHAL::Plugin::");
        push @{ $self->{'commands'}->{$plugin} }, { 'server' => $self->{'serv'}->name(), 'plugin' => $plugin } if not $self->{'commands'}->{$plugin};
        foreach (@{$cmds}) {
            my $fixed = {%$_};
            $fixed->{'source'}->{'plugin'} = $plugin;
            $fixed->{'source'}->{'server'} = $self->{'serv'}->name();
            push @{ $self->{'commands'}->{$plugin} }, $fixed;
        }
    } else {
        croak "Commands can only be registered from a plugin!\n";
    }
}

sub commands {
    my ($self) = @_;
    return values %{ $self->{'commands'} };
}

sub error_cb {
    my ($self, $cb) = @_;
    $self->{'errcb'} = sub {
        local $@;
        local $!;
        eval { $cb->(@_) };
        if ($@) {
            print STDERR longmess("ERROR IN error_cb!!\n" . $@);
            exit;
        }
        if ($!) {
            print STDERR longmess("ERROR IN error_cb!!\n" . $!);
            exit;
        }
    };
    return 1;
}

sub serv {
    return $_[0]->{'serv'};
}

sub this {
    my ($self) = @_;
    my $pkg = caller;
    if ((substr $pkg, 0, length('MegaHAL::Plugin::')) eq 'MegaHAL::Plugin') {
        return $self->{'plugins'}->{ substr $pkg, length('MegaHAL::Plugin::') };
    } else {
        confess "this() is only callable from plugins!\n";
    }
}

sub load_plugin {
    my ($self, $plugin) = @_;
    $plugin =~ s/^MegaHAL::Plugin:://;
    $plugin =~ s/\.pmc?$//;
    if (defined $self->{'plugins'}->{$plugin}) {
        return _warn "This plugin is already loaded!\n";
    }
    my $file = $plugin;
    $file =~ s/::/\//g;
    my $instance;
    {
        local $@;
        local $!;
        delete $INC{"MegaHAL::Plugin::${file}"};
        do "MegaHAL/Plugin/${file}.pm";
        if ($@) {
            return _warn $@;
        }
        if ($!) {
            return _warn $!;
        }
        eval { $instance = "MegaHAL::Plugin::$plugin"->new($self->{'serv'}); };
        if ($@) {
            return _warn $@;
        }
        if ($!) {
            return _warn $!;
        }
    }
    $self->{'plugins'}->{$plugin} = $instance or bless [], "MegaHAL::Plugin::$plugin";
    if ($self->{'pldata'}->{$plugin}) {
        $instance->load($self->{'pldata'}->{$plugin}) if $instance->can('load');
    }
    return 0;
}

sub list_plugins {
    return keys %{ $_[0]->{'plugins'} };
}

sub list_plugin_hooks {
    my ($self, $plugin) = @_;
    $plugin =~ s/^MegaHAL::Plugin:://;
    $plugin =~ s/\.pmc?$//;
    return grep { 0 + @{ $self->{'hooks'}->{$_}->{$plugin} } > 0 } keys %{ $self->{'hooks'} };
}

sub has_hook {
    my ($self, $hook) = @_;
    return defined($self->{'hooks'}->{$hook});
}

sub list_hook_plugins {
    my ($self, $hook) = @_;
    return keys %{ $self->{'hooks'}->{$hook} };
}

sub is_loaded {
    my ($self, $plugin) = @_;
    $plugin =~ s/^MegaHAL::Plugin:://;
    $plugin =~ s/\.pmc?$//;
    return defined $self->{'plugins'}->{$plugin};
}

sub unload_plugin {
    my ($self, $plugin) = @_;
    $plugin =~ s/^MegaHAL::Plugin:://;
    $plugin =~ s/\.pmc?$//;
    if (not defined $self->{'plugins'}->{$plugin}) {
        return "This plugin is not loaded!\n";
    }
    my $sn = $self->{'serv'}->name();
    foreach (keys %{ $self->{'hooks'} }) {
        print "[$sn] Unregistering $_ for $plugin...\n" if $self->{'hooks'}->{$_}->{$plugin};
        delete $self->{'hooks'}->{$_}->{$plugin};
    }
    foreach (@{ $self->{'reghooks'}->{$plugin} }) {
        $self->{'serv'}->unreg_cb($_);
    }
    delete $self->{'commands'}->{$plugin};
    {
        local $@;
        eval {
            $self->{'plugins'}->{$plugin}->cleanup($self->{'serv'}) if $self->{'plugins'}->{$plugin}->can('cleanup');
            delete $self->{'plugins'}->{$plugin};
        };
        if ($@) {
            return _warn $@;
        }
    }
    return 0;
}

sub new_hook {
    my ($self, $name) = @_;
    confess "Hook $name already exists!\n" if $self->{'hooks'}->{$name};
    $self->{'hooks'}->{$name} = {};
    if (defined wantarray) {    #If context != void
        return sub {
            $self->call_hook($name, @_);
        };
    }
    return 1;
}

sub call_hook {
    my ($self, $hook, @args) = @_;
    confess "No such hook: $name\n" if !$self->{'hooks'}->{$hook};
    foreach (keys %{ $self->{'hooks'}->{$hook} }) {
        local $@;
        local $!;
        my $plugin = $_;
        eval { $_->($self, @args) foreach @{ $self->{'hooks'}->{$hook}->{$plugin} }; };
        if ($@) {
            $self->{'errcb'}->("Error in $hook (${plugin}): $@\n");
        }
        if ($!) {
            $self->{'errcb'}->("Error in $hook (${plugin}): $!\n");
        }
    }
    return 1;
}

sub c_is_pl {
    my ($pkg) = caller(defined($_[1]) ? $_[1] : 1);
    return ((substr $pkg, 0, length("MegaHAL::Plugin::")) eq "MegaHAL::Plugin::");
}

sub reg_cb {
    my ($self, $hook, $cb, $lvl) = @_;
    $lvl = 1 if not $lvl;
    if (!$self->{'hooks'}->{$hook}) {
        confess "No such hook: '$hook'\n";
    }
    if ($self->c_is_pl($lvl)) {    #good!
        my $plugin = substr caller($lvl - 1), length("MegaHAL::Plugin::");
        my $sn = $self->{'serv'}->name();
        print "[$sn] $plugin is hooking $hook\n";
        push @{ $self->{'hooks'}->{$hook}->{$plugin} }, $cb;
        return 1;
    } else {
        confess "Can't register hook callbacks from outside a plugin!\n";
    }
}

sub save {
    my ($self) = @_;
    my $ser = {
        'plist'   => [],
        'plugins' => {}
    };
    foreach (keys %{ $self->{'plugins'} }) {
        push @{ $ser->{'plist'} }, $_;
        $ser->{'plugins'}->{$_} = $self->{'plugins'}->{$_}->save() if $self->{'plugins'}->{$_}->can('save');
    }
    return $ser;
}

sub load {
    my ($self, $data) = @_;
    my $ret;
    foreach (@{ $data->{'plist'} }) {
        my $r = $self->load_plugin($_) unless $self->is_loaded($_);
        if ($r == 0) {
            $self->{'pldata'}->{$_} = $data->{'plugins'}->{$_};
            $self->{'plugins'}->{$_}->load($data->{'plugins'}->{$_}) if $self->{'plugins'}->{$_}->can('load');
        } else {
            $ret->[0] = $r->[0] . "\n";
            $ret->[1] = $r->[1] . "\n";
        }
    }
    return $ret ? $ret : 1;
}
1;
