package IO::Socket::Socks::Wrapper;

use strict;
use Socket;
use base 'Exporter';

our $VERSION = 0.02;
our @EXPORT_OK = 'connect';

sub import
{
	my $pkg = shift;
	
	while(my ($module, $cfg) = splice @_, 0, 2) {
		unless(defined $cfg) {
			$cfg = $module;
			$module = undef;
		}
		
		if($module) {
			# override connect() in the package
			eval "require $module" # make @ISA available
				or die $@;
			
			if($module->isa('IO::Socket::INET')) {
				# replace IO::Socket::INET::connect
				# if package inherits from IO::Socket::INET
				*connect = sub(*$) {
					local(*IO::Socket::INET::connect) = sub(*$) {
						_connect(@_, $cfg);
					};
					
					my $self = shift;
					my $ref = ref($self);
					no strict 'refs';
					
					# get first parent which has connect sub
					# and call it
					foreach my $parent (@{$module.'::ISA'}) {
						if($parent->isa('IO::Socket::INET')) {
							bless $self, $parent;
							$self->connect(@_);
							bless $self, $ref;
							return $self;
						}
					}
				}
			}
			else {
				# replace package version of connect
				*connect = sub(*$) {
					_connect(@_, $cfg);
				}
			}
			
			$pkg->export($module, 'connect');
		}
		else {
			# override connect() globally
			*connect = sub(*$) {
				_connect(@_, $cfg);
			};
			
			$pkg->export('CORE::GLOBAL', 'connect');
		}
	}
}

sub _connect
{
	my ($socket, $name, $cfg) = @_;
	my $ref = ref($socket);
	
	return CORE::connect( $socket, $name )
		if (($ref && $socket->isa('IO::Socket::Socks')) || !$cfg);
		
	my ($port, $host) = sockaddr_in($name);
	$host = inet_ntoa($host);
	
	# global overriding will not work with `use'
	require IO::Socket::Socks;
	
	IO::Socket::Socks->new_from_socket(
		$socket,
		ConnectAddr  => $host,
		ConnectPort  => $port,
		%$cfg
	) or return;
	
	bless $socket, $ref
		if $ref && $ref ne 'GLOB';
}

1;

__END__

=head1 NAME

IO::Socket::Socks::Wrapper - Allow any perl module to work through a socks proxy

=head1 SYNOPSIS

=over

	# only Net::FTP and Net::HTTP
	use IO::Socket::Socks::Wrapper (
		Net::FTP => { # `Net::FTP::dataconn' to wrap data connection
			ProxyAddr => '10.0.0.1',
			ProxyPort => 1080,
			SocksDebug => 1
		},
		Net::HTTP => {
			ProxyAddr => '10.0.0.2',
			ProxyPort => 1080,
			SocksVersion => 4,
			SocksDebug => 1
		}
	);
	use Net::FTP;
	use Net::POP3;
	use LWP;
	use strict;
	
	my $ftp = Net::FTP->new();       # via socks5://10.0.0.1:1080
	my $lwp = LWP::UserAgent->new(); # via socks4://10.0.0.2:1080
	my $pop = Net::POP3->new();      # direct network access
	
	...
	
	# change proxy for Net::FTP
	IO::Socket::Socks::Wrapper->import(Net::FTP:: => {ProxyAddr => '10.0.0.3', ProxyPort => 1080});

=back

=over

	# all modules
	use IO::Socket::Socks::Wrapper ( # should be before any other `use'
		{
			ProxyAddr => 'localhost',
			ProxyPort => 1080,
			SocksDebug => 1,
			Timeout => 10
		}
	);
	
	# except Net::FTP
	IO::Socket::Socks::Wrapper->import(Net::FTP:: => 0); # direct network access

=back

=head1 DESCRIPTION

C<IO::Socket::Socks::Wrapper> allows to wrap up the network connections into socks proxy. It can wrap up connection
from separate modules or any network connection. It works by overriding builtin connect() function in the package
or globally.

=head1 METHODS

=head2 import( CFG )

import() is invoked when C<IO::Socket::Socks::Wrapper> loaded by `use'. Later it can be invoked manually
to change proxy in some module. Global overriding will not work in modules which was loaded before calling 
IO::Socket::Socks::Wrapper->import(). So, for this purposes `use IO::Socket::Socks::Wrapper' should be before
any other uses.

CFG syntax to wrap up separate modules is:

	module => $hashref,
	...
	module => $hashref

module is a module which is responsible for connections. For example if you want to wrap LWP http connections, then module
name should be Net::HTTP, for https connections it should be Net::HTTPS. You really need to look at the code of the module
which you want to wrap to determine name for wrapping or use global wrapping which will wrap all that can. Use `SocksDebug' to
verify that wrapping works good.

For the global wrapping only $hashref should be specified.

$hashref is a reference to a hash with key/value pairs same as L<IO::Socket::Socks> constructor options, but without (Connect|Bind|Udp)Addr
and (Connect|Bind|Udp)Port. To disable of using proxy $hashref could be scalar with false value.

=head1 BUGS

Wrapping doesn't work with impure perl modules. WWW::Curl for example.

=head1 SEE ALSO

L<IO::Socket::Socks>

=head1 COPYRIGHT

Oleg G <oleg@cpan.org>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
