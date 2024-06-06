package Koha::Plugin::Com::WorldFellow::PayViaCCAVenue;

use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);


## We will also need to include any Koha libraries we want to access

use C4::Context;
use C4::Auth qw(get_template_and_user);
use Koha::Account;
use Koha::Account::Lines;
use List::Util qw(sum);
use URI::Encode qw(uri_encode uri_decode);
use Time::HiRes qw(gettimeofday);
## Here we set our plugin version
our $VERSION = "1.0.0";
use Crypt::CBC;
use MIME::Base64;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Encode qw(encode_utf8);
use DateTime;

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name          => 'Pay Via CCAVenue',
    author        => 'Priyanka Divekar',
    description   => 'This plugin enables online OPAC fee payments via CCAVenue',
    date_authored => '2024-06-03',
    date_updated  => '2023-06-03',
    minimum_version => '23.11.04',
    maximum_version => undef,
    version         => $VERSION,
};


sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub opac_online_payment {
    my ( $self, $args ) = @_;
    try{
        return $self->retrieve_data('enable_opac_payments') eq 'Yes';
    }catch{
        warn "opac online payment"
    }
}

sub opac_online_payment_begin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $active_currency = Koha::Acquisition::Currencies->get_active;

    my ( $template, $borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_payment_request.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );

    my @accountline_ids = $cgi->multi_param('accountline');

    my $rs = Koha::Database->new()->schema()->resultset('Accountline');
    my @accountlines = map { $rs->find($_) } @accountline_ids;

    my $patron = scalar Koha::Patrons->find($borrowernumber);

    my $token = "B" . $borrowernumber . "T" . time;

    my $table = $self->get_qualified_table_name('pay_via_ccavenue');
    C4::Context->dbh->do(
        qq{
        INSERT INTO $table ( token, borrowernumber )
        VALUES ( ?, ? )
    }, undef, $token, $borrowernumber
    );

     

    # my $rs = Koha::Database->new()->schema()->resultset('Accountline');
    # my @accountlines = map { $rs->find($_) } @accountline_ids;

    my $amount_to_pay = 0;
    
    foreach $a (@accountlines) {
        $amount_to_pay = $amount_to_pay + $a->amountoutstanding;
    }

    my $redirect_url = C4::Context->preference('OPACBaseURL') . "/cgi-bin/koha/opac-account-pay-return.pl?payment_method=Koha::Plugin::Com::WorldFellow::PayViaCCAVenue";
    # my $redirectUrlParameters = "transactionType,transactionStatus,transactionId,transactionResultCode,transactionResultMessage,orderAmount,userChoice1,userChoice2,userChoice3";
    my $cancel_url = C4::Context->preference('OPACBaseURL') . "/cgi-bin/koha/opac-account.pl";

    my $dt = DateTime->new(time_zone => 'Asia/Kolkata');
    my $transaction_id = $patron->cardnumber.'Y'.$dt->year.'M'.$dt->month.'D'.$dt->day.'T'.$dt->hour.$dt->minute.$dt->second;
    my $requestParams = "";
    $requestParams = $requestParams."merchant_id=";
    $requestParams = $requestParams.uri_encode($self->retrieve_data('merchant_id'))."&";
    $requestParams = $requestParams."order_number=";
    $requestParams = $requestParams.uri_encode($accountlines[0]->id)."&";
    $requestParams = $requestParams."currency=";
    $requestParams = $requestParams.uri_encode($active_currency)."&";
    $requestParams = $requestParams."amount=";
    $requestParams = $requestParams.uri_encode($amount_to_pay)."&";
    $requestParams = $requestParams."redirect_url=";
    $requestParams = $requestParams.uri_encode($redirect_url)."&";
    $requestParams = $requestParams."cancel_url=";
    $requestParams = $requestParams.uri_encode($cancel_url)."&";
    $requestParams = $requestParams."language=";
    $requestParams = $requestParams.uri_encode('EN')."&";
    $requestParams = $requestParams."billing_name=";
    $requestParams = $requestParams.uri_encode(($patron->firstname.' '.$patron->surname))."&";
    $requestParams = $requestParams."billing_address=";
    $requestParams = $requestParams.uri_encode($patron->address)."&";
    $requestParams = $requestParams."billing_city=";
    $requestParams = $requestParams.uri_encode($patron->city)."&";
    $requestParams = $requestParams."billing_state=";
    $requestParams = $requestParams.uri_encode($patron->state)."&";
    $requestParams = $requestParams."billing_zip=";
    $requestParams = $requestParams.uri_encode($patron->zipcode)."&";
    $requestParams = $requestParams."billing_country=";
    $requestParams = $requestParams.uri_encode('India')."&";
    $requestParams = $requestParams."billing_tel=";
    $requestParams = $requestParams.uri_encode($patron->mobile)."&";
    $requestParams = $requestParams."billing_email=";
    $requestParams = $requestParams.uri_encode($patron->email)."&";
    $requestParams = $requestParams."merchant_param1=";
    $requestParams = $requestParams.uri_encode($patron->id)."&";
    $requestParams = $requestParams."merchant_param2=";
    $requestParams = $requestParams.uri_encode(join( ',', map { $_->id } @accountlines ))."&";
    $requestParams = $requestParams."merchant_param3=";
    $requestParams = $requestParams.uri_encode($token)."&";
    $requestParams = $requestParams."merchant_param4=";
    $requestParams = $requestParams.uri_encode($patron->cardnumber)."&";
    $requestParams = $requestParams."merchant_param5=";
    $requestParams = $requestParams.uri_encode($transaction_id)."&";
   
    my $encrypted = $self->encrypt({working_key => $self->retrieve_data('working_Key'), request_str => $requestParams});

    $template->param(
        borrower             => $patron,
        payment_method       => scalar $cgi->param('payment_method'),
        enable_opac_payments => $self->retrieve_data('enable_opac_payments'),
        accountlines         => \@accountlines,
        payment_url          => $self->retrieve_data('payment_url'),
        encrypted            => $encrypted,
        access_code          => $self->retrieve_data('access_code')
    );

    print $cgi->header();
    print $template->output();
}

