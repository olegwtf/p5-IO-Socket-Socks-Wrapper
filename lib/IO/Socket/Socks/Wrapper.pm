package IO::Socket::Socks::Wrapper;

use strict;
no warnings 'prototype';
no warnings 'redefine';
use Socket;
use base 'Exporter';

our $VERSION = '0.08_2';
our @EXPORT_OK = 'connect';

# cache
# pkg -> ref to pkg::sub || undef(if pkg has no connect)
my %PKGS;

sub import
{
	my $mypkg = shift;
	
	while(my ($pkg, $cfg) = splice @_, 0, 2) {
		unless(defined $cfg) {
			$cfg = $pkg;
			$pkg = undef;
		}
		
		if($pkg) {
			no strict 'refs';
			
			my $sub;
			if ($pkg =~ /^(.+)::([^:]+)\(\)$/) {
				$pkg = $1;
				$sub = $2;
			}
			
			# override in the package
			
			# do not load module with package if package already available
			# some packages haven't separate modules
			# so, in this case loading will fail
			# allow the user to load correct module with needed package
			unless(%{$pkg.'::'}) {
				eval "require $pkg" # make @ISA available
					or die $@;
			}
			
			if ($sub) {
			# localize IO::Socket::connect overriding
			# in the sub where IO::Socket::connect called
				my $symbol = $pkg.'::'.$sub;
				my $pkg_sub = exists $PKGS{$symbol} ?
				                     $PKGS{$symbol} :
				                     ($PKGS{$symbol} = \&$symbol);
				*$symbol = sub {
					local *IO::Socket::connect = sub {
						_connect(@_, $cfg);
					};
					
					$pkg_sub->(@_);
				};
				next;
			}
			elsif($pkg->isa('IO::Socket')) {
			# replace IO::Socket::connect
			# if package inherits from IO::Socket
				# save replaceable package version of the connect
				# if it has own
				# will call it from the our new connect
				my $symbol = $pkg.'::connect';
				my $pkg_connect = exists $PKGS{$pkg} ?
				                         $PKGS{$pkg} :
				                         ($PKGS{$pkg} = eval{ *{$symbol}{CODE} } ? \&$symbol : undef);
				
				*connect = sub {
					local(*IO::Socket::connect) = sub {
						_connect(@_, $cfg);
					};
					
					my $self = shift;
					
					if ($pkg_connect) {
					# package has its own connect
						$pkg_connect->($self, @_);
					}
					else {
					# get first parent which has connect sub
					# and call it
						my $ref = ref($self);
						
						foreach my $parent (@{$pkg.'::ISA'}) {
							if($parent->isa('IO::Socket')) {
								bless $self, $parent;
								$self->connect(@_);
								bless $self, $ref;
								return $self;
							}
						}
					}
				}
			}
			else {
				# replace package version of connect
				*connect = sub {
					_connect(@_, $cfg);
				}
			}
			
			$mypkg->export($pkg, 'connect');
		}
		else {
			# override connect() globally
			*connect = sub(*$) {
				my $socket = shift;
				unless (ref $socket) {
					# old-style bareword used
					no strict 'refs';
					my $caller = caller;
					$socket = $caller . '::' . $socket;
					$socket = \*{$socket};
				}
				
				_connect($socket, @_, $cfg);
			};
			
			$mypkg->export('CORE::GLOBAL', 'connect');
		}
	}
}

sub wrap_connection {
	require IO::Socket::Socks::Wrapped;
	return  IO::Socket::Socks::Wrapped->new(@_);
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
	
	unless (exists $cfg->{Timeout}) {
		$cfg->{Timeout} = 180;
	}
	
	IO::Socket::Socks->new_from_socket(
		$socket,
		ConnectAddr  => $host,
		ConnectPort  => $port,
		%$cfg
	) or return;
	
	bless $socket, $ref if $ref; # XXX: should we unbless for GLOB?
	1;
}

1;

__END__

=head1 NAME

IO::Socket::Socks::Wrapper - Allow any perl package to work through a socks proxy

=head1 SYNOPSIS

