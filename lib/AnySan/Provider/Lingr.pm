package AnySan::Provider::Lingr;
use 5.008_001;
use strict;
use warnings;

our $VERSION = '0.01';

use parent 'AnySan::Provider';
our @EXPORT = qw/lingr/;
use AnySan;
use AnySan::Receive;
use AnyEvent::WebService::Lingr;
use Coro;
use Coro::Timer;
use Carp;
use Try::Tiny;

sub lingr {
    my (%config) = @_;

    my $self = __PACKAGE__->new(
        client => undef,
        config => \%config,
    );

    my $client = AnyEvent::WebService::Lingr->new(
        user     => $config{user},
        password => $config{password},
        timeout  => $config{timeout} || 100,
    );
    $self->{client} = $client;
    $self->{config}{auto_reconnect} ||= 1;
    $self->{config}{reconnect_interval} ||= 60;
    $self->{config}{session_create_cb} ||= sub {};
    my $session = $self->{config}{session};

    async {
        my $is_continue = 1;
        while ( $is_continue ) {
            try {
                if ( $session ) {
                    try {
                        $self->_verify_session($session);
                    }
                    catch {
                        $self->_create_session;
                    };
                }
                else {
                    $self->_create_session;
                }

                my $rooms = $self->{config}{rooms} || do {
                    my $json = $self->_request("user/get_rooms");
                    $json->{rooms};
                };

                my $json = $self->_request("room/subscribe", room => join(",", @$rooms));

                $self->_observe($json->{counter});
            }
            catch {
                warn $_;
                try {
                    $self->_destory_session;
                }
                catch {
                    $self->{client}{session} = undef;
                    warn $_;
                }
                finally {
                    $session = undef;
                };

                if ( $self->{config}{auto_reconnect} ) {
                    Coro::Timer::sleep $self->{config}{reconnect_interval};
                }
                else {
                    $is_continue = 0;
                }
            };
        }
    };
}

sub event_callback {
    my ($self, $receive, $type, @args) = @_;

    if ( $type eq "reply" ) {
        $self->{client}->request("room/say",
            room     => $receive->attribute->{obj}{room},
            nickname => $self->{nickname},
            text     => $args[0],
            sub {},
        );
    }
}

sub send_message {
    my ($self, $message, %args) = @_;
    $self->{client}->request("room/say",
        room     => $args{room},
        nickname => $args{nickname} || $self->{nickname},
        text     => $message,
        sub {},
    );
}

sub _create_session {
    my ($self) = @_;
    $self->{client}->create_session(Coro::rouse_cb);
    my ($hdr, $json, $reason) = Coro::rouse_wait;
    _check_response($hdr, $json, $reason);

    $self->{config}{session_create_cb}->($json);
    $self->{nickname} = $json->{nickname};

    $json;
}

sub _destory_session {
    my ($self) = @_;
    $self->{client}->destroy_session(Coro::rouse_cb);
    my ($hdr, $json, $reason) = Coro::rouse_wait;
    _check_response($hdr, $json, $reason);

    $self->{nickname} = undef;
}

sub _verify_session {
    my ($self, $session) = @_;
    $self->{client}->verify_session($session, Coro::rouse_cb);
    my ($hdr, $json, $reason) = Coro::rouse_wait;
    _check_response($hdr, $json, $reason);

    $self->{nickname} = $json->{nickname};

    $json;
}

sub _request {
    my ($self, $method, %params) = @_;
    $self->{client}->request($method, %params, Coro::rouse_cb);
    my ($hdr, $json, $reason) = Coro::rouse_wait;
    _check_response($hdr, $json, $reason);

    $json;
}

sub _observe {
    my ($self, $counter) = @_;

    while (1) {

        $self->{client}->request("event/observe", counter => $counter, Coro::rouse_cb);
        my ($hdr, $json, $reason) = Coro::rouse_wait;

        next if $reason eq "Operation timed out";

        _check_response($hdr, $json, $reason);

        for my $event (@{$json->{events}} ) {

            my $type = $event->{message} ? "message" : "presence";

            my $receive; $receive = AnySan::Receive->new(
                provider => "lingr",
                event => $type,
                message => $event->{$type}{text},
                nickname => $self->{nickname},
                from_nickname => $event->{$type}{nickname},
                attribute => {
                    obj => $event->{$type}
                },
                cb => sub { $self->event_callback($receive, @_) },
            );
            AnySan->broadcast_message($receive);

        }
        $counter = $json->{counter} if defined $json->{counter};
    }
}

sub _check_response {
    my ($hdr, $json, $reason) = @_;
    croak $reason unless $json;
    croak $json->{code} . " : " . $json->{detail} unless $json->{status} eq "ok";
}

1;
__END__

=head1 NAME

AnySan::Provider::Lingr - Perl extention to do something

=head1 VERSION

This document describes AnySan::Provider::Lingr version 0.01.

=head1 SYNOPSIS

    use AnySan::Provider::Lingr;

=head1 DESCRIPTION

# TODO

=head1 INTERFACE

=head2 Functions

=head3 C<< hello() >>

# TODO

=head1 DEPENDENCIES

Perl 5.8.1 or later.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

<<YOUR NAME HERE>> E<lt><<YOUR EMAIL ADDRESS HERE>>E<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012, <<YOUR NAME HERE>>. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