sub opac_online_payment_end {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my ( $template, $logged_in_borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_payment_response.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );
    my $encResp = $cgi->param("encResp"); 
    my @plainText =  $self->decrypt({working_key => $self->retrieve_data('working_Key'), response_str => $encResp});
    #warn "NELNET INCOMING: " . Data::Dumper::Dumper( \%vars );
    my %params = split('&', $plainText[0]);
    
    my $borrowernumber = $params{merchant_param1};
    my $accountline_ids = $params{merchant_param2};
    my $token = $params{merchant_param3};

    my $transaction_status = $params{order_status};
    my $transaction_id = $params{tracking_id};
    # my $transaction_result_message = $vars{transactionResultMessage};
    my $order_amount =$params{mer_amount};
    my $table = $self->get_qualified_table_name('pay_via_ccavenue');
    my $dbh      = C4::Context->dbh;
    my $query    = "SELECT * FROM $table WHERE token = ?";
    my $token_hr = $dbh->selectrow_hashref( $query, undef, $token );

    my $accountlines = [ split( ',', $accountline_ids ) ];

    my ( $m, $v );
    if ( $logged_in_borrowernumber ne $borrowernumber ) {
        $m = 'not_same_patron';
        $v = $transaction_id;
    }
    elsif ( $transaction_status eq '1' ) { # Success
        if ($token_hr) {
            my $note = "Paid via CCAVenue: " . sha256_hex( $transaction_id );

            # If this note is found, it must be a duplicate post
            unless (
                Koha::Account::Lines->search( { note => $note } )->count() )
            {

                my $patron  = Koha::Patrons->find($borrowernumber);
                my $account = $patron->account;

                my $schema = Koha::Database->new->schema;

                my @lines = Koha::Account::Lines->search( { accountlines_id => { -in => $accountlines } } )->as_list;
                my $table = $self->get_qualified_table_name('pay_via_ccavenue');
                $schema->txn_do(
                    sub {
                        $dbh->do(qq{
                            DELETE FROM $table WHERE token = ?},
                            undef, $token
                        );

                        $account->pay(
                            {
                                amount     => $order_amount,
                                note       => $note,
                                library_id => $patron->branchcode,
                                lines      => \@lines,
                            }
                        );
                    }
                );

                $m = 'valid_payment';
                $v = $order_amount;
            }
            else {
                $m = 'duplicate_payment';
                $v = $transaction_id;
            }
        }
        else {
            $m = 'invalid_token';
            $v = $transaction_id;
        }
    }
    else {
        # 1 = Accepted credit card payment/refund (successful)
        # 2 = Rejected credit card payment/refund (declined)
        # 3 - Error credit card payment/refund (error)
        $m = 'payment_failed';
        $v = $transaction_id;
    }

    $template->param(
        borrower      => scalar Koha::Patrons->find($borrowernumber),
        message       => $m,
        message_value => $v,
    );

    print $cgi->header();
    print $template->output();
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            enable_opac_payments => $self->retrieve_data('enable_opac_payments'),
            payment_url => $self->retrieve_data('payment_url'),
            merchant_id => $self->retrieve_data('merchant_id'),
            access_code => $self->retrieve_data('access_code'),
            working_Key => $self->retrieve_data('working_Key'),
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                enable_opac_payments => $cgi->param('enable_opac_payments'),
                payment_url=> $cgi->param('payment_url'),
                merchant_id => $cgi->param('merchant_id'),
                access_code => $cgi->param('access_code'),
                working_Key => $cgi->param('working_Key'),
            }
        );
        $self->go_home();
    }
}

