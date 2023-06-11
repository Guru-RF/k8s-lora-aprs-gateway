#!/usr/bin/perl

use v5.28;
use strict;
use utf8;
use warnings;
use Mojolicious::Lite -signatures;
use Protocol::Redis::XS;
use Mojo::Redis;
use YAML::PP;
use YAML::XS;
use Mojo::JSON::XS;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Exception qw(check);
use Mojo::UserAgent;
use Mojolicious::Plugin::Sentry;
use Config::YAML;
use boolean;
use lib 'lib';

# Config
my $config = Config::YAML->new( config => "config.yaml" );

# Mojo Config
my $mojoconfig = plugin Config => { file => 'mojo.conf' };

app->secrets( [ $config->{'appsecret'} ] );

hook before_dispatch => sub {
    my $self        = shift;
    my $request_url = $self->req->url->to_abs;
    if ( defined $request_url->{'path'}->{'parts'} ) {
        if (   scalar @{ $request_url->{'path'}->{'parts'} } == 0
            || scalar @{ $request_url->{'path'}->{'parts'} } == 1
            || $request_url->{'path'}->{'parts'}[1] ne 'healthz' )
        {
            my $proto = $self->req->headers->header('x-forwarded-proto');

            #            HTTP ONLY APP
            # if ( defined $proto && $proto eq 'http' ) {
            #    $request_url->scheme('https');
            #    $self->res->code(301);
            #    $self->redirect_to($request_url);
            #}
        }
    }

    # securityheaders
    foreach my $key ( keys %{ $config->{'securityheaders'} } ) {
        $self->res->headers->append(
            $key => $config->{'securityheaders'}->{$key} );
    }
};

options '*' => sub {
    my $self = shift;

    $self->respond_to( any => { data => '', status => 200 } );
};

helper whois => sub {
    my $self    = shift;
    my $agent   = $self->req->headers->useragent || 'Anonymous';
    my $ip      = '127.0.0.1';
    my $forward = 'none';
    $ip = $self->req->headers->header('X-Real-IP')
        if $self->req->headers->header('X-Real-IP');
    $ip = $self->req->headers->header('X-Forwarded-For')
        if $self->req->headers->header('X-Forwarded-For');
    return $agent . " (" . $ip . ")";
};

# needs to be adopted to REDIS
## token authentication
#helper auth => sub {
#    my $self = shift;
#    if ( !defined( $config->{tokens}->{ $self->stash('token') } ) ) {
#        app->log->error( 'authentication denied by token ['
#                . $self->stash('token')
#                . '] token unknown' );
#
#        $self->render(
#            text   => 'wrong token',
#            status => 523
#        );
#
#        return;
#    }
#    else {
#        my $appuser = $config->{tokens}->{ $self->stash('token') };
#        app->log->info( '['
#                . __LINE__ . '] ['
#                . $appuser
#                . '] authenticated by token ['
#                . $self->stash('token')
#                . ']' )
#            if $config->{debug} eq 'true';
#        app->log->info( '['
#                . __LINE__ . '] ['
#                . $appuser
#                . '] client info ['
#                . $self->whois
#                . ']' )
#            if $config->{debug} eq 'true';
#
#        return $appuser;
#    }
#};

helper redis_persistent => sub {
    state $r
        = Mojo::Redis->new( "redis://"
            . $config->{redis}->{host} . ":"
            . $config->{redis}->{port}
            . "/1" );
    $r->protocol_class("Protocol::Redis::XS");
};

helper verbose => sub {
    my $self = shift;
    my $data = shift || "no log value";
    chomp($data);

    my $appuser = 'lol';

    # TODO !
    #my $appuser = $config->{tokens}->{ $self->stash('token') };

    app->log->info( '[' . $appuser . '] ' . $data );
};

helper error => sub {
    my $self = shift;
    my $data = shift || "no log value";
    chomp($data);

    my $appuser = 'lol';

    # TODO !
    #my $appuser = $config->{tokens}->{ $self->stash('token') };

    app->log->error( '[' . $appuser . '] ' . $data );
};

helper debug => sub {
    my $self = shift;
    my $data = shift || "no log value";
    chomp($data);

    my $appuser = 'lol';

    # TODO !
    #my $appuser = $config->{tokens}->{ $self->stash('token') };

    app->log->debug( '[' . $appuser . '] ' . $data )
        if $config->{debug} eq 'true';
};

get '/' => sub {
    my $self = shift;
    return $self->render(
        data   => '',
        status => '200'
    );
};

get '/healthz' => sub {
    my $self = shift;

    if ( $self->redis_persistent->db->set( 'ping', 'pong' ) ) {
        return $self->render( json => 'Healty', status => '200' );
    }
    else {
        return $self->render( json => 'Broken', status => '599' );
    }
};

# post aprs lora packet
post '/:token' => sub {
    my $self = shift;

    # reder when we are done
    $self->render_later;

    # authenticate
    #my $appuser = $self->auth;
    #return unless $appuser;

    my $state  = 'ok';
    my $status = '200';
    my $data   = $self->req->json;
    eval {
        $self->redis_persistent->db->rpush('rawdata', $self->req->text);
        $self->verbose("Queued " . $self->req->text);
    };
    check $@ => [
        default => sub {
            $self->verbose($_);
            $data   = 'error';
            $status = '522';
        }
    ];

    return $self->render(
        json   => $data,
        status => $status
    );
    },
    "lora-aprs-gateway";

app->start;
