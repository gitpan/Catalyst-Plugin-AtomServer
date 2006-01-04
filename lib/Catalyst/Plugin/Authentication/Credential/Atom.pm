# $Id: Atom.pm 1073 2006-01-04 05:08:28Z btrott $

package Catalyst::Plugin::Authentication::Credential::Atom;
use strict;

use MIME::Base64 qw( encode_base64 decode_base64 );
use Digest::SHA1 qw( sha1 );
use XML::Atom::Util qw( first textValue );

use constant NS_WSSE => 'http://schemas.xmlsoap.org/ws/2002/07/secext';
use constant NS_WSU => 'http://schemas.xmlsoap.org/ws/2002/07/utility';

sub login_atom {
    my $c = shift;
    my($username, $cred) = $c->_extract_credentials;
    return unless $username;

    my $user = $c->get_user($username) or return;
    if ($c->_validate_credentials($user, $cred)) {
        $c->set_authenticated($user);
        return 1;
    }
    return;
}

sub _extract_credentials {
    my $c = shift;
    my $req = $c->request;
    my($tokens, $username, %cred);
    ## SOAP wrapper only supports WSSE?
    if ($req->is_soap) {
        my $xml = $req->body_parsed;
        my $auth = first($xml, NS_WSSE, 'UsernameToken');
        $username = $cred{Username} = textValue($auth, NS_WSSE, 'Username');
        $cred{PasswordDigest} = textValue($auth, NS_WSSE, 'Password');
        $cred{Nonce} = textValue($auth, NS_WSSE, 'Nonce');
        $cred{Created} = textValue($auth, NS_WSU, 'Created');
    }
    
    ## Basic auth.
    elsif ($req->header('Authorization') and
        ($tokens) = $req->header('Authorization') =~ /^Basic (.+)$/) {
        ($username, $cred{password})= split /:/, decode_base64($tokens);
    }
    
    ## WSSE-via-HTTP-headers.
    elsif ($req->header('X-WSSE') and
        ($tokens) = $req->header('X-WSSE') =~ /^UsernameToken (.+)$/) {
        for my $pair (split /\s*,\s*/, $tokens) {
            my($k, $v) = split /=/, $pair, 2;
            $v =~ s/^"//;
            $v =~ s/"$//;
            $cred{$k} = $v;
        }
        $username = delete $cred{Username};
    }
    ($username, \%cred);
}

sub _validate_credentials {
    my $c = shift;
    my($user, $cred) = @_;
    if ($cred->{password}) {
        return $user->password eq $cred->{password};
    } elsif ($cred->{PasswordDigest}) {
        my $pass = $user->password;
        my $expected = encode_base64(sha1(
            decode_base64($cred->{Nonce}) . $cred->{Created} . $pass
        ), '');
        return $expected eq $cred->{PasswordDigest};
    }
}

1;
__END__

=head1 NAME

Catalyst::Plugin::Authentication::Credential::Atom - Authentication for Atom

=head1 SYNOPSIS

    use Catalyst qw( Authentication
                     Authentication::Credential::Atom
                     Authentication::Store::Minimal
                   );

    sub begin : Private {
        my($self, $c) = @_;
        $c->login_atom or die "Unauthenticated";
    }

=head1 DESCRIPTION

I<Catalyst::Plugin::Authentication::Credential::Atom> implements WSSE and
Basic authentication for Catalyst applications using
I<Catalyst::Plugin:AtomServer>.

It implements the Credential interface for the
I<Catalyst::Plugin::Authentication> framework, allowing you to use it with
any I<Store> backend.

=cut
