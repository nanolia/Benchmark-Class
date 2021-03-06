package Benchmark::Class::Builder;

use strict;
use warnings;
use Class::Accessor::Lite::Lazy (
    new     => 1,
    rw_lazy => [qw/context setups tasks/],
);
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use Carp;
use Module::Load;
use JSON;

my $json = JSON->new->allow_nonref->relaxed(1);

sub _build_context {
    my $self = shift;
    require Benchmark::Class::Context;
    return Benchmark::Class::Context->new;
}

sub _build_setups {
    my $self = shift;
    return [];
}

sub _build_tasks {
    my $self = shift;
    return [];
}

sub parse_options {
    my $self = shift;

    local @ARGV = @_;
    # From 'prove': Allow cuddling the paths with -I, -M
    @ARGV = map { /^(-[IM])(.+)/ ? ($1,$2) : $_ } @ARGV;

    GetOptions(
        'config=s'  => \my $config,
        'planner=s' => \my $planner,
        'setup=s@'  => \my $setups,
        'task=s@'   => \my $tasks,
        'I=s@'      => \my $includes,
        'M=s@'      => \my $modules,
    );

    if (@{ $includes || [] }) {
        require lib;
        lib->import(@$includes);
    }

    for (@{ $modules || [] }) {
        my($module, @import) = split /[=,]/;
        load $module;
    }

    if ($config) {

        open my $config_fh, '<', $config or croak $!;
        my $string = do { local $/; <$config_fh> };
        close $config_fh;
        my $config_param = $json->decode($string);

        my $context = do {
            my $class = $config_param->{context} && $config_param->{context}->{class}
                ? $config_param->{context}->{class}
                : 'Benchmark::Class::Context';
            load $class;
            $class->new(
                $config_param->{context} && $config_param->{context}->{args}
                    ? $config_param->{context}->{args}
                    : ()
            );
        };
        $self->context($context);

        $self->context->config($config_param);

        my $planner_config = $self->context->config->{planner};
        if ($planner_config) {
            load $planner_config->{class};
            $self->context->planner(
                $planner_config->{class}->new($planner_config->{args})
            );
        }

        my $setup_config = $self->context->config->{setups} || [];
        for my $setup (@$setup_config) {
            load $setup;
            push @{ $self->setups }, $setup->new( $setup->{args} );
        }

        my $task_config = $self->context->config->{tasks} || [];
        for my $task (@$task_config) {
            load $task;
            push @{ $self->tasks }, $task->new( $task->{args} );
        }
    }

    if ($planner) {
        load $planner;
        $self->context->planner($planner->new);
    }

    for my $setup (@$setups) {
        # XXX すでに config に setup があるときどうするのがいいか
        # 1. config における setup を破棄
        # 2. 新しい setup を追加

        load $setup;
        push @{ $self->setups }, $setup->new;
    }

    for my $task (@$tasks) {
        # XXX すでに config に task があるときどうするのがいいか
        # 1. config における task を破棄
        # 2. 新しい task を追加

        load $task;
        push @{ $self->tasks }, $task->new;
    }
}

sub run {
    my $self = shift;

    if ( $self->context->planner ) {
        return $self->context->planner->launch($self->context);
    }

    for my $setup ( @{ $self->setups } ) {
        $setup->load($self->context);
    }

    for my $task ( @{ $self->tasks } ) {
        $task->load($self->context);
    }
}

1;