sub install {
    my ( $self, $args ) = @_;
    try{
        my $table = $self->get_qualified_table_name('pay_via_ccavenue');

        return C4::Context->dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $table(
                token          VARCHAR(128),
                created_on     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                borrowernumber INT(11) NOT NULL,
                PRIMARY KEY (token),
                CONSTRAINT token_bn FOREIGN KEY (borrowernumber) REFERENCES borrowers (
                borrowernumber ) ON DELETE CASCADE ON UPDATE CASCADE
            )ENGINE=innodb
            DEFAULT charset=utf8mb4
            COLLATE=utf8mb4_unicode_ci;
        });
        	

    } catch {
        warn "Error installing CCAVenue plugin, caught error";
        return 0;
    };
}

sub uninstall() {
    my ( $self, $args ) = @_;
    my $table = $self->get_qualified_table_name('pay_via_ccavenue');
    return C4::Context->dbh->do(qq{DROP TABLE IF EXISTS $table});
}

# Encryption Function
sub encrypt {
   	# get total number of arguments passed.
    my ( $self, $args ) = @_;
   	# my $n = scalar(@_);
	my $key = md5($args->{working_key});
    # my $ctx = Digest::MD5->new;
	# my $key = $ctx->add($args->{working_key});
	my $plainText = $args->{request_str};
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
    # my $ctx = Digest::MD5->new;
    # $ctx->add($args->{working_key});
    # $ctx->add($args->{request_str});
    # my $encrypted = $ctx->hexdigest;
   	return $encrypted;

}

# Decryption Function
sub decrypt{
   	# get total number of arguments passed.
   	# my $n = scalar(@_);
    my ( $self, $args ) = @_;
    my $key = md5($args->{working_key});
	my $encryptedText = $args->{response_str};
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
    # my $ctx = Digest::MD5->new;
    # $ctx->add($args->{working_key});
    # $ctx->add($args->{response_str});
    # my $plainText = $ctx->hexdigest;
   	return $plainText;

}

1;
