package IO::Socket::Socks::Wrapped;

use IO::Socket;
use IO::Socket::Socks::Wrapper;

use constant {
	OBJ => 0,
	CFG => 1,
};

our $VERSION = '0.08_2';
our $AUTOLOAD;

sub new {
	my ($class, $obj, $cfg) = @_;
	bless [$obj, $cfg], $class;
}

sub AUTOLOAD {
	my $self = shift;
	
	local *IO::Socket::connect = sub {
		return IO::Socket::Socks::Wrapper::_connect(@_, $self->[CFG]);
	};
	
	$AUTOLOAD =~ s/^.+:://;
	$self->[OBJ]->$AUTOLOAD(@_);
}

sub DESTROY {}

1;
