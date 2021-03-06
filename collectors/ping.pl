#! /usr/bin/perl
use DBI;
use POSIX;
use Time::HiRes qw(sleep time);
use Net::Oping;
use strict;
use warnings;
use Data::Dumper;
use IO::Socket::IP;

use lib '/opt/gondul/include';
use nms;

$|++;
my $dbh = nms::db_connect();
$dbh->{AutoCommit} = 0;
$dbh->{RaiseError} = 1;

my $q = $dbh->prepare("SELECT switch,sysname,host(mgmt_v4_addr) as ip,host(mgmt_v6_addr) as secondary_ip FROM switches WHERE mgmt_v4_addr is not null or mgmt_v6_addr is not null ORDER BY random();");
my $lq = $dbh->prepare("SELECT linknet,addr1,addr2 FROM linknets WHERE addr1 is not null and addr2 is not null;");

my $last = time();
my $target = 0.7;
while (1) {
	my $now = time();
	my $elapsed = ($now - $last);
	if ($elapsed < $target) {
		sleep($target - ($now - $last));
	}
	$last = time();
	# ping loopbacks
	my $ping = Net::Oping->new;
	$ping->timeout(0.3);

	$q->execute;
	my %ip_to_switch = ();
	my %secondary_ip_to_switch = ();
	my %sw_to_sysname = ();
	my $affected = 0;
	while (my $ref = $q->fetchrow_hashref) {
		$affected++;
		my $switch = $ref->{'switch'};
		my $sysname = $ref->{'sysname'};
		$sw_to_sysname{$switch} = $sysname;

		my $ip = $ref->{'ip'};
		if (defined($ip) ) {
			$ping->host_add($ip);
			$ip_to_switch{$ip} = $switch;
		}

		my $secondary_ip = $ref->{'secondary_ip'};
		if (defined($secondary_ip)) {
			$ping->host_add($secondary_ip);
			$secondary_ip_to_switch{$secondary_ip} = $switch;
		}
	}
	if ($affected == 0) {
		print "Nothing to do... sleeping 1 second...\n";
		sleep(1);
		next;
	}

	my $result = $ping->ping();
	die $ping->get_error if (!defined($result));
	my %dropped = %{$ping->get_dropped()};

	$dbh->do('COPY ping (switch, latency_ms) FROM STDIN');  # date is implicitly now.
	my $drops = 0;
	while (my ($ip, $latency) = each %$result) {
		my $switch = $ip_to_switch{$ip};
		if (!defined($switch)) {
			next;
		}
		my $sysname = $sw_to_sysname{$switch};

		if (!defined($latency)) {
			$drops += $dropped{$ip};
		}
		$latency //= "\\N";
		$dbh->pg_putcopydata("$switch\t$latency\n");
	}
 

	if ($drops > 0) {
		print "$drops ";
	}
	$dbh->pg_putcopyend();

	$dbh->do('COPY ping_secondary_ip (switch, latency_ms) FROM STDIN');  # date is implicitly now.
	while (my ($ip, $latency) = each %$result) {
		my $switch = $secondary_ip_to_switch{$ip};
		next if (!defined($switch));
		my $sysname = $sw_to_sysname{$switch};

		$latency //= "\\N";
		$dbh->pg_putcopydata("$switch\t$latency\n");
	}
	$dbh->pg_putcopyend();

	$dbh->commit;
	# ping linknets
	$ping = Net::Oping->new;
	$ping->timeout(0.4);

	$lq->execute;
	my @linknets = ();
	while (my $ref = $lq->fetchrow_hashref) {
		push @linknets, $ref;
		$ping->host_add($ref->{'addr1'});
		$ping->host_add($ref->{'addr2'});
	}
	if (@linknets) { 
		$result = $ping->ping();
		die $ping->get_error if (!defined($result));

		$dbh->do('COPY linknet_ping (linknet, latency1_ms, latency2_ms) FROM STDIN');  # date is implicitly now.
			for my $linknet (@linknets) {
				my $id = $linknet->{'linknet'};
				my $latency1 = $result->{$linknet->{'addr1'}} // '\N';
				my $latency2 = $result->{$linknet->{'addr2'}} // '\N';
				$dbh->pg_putcopydata("$id\t$latency1\t$latency2\n");
			}
		$dbh->pg_putcopyend();
	}
	$dbh->commit;
}

