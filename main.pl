#!/usr/bin/env perl
use 5.020;
use utf8;
use warnings;
use autodie;
use feature qw/signatures postderef/;
no warnings qw/experimental::postderef/;
use open qw/:std :utf8/;

use Net::SMTP::Server;
use Net::SMTP::Server::Client;
use HTTP::Tiny;
use JSON;
use Env qw/@ALLOWED_CIDR/;
push @ALLOWED_CIDR, '0.0.0.0/32' unless $ALLOWED_CIDR[0];

my $json = JSON->new->utf8(1);

my $server = Net::SMTP::Server->new(
    $ENV{LISTEN_ADDRESS},
    $ENV{LISTEN_PORT},
) or die;

my $ua = HTTP::Tiny->new(
    default_headers => {
        'Content-Type' => 'application/json',
        ($ENV{ONEBOT_TOKEN} ? (Authorization => "Bearer $ENV{ONEBOT_TOKEN}") : ()),
    }
);

sub parse_message_content ($message) {
    my ($header, $body) = ($message =~ /^(.*?)\r\n\r\n(.*)/s);
    my %headers = map { /([^:]*): (.*)/ } split "\r\n", $header;
    $body //= $message; # if no headers
    $body =~ s/\s*$//s;
    (\%headers, $body);
}

sub sd_info (@message) {
    say STDERR '<6>' . join '', @message;
}

sub sd_warn (@message) {
    say STDERR '<4>' . join '', @message;
}

sub ip_to_int ($ip) {
    my @octets = split /\./, $ip;
    return ($octets[0] << 24) | ($octets[1] << 16) | ($octets[2] << 8) | $octets[3];
}

sub is_ip_in_subnet ($ip, $cidr) {
    return 0 unless $cidr =~ /^(\d+\.\d+\.\d+\.\d+)\/(\d+)$/;
    my ($network, $mask_bits) = ($1, $2);
    return 0 unless $ip =~ /^\d+\.\d+\.\d+\.\d+$/;
    return 0 unless $network =~ /^\d+\.\d+\.\d+\.\d+$/;
    return 0 if $mask_bits < 0 || $mask_bits > 32;
    my $ip_int = ip_to_int($ip);
    my $network_int = ip_to_int($network);
    my $mask_int = (0xFFFFFFFF << (32 - $mask_bits)) & 0xFFFFFFFF;
    return ($ip_int & $mask_int) == ($network_int & $mask_int);
}

sd_info "listening";
sd_info "allowed cidr: ", join ", ", @ALLOWED_CIDR;

while(my $conn = $server->accept()) {
    my $peerhost = $conn->peerhost;
    my $allowed = grep { is_ip_in_subnet($peerhost, $_) } @ALLOWED_CIDR;
    sd_info "new conn from $peerhost, allowed = $allowed";
    next unless $allowed;
    my $client = Net::SMTP::Server::Client->new($conn) or die;
    $client->process || next;
    my $content = $client->{MSG};
    utf8::decode $content;
    my ($headers, $body) = parse_message_content $content;

    my $subject = $headers->{Subject} || '[NO SUBJECT]';
    my $sender = $client->{FROM} || '[NO SENDER]';

    my ($endpoint, $payload);

    my $message = <<EOF;
$subject
$sender

$body
EOF

    my @address = (@{ $client->{TO} }, $sender);

    sd_info "address: ", join ", ", @address;

    my @send_to;

    for my $address (@address) {
        $address =~ s/^<|>$//g;
        for my $dest (split '@', $address) {
            my $to;
            if ($dest =~ /^(p_\d+)/) {
                $to = $1;
            } elsif ($dest =~ /^(g_\d+)/) {
                $to = $1;
            } elsif ($dest =~ /^m_(\d+)_(\d+)/) {
                $to = $1;
            } else {
                next;
            }
            push @send_to, $to;
        }
    }

    @send_to = do {
        my %to = map { $_ => undef } @send_to;
        keys %to;
    };

    sd_info "send to: ", join ", ", @send_to;

    for my $dest (@send_to) {
        my ($number, $group);

        if (($number) = ($dest =~ /^p_(\d+)/)) {
            sd_info "send to private: $number";
            $endpoint = "$ENV{ONEBOT_API}/send_private_msg";
            $payload = {
                user_id => $number,
                message => [
                    { type => 'text', data => { text => $message } },
                ]
            };
        } elsif (($group) = ($dest =~ /^g_(\d+)/)) {
            sd_info "send to group: $group";
            $endpoint = "$ENV{ONEBOT_API}/send_group_msg";
            $payload = {
                group_id => $group,
                message => [
                    { type => 'text', data => { text => $message } },
                ]
            }
        } elsif (($number, $group) = ($dest =~ /^m_(\d+)_(\d+)/)) {
            sd_info "send to someone at group: $number\@$group";
            $endpoint = "$ENV{ONEBOT_API}/send_group_msg";
            $payload = {
                group_id => $group,
                message => [
                    { type => 'at', data => { qq => $number } },
                    { type => 'text', data => { text => "\n" } },
                    { type => 'text', data => { text => $message } },
                ]
            }
        } else {
            sd_info "unknown dest: $dest";
            next;
        }

        my $resp = $ua->post(
            $endpoint => {
                content => $json->encode($payload),
            }
        );

        my $ok = eval {
            die unless $resp->{success};
            my $data = $json->decode($resp->{content});
            die unless $data->{status} eq 'ok';
        };
        sd_warn JSON::to_json($resp) unless $ok;
    }
}

