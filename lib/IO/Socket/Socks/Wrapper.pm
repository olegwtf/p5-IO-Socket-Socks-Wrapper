package IO::Socket::Socks::Wrapper;

use strict;
use Socket;
use base 'Exporter';

our $VERSION = 0.01;
our @EXPORT_OK = 'connect';
our $CFG = {};

sub import
{
	my ($pkg, %arg) = @_;
	
	$CFG = delete $arg{'-cfg'}
		if exists $arg{'-cfg'};
	
	while(my ($module, $socksaddr) = each(%arg)) {
		unless($socksaddr) {
			$socksaddr = $module;
			$module = undef;
		}
		
		my ($socksver, $sockshost, $socksport) = $socksaddr =~ m!^socks(4|5)://([^:]+):(\d+)!
			or next;
		
		if($module) {
			# override connect() in the package
			*connect = sub(*$) {
				my ($socket, $name) = @_;
				return _connect($socket, $name, $socksver, $sockshost, $socksport);
			};
			
			$pkg->export($module, 'connect');
		}
		else {
			# override connect() globally
			*connect = sub(*$) {
				my ($socket, $name) = @_;
				return _connect($socket, $name, $socksver, $sockshost, $socksport);
			};
			
			$pkg->export('CORE::GLOBAL', 'connect');
		}
	}
}

sub _connect
{
	my ($socket, $name, $socksver, $sockshost, $socksport) = @_;
	my $ref = ref($socket);
	
	return CORE::connect( $socket, $name )
		if ($ref && $socket->isa('IO::Socket::Socks'));
		
	my ($port, $host) = sockaddr_in($name);
	$host = inet_ntoa($host);
	
	# global overriding will not work with `use' pragma
	require IO::Socket::Socks;
	
	IO::Socket::Socks->new_from_socket(
		$socket,
		SocksVersion => $socksver,
		ProxyAddr    => $sockshost,
		ProxyPort    => $socksport,
		ConnectAddr  => $host,
		ConnectPort  => $port,
		%$CFG
	) or return;
	
	bless $socket, $ref
		if $ref && $ref ne 'GLOB';
}

1;