=over

	# wrap Net::FTP and Net::HTTP only
	use IO::Socket::Socks::Wrapper (
		Net::FTP => { # also specify `Net::FTP::dataconn' to wrap data connection
			ProxyAddr => '10.0.0.1',
			ProxyPort => 1080,
			SocksDebug => 1,
			Timeout => 15
		},
		Net::HTTP => {
			ProxyAddr => '10.0.0.2',
			ProxyPort => 1080,
			SocksVersion => 4,
			SocksDebug => 1,
			Timeout => 15
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

	# wrap all connections
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

=over

	# more direct LWP::UserAgent wrapping
	
	# we need to associate LWP::Protocol::http::Socket and LWP::Protocol::https::Socket packages
	# with socks proxy
	# this packages do not have separate modules
	# LWP::Protocol::http and LWP::Protocol::https modules includes this packages respectively
	# IO::Socket::Socks::Wrapper should has access to @ISA of each package which want to be wrapped
	# when package == module it can load packages automatically and do its magic with @ISA
	# but in the case like this loading will fail
	# so, we should load this modules manually
	use LWP::Protocol::http;
	use LWP::Protocol::https;
	use IO::Socket::Socks::Wrapper (
		LWP::Protocol::http::Socket => {
			ProxyAddr => 'localhost',
			ProxyPort => 1080,
			SocksDebug => 1,
			Timeout => 15
		},
		LWP::Protocol::https::Socket => {
			ProxyAddr => 'localhost',
			ProxyPort => 1080,
			SocksDebug => 1,
			Timeout => 15
		}
	);
	use LWP;
	
	# then use lwp as usual
	my $ua = LWP::UserAgent->new();
	
	# in this case Net::HTTP and Net::HTTPS objects will use direct network access
	# but LWP::UserAgent objects will use socks proxy

=back

=over

	# the way to wrap package that is not inherited from IO::Socket
	# but uses IO::Socket object as internal socket handle
	
	use HTTP::Tiny; # HTTP::Tiny::Handle package is in HTTP::Tiny module
	use IO::Socket::Socks::Wrapper (
		# HTTP::Tiny::Handle::connect sub invokes IO::Socket::INET->new
		# see HTTP::Tiny sourse code
		'HTTP::Tiny::Handle::connect()' => { # parentheses required
			ProxyAddr => 'localhost',
			ProxyPort => 1080,
			SocksVersion => 4,
			Timeout => 15
		}
	);
	
	# via socks
	my $page = HTTP::Tiny->new->get('http://www.google.com/')->{content};
	
	# disable wrapping for HTTP::Tiny
	IO::Socket::Socks::Wrapper->import('HTTP::Tiny::Handle::connect()' => 0);
	# and get page without socks
	$page = HTTP::Tiny->new->get('http://www.google.com/')->{content};

=back

=head1 DESCRIPTION

C<IO::Socket::Socks::Wrapper> allows to wrap up the network connections into socks proxy. It can wrap up connection
from separate packages or any network connection. It works by overriding builtin connect() function in the package
or globally, or by overriding IO::Socket::connect() function in the package.

=head1 METHODS

=head2 import( CFG )

import() is invoked when C<IO::Socket::Socks::Wrapper> loaded by `use' command. Later it can be invoked manually
to change proxy in some package. Global overriding will not work in the packages that was loaded before calling 
IO::Socket::Socks::Wrapper->import(). So, for this purposes `use IO::Socket::Socks::Wrapper' with $hashref argument
should be before any other `use' statements.

=head3 CFG syntax

=over

=item Global wrapping

Only $hashref should be specified. $hashref is a reference to a hash with key/value pairs same as L<IO::Socket::Socks>
constructor options, but without (Connect|Bind|Udp)Addr and (Connect|Bind|Udp)Port. To disable wrapping $hashref could
be scalar with false value.

=item Wrapping package that inherits from IO::Socket or uses builtin connect()

Examples are: Net::FTP, Net::POP3, Net::HTTP

	'pkg' => $hashref

Where pkg is a package name that is responsible for connections. For example if you want to wrap LWP http connections, then module
name should be Net::HTTP, for https connections it should be Net::HTTPS or even LWP::Protocol::http::Socket and
LWP::Protocol::https::Socket respectively (see examples above). You really need to look at the source code of the package
which you want to wrap to determine the name for wrapping. Or use global wrapping which will wrap all that can. Use `SocksDebug' to
verify that wrapping works good. For $hashref description see above.

=item Wrapping package that uses IO::Socket object or class object inherited from IO::Socket as internal socket handle

Examples are: HTTP::Tiny (HTTP::Tiny::Handle::connect)

	'pkg::sub()' => $hashref

Where sub is a name of subroutine contains IO::Socket object creation/connection.
Parentheses required. For pkg and $hashref description see above.

=back

=head1 NOTICE

Default timeout for wrapped connect is 180 sec. You can specify your own value using C<Timeout> option. Set it to zero if you don't want
to limit connection attempt time.

=head1 BUGS

Wrapping doesn't work with impure perl packages. WWW::Curl for example.

=head1 SEE ALSO

L<IO::Socket::Socks>

=head1 COPYRIGHT

Oleg G <oleg@cpan.org>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
