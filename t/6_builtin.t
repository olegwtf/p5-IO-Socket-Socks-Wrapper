use strict;
use Test::More;
use lib 't';
use IO::Socket::Socks::Wrapper;
require 't/subs.pm';

$^W = 0;

SKIP: {
	skip "fork, windows, sux" if $^O =~ /MSWin/i;
	
	my ($s_pid, $s_host, $s_port) = make_socks_server(4);
	my ($h_pid, $h_host, $h_port) = make_http_server();
	
	IO::Socket::Socks::Wrapper->import(
		Connect => {
			ProxyAddr    => $s_host,
			ProxyPort    => $s_port,
			SocksVersion => 4
		}
	);
	require Connect;
	
	ok(Connect::make($h_host, $h_port), "Built-in connect +socks 4 server");
	
	kill 15, $s_pid;
	ok(!Connect::make($h_host, $h_port), "Built-in connect -socks 4 server");
	
	IO::Socket::Socks::Wrapper->import(
		Connect => 0
	);
	ok(Connect::make($h_host, $h_port), "Built-in connect +direct network access");
	
	kill 15, $h_pid;
	ok(!Connect::make($h_host, $h_port), "Built-in connect +direct network access -http server");
}

done_testing();
