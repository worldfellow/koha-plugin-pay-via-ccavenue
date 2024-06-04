#!/usr/bin/perl
use strict;
use warnings;

use Crypt::CBC;
use MIME::Base64;
use Digest::MD5 qw(md5 md5_hex md5_base64);

# Encryption Function
sub encrypt{
   	# get total number of arguments passed.
   	my $n = scalar(@_);
	my $key = md5($_[0]);
	my $plainText = $_[1];
	my $iv = pack "C16", 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f;
	
	my $cipher = Crypt::CBC->new(
        		-key         => $key,
        		-iv          => $iv,
        		-cipher      => 'OpenSSL::AES',
        		-literal_key => 1,
        		-header      => "none",
        		-padding     => "standard",
        		-keysize     => 16
  			);

	my $encrypted = $cipher->encrypt_hex($plainText);
   	return $encrypted;

}

# Decryption Function
sub decrypt{
   	# get total number of arguments passed.
   	my $n = scalar(@_);
	my $key = md5($_[0]);
	my $encryptedText = $_[1];
	my $iv = pack "C16", 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f;
	
	my $cipher = Crypt::CBC->new(
        		-key         => $key,
        		-iv          => $iv,
        		-cipher      => 'OpenSSL::AES',
        		-literal_key => 1,
        		-header      => "none",
        		-padding     => "standard",
        		-keysize     => 16
  			);

	my $plainText = $cipher->decrypt_hex($encryptedText);
   	return $plainText;

}

1;