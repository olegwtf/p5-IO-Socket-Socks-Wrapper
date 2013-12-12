use strict;
BEGIN {
	require 't/subs.pm';
	our ($s_pid, $s_host, $s_port) = make_socks_server(4);
}
use Test::More;
use lib 't';
use IO::Socket::Socks::Wrapper(
	Connect => {
		_norequire   => 1,
		ProxyAddr    => our $s_host,
		ProxyPort    => our $s_port,
		SocksVersion => 4
	}
);
use Connect;

$^W = 0;

SKIP: {
	skip "fork, windows, sux" if $^O =~ /MSWin/i;
	
	my ($h_pid, $h_host, $h_port) = make_http_server();
	
	ok(Connect::make($h_host, $h_port), "Built-in connect +socks 4 server");
	
	kill 15, our $s_pid;
	ok(!Connect::make($h_host, $h_port), "Built-in connect -socks 4 server");
	
	IO::Socket::Socks::Wrapper->import(
		Connect => 0
	);
	ok(Connect::make($h_host, $h_port), "Built-in connect +direct network access");
	
	kill 15, $h_pid;
	ok(!Connect::make($h_host, $h_port), "Built-in connect +direct network access -http server");
}

done_testing();
