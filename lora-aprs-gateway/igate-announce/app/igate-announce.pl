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
use Geo::Coordinates::DecimalDegrees;

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
    my $rawdata = $redis->smembers('users');

    if ($rawdata) {
        while ( my $user = shift(@$rawdata) ) {
            my $lasthb = $redis->get( $user . "heartbeat" );
            if ( ( !$lasthb ) || ( $lasthb < time() - 3500 ) ) {
                $redis->set( $user . "heartbeat", time() );
                print "Sending keepalive for " . $user . "\n";

                my $lat = 51.15195;
                my $lon = 2.76532;
                my ( $degreesn, $minutesn, $secondsn, $signn )
                    = decimal2dms($lat);
                my ( $degreese, $minutese, $secondse, $signn )
                    = decimal2dms($lon);

                my $comment   = "https://rf.guru LoraAPRSGateway v0.1";
                my $altinfeet = "0";

                my $stable = "L";
                my $stype  = "&";
                my $coord  = sprintf(
                    "%02d%02d.%02dN%s%03d%02d.%02dE%1s",
                    $degreesn, $minutesn, $secondsn, $stable,
                    $degreese, $minutese, $secondse, $stype
                );

                my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday )
                    = gmtime();
                my $message
                    = sprintf( "%s>APDW16,TCPIP*:@%02d%02d%02dh%s/A=%06d %s",
                    $user, $hour, $min, $sec, $coord, $altinfeet, $comment );

                my $is = new Ham::APRS::IS(
                    'belgium.aprs2.net:14580', $user,
                    'passcode' => Ham::APRS::IS::aprspass($user),
                    'appid'    => 'APLORA 1.2'
                );
                $is->connect( 'retryuntil' => 3 );

                $is->sendline($message);
                $is->disconnect;
            }
        }

    }

}
