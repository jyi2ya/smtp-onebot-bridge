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
    $body =~ s/\s*$//s;
    (\%headers, $body);
}

use DDP;
while(my $conn = $server->accept()) {
    my $client = Net::SMTP::Server::Client->new($conn) or die;
    $client->process || next;
    my $content = $client->{MSG};
    utf8::decode $content;
    my ($headers, $body) = parse_message_content $content;

    my $subject = $headers->{Subject} || '[NO SUBJECT]';
    my $sender = $client->{FROM} || '[NO SENDER]';

    my ($endpoint, $payload);

    my $message = <<EOF;
【$subject】
$sender

$body
EOF

    for my $dest (@{ $client->{TO} }) {
        $dest =~ s/^<|>$//g;
        my ($number, $group);

        if (($number) = ($dest =~ /^p_(\d+)/)) {
            say "send to private: $number";
            $endpoint = "$ENV{ONEBOT_API}/send_private_msg";
            $payload = {
                user_id => $number,
                message => [
                    { type => 'text', data => { text => $message } },
                ]
            };
        } elsif (($group) = ($dest =~ /^g_(\d+)/)) {
            say "send to group: $group";
            $endpoint = "$ENV{ONEBOT_API}/send_group_msg";
            $payload = {
                group_id => $group,
                message => [
                    { type => 'text', data => { text => $message } },
                ]
            }
        } elsif (($number, $group) = ($dest =~ /^m_(\d+)_(\d+)/)) {
            say "send to someone at group: $number\@$group";
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
            warn "unknown dest: $dest";
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
        warn JSON::to_json($resp) unless $ok;
    }
}

