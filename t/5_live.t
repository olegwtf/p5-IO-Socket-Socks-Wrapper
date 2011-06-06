#!/usr/bin/env perl

use Test::More;
use IO::Socket::Socks::Wrapper;
require 't/subs.pm';
use strict;

SKIP: {
	skip "fork, windows, sux" if $^O =~ /MSWin/i;
	eval { require IO::Socket::SSL; require LWP;  }
		or skip "No LWP or IO::Socket::SSL found";
		
	my $ua = LWP::UserAgent->new(timeout => 10);
	my $page = $ua->get('https://encrypted.google.com')->content;
	skip "Seems there is no internet connection on this machine"
		if (() = $page =~ /google/g) < 2;
	
	my ($s_pid, $s_host, $s_port) = make_socks_server(5);
	
	IO::Socket::Socks::Wrapper->import(
		IO::Socket::SSL:: => {
			ProxyAddr => $s_host,
			ProxyPort => $s_port,
		}
	);
	
	$ua = LWP::UserAgent->new(timeout => 10);
	$page = $ua->get('https://encrypted.google.com')->content;
	ok((() = $page =~ /google/g) >= 2, 'IO::Socket::SSL socks5 wrapping +Server');
	
	kill 15, $s_pid;
	$page = $ua->get('https://encrypted.google.com')->content;
	ok((() = $page =~ /google/g) < 2, 'IO::Socket::SSL socks5 wrapping -Server') or diag $page;
};

SKIP: {
	skip "fork, windows, sux" if $^O =~ /MSWin/i;
	eval { require Net::POP3 }
		or skip "No Net::POP3 found";
	
	Net::POP3->new('gorodok.net', Timeout => 10)
		or skip "Seems there is no internet connection on this machine";
	
	my ($s_pid, $s_host, $s_port) = make_socks_server(4);
	
	IO::Socket::Socks::Wrapper->import(
		Net::POP3:: => {
			ProxyAddr => $s_host,
			ProxyPort => $s_port,
			SocksVersion => 4
		}
	);
	
	ok(Net::POP3->new('gorodok.net', Timeout => 10), 'POP3 connection +Server') or diag $@;
	
	kill 15, $s_pid;
	ok(!defined(Net::POP3->new('gorodok.net', Timeout => 10)), 'POP3 connection -Server');
};

done_testing();
