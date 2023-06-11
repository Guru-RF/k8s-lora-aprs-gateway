#!/usr/bin/perl

use v5.10;
use strict;
use utf8;
use Cpanel::JSON::XS;
use JSON::MaybeXS;
use Config::YAML;
use Redis::Fast;
use Sys::Hostname;
use Math::Round qw(nearest);
use POSIX qw(strftime);
use Math::Round qw(:all);
use Ham::APRS::IS;
use Ham::APRS::FAP qw(parseaprs);

$| = 1;    # Unbuffered output

# JSON Config (pretty can go to 0 ... easier to debug)
my $json = JSON::MaybeXS->new( utf8 => 1, pretty => 0 )->allow_nonref;

# YAML based config
my $config = Config::YAML->new( config => "config.yaml" );

# Connect to Redis
my $redis = Redis::Fast->new(
    reconnect => 2,
    every     => 100,
    server    => $config->{redis}->{host} . ":" . $config->{redis}->{port},
    encoding  => 'utf8'
);

$redis->select('1');

while (1) {
    my $rawdata = $redis->lpop('rawdata');

    if ($rawdata) {
        my $data = decode_json $rawdata;
        print Dumper $data;
        my $is = new Ham::APRS::IS(
            'belgium.aprs2.net:14580', $data->{call},
            'passcode' => Ham::APRS::IS::aprspass( $data->{call} ),
            'appid'    => 'APLORA 1.2'
        );
        $is->connect( 'retryuntil' => 3 );

        $is->sendline( $data->{raw} );
        $is->disconnect;

        my %packetdata_ref;
        my $retval     = parseaprs( $data->{raw}, \%packetdata_ref );
        my $packetdata = \%packetdata_ref;

        if ( $retval == 1 ) {
            $packetdata->{loragateway} = $data->{call};
            $packetdata->{rssi}        = $data->{rssi};

            $redis->zadd( "lastheard" . $data->{call},
                time(), $packetdata->{srccallsign} );
            $redis->zadd( "lastheard", time(), $packetdata->{srccallsign} );
            $redis->sadd( "users", $data->{call} );
            $redis->set( "lastdata" . $data->{call}, time() );
            $redis->set( "lastpacket" . $packetdata->{srccallsign},
                encode_json($packetdata) );
        }
        else {
            warn
                "Parsing failed: $packetdata->{resultmsg} ($packetdata->{resultcode})\n";
        }
    }
}
