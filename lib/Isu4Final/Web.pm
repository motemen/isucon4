package Isu4Final::Web;

use 5.014;
use warnings;
use utf8;
use Kossy;
use Redis::Fast;
use JSON;
use Cache::Memcached::Fast;
use Sereal qw(encode_sereal decode_sereal);

sub advertiser_id {
    my ( $self, $c ) = @_;
    return $c->req->header('X-Advertiser-Id');
}

sub redis {
    state $redis = Redis::Fast->new(server => '10.11.54.191:6379'); # isu31a
    $redis;
}

sub memd {
  my $self = shift;
  $self->{_membed} ||= Cache::Memcached::Fast->new({
    servers => [ { address => 'localhost:11211' } ],
    serialize_methods => [
        \&encode_sereal,
        \&decode_sereal,
    ],
  });
}

sub json {
    state $json = JSON->new;
}

sub ad_key {
    my ( $self, $slot, $id ) = @_;
    return "isu4:ad:${slot}-${id}";
}

sub asset_key {
    my ( $self, $slot, $id ) = @_;
    return "isu4:asset:${slot}-${id}";
}

sub advertiser_key {
    my ( $self, $id ) = @_;
    return "isu4:advertiser:$id";
}

sub slot_key {
    my ( $self, $slot ) = @_;
    return "isu4:slot:$slot";
}

sub next_ad_id {
    my $self = shift;
    $self->redis->incr('isu4:ad-next');
}

sub log_key {
    my ($self, $id) = @_;
    return "isu4:log:$id";
}

sub next_ad {
    my ( $self, $c ) = @_;
    my $slot = $c->args->{slot};
    my $key = $self->slot_key($slot);

    my $id = $self->redis->rpoplpush($key, $key);
    unless ( $id ) {
        return undef;
    }

    my $ad = $self->get_ad($c, $slot, $id);
    if ( $ad ) {
        return $ad;
    }
    else {
        $self->redis->lrem($key, 0, $id);
        $self->next_ad($c);
    }
}

sub get_ad {
    my ( $self, $c, $slot, $id ) = @_;
    my $key = $self->ad_key($slot, $id);
    my %ad  = $self->redis->hgetall($key);

    return undef if !%ad;

    $ad{impressions} = int($ad{impressions});
    $ad{asset}       = $c->req->uri_for("/slots/${slot}/ads/${id}/asset")->as_string;
    $ad{counter}     = $c->req->uri_for("/slots/${slot}/ads/${id}/count")->as_string;
    $ad{redirect}    = $c->req->uri_for("/slots/${slot}/ads/${id}/redirect")->as_string;
    $ad{type}        = undef if $ad{type} eq '';
    return \%ad;
}

sub decode_user_key {
    my ( $self, $id ) = @_;
    my ( $gender, $age ) = split '/', $id;
    return {
        gender => ($gender // '') eq '0' ? 'female' : ($gender // '') eq '1' ? 'male' : undef,
        age => int($age // 0),
    };
}

sub get_log {
    my ( $self, $id ) = @_;

    my @list = $self->redis->lrange($self->log_key($id), 0, -1);
    my $result = {};
    for my $line (@list) {
        my ( $ad_id, $user, $agent ) = split "\t", $line;
        $result->{$ad_id} = [] unless $result->{$ad_id};
        my $user_attr = $self->decode_user_key($user);
        push @{$result->{$ad_id}}, {
            ad_id  => $ad_id,
            user   => $user,
            agent  => $agent,
            age    => $user_attr->{age},
            gender => $user_attr->{gender},
        };
    }
    return $result;
}

get '/' => sub {
    my ( $self, $c )  = @_;
    open my $in, $self->root_dir . '/public/index.html' or do {
        $c->halt(404);
    };
    $c->res->body(do { local $/; <$in> });
    close $in;
    return $c->res;
};

post '/slots/{slot:[^/]+}/ads' => sub {
    my ($self, $c) = @_;

    my $advertiser_id;
    unless ( $advertiser_id = $self->advertiser_id($c) ) {
        $c->halt(400);
    }

    my $slot  = $c->args->{slot};
    my $asset = $c->req->uploads->{'asset'};

    my $id  = $self->next_ad_id;
    my $key = $self->ad_key($slot, $id);

    open my $in, $asset->path or do {
        $c->halt(500);
    };
    my $content = do { local $/; <$in> };
    close $in;

    $self->redis->hmset(
        $key,
        'slot'        => $slot,
        'id'          => $id,
        'title'       => scalar $c->req->param('title'),
        'type'        => $c->req->param('type') || $asset->content_type || 'video/mp4',
        'advertiser'  => $advertiser_id,
        'destination' => scalar $c->req->param('destination'),
        'impressions' => 0,
        sub {},
    );

    $self->redis->set($self->asset_key($slot, $id), $content, sub {});
    $self->redis->rpush($self->slot_key($slot), $id, sub {});
    $self->redis->sadd($self->advertiser_key($advertiser_id), $key, sub {});

    $self->redis->wait_all_responses;

    $self->memd->set($self->asset_key($slot, $id), $content);

    $c->render_json($self->get_ad($c, $slot, $id));
};

get '/slots/{slot:[^/]+}/ad' => sub {
    my ($self, $c) = @_;

    my $ad = $self->next_ad($c);
    if ( $ad ) {
        $c->res->header('Content-Length' => 0);
        $c->redirect($c->req->uri_for('/slots/' . $c->args->{slot} . '/ads/' . $ad->{id})->as_string);
    }
    else {
        $c->res->status(404);
        $c->res->content_type('application/json');
        $c->res->body(json->encode({ error => 'Not Found' }));
        return $c->res;
    }
};

get '/slots/{slot:[^/]+}/ads/{id:[0-9]+}' => sub {
    my ($self, $c) = @_;

    my $ad = $self->get_ad($c, $c->args->{slot}, $c->args->{id});
    if ( $ad ) {
        my $body = json->encode($ad);
        $c->res->status(200);
        $c->res->header('Content-Length' => length($body));
        $c->res->content_type('application/json');
        $c->res->body($body);
    }
    else {
        $c->res->status(404);
        $c->res->content_type('application/json');
        $c->res->body(json->encode({ error => 'Not Found' }));
    }
    return $c->res;
};

get '/slots/{slot:[^/]+}/ads/{id:[0-9]+}/asset' => sub {
    my ($self, $c) = @_;

    my $slot = $c->args->{slot};
    my $id   = $c->args->{id};

    my $ad = $self->get_ad($c, $slot, $id);

    if ( $ad ) {
        $c->res->content_type($ad->{type} || 'video/mp4');
        my $data = $self->memd->get($self->asset_key($slot, $id)) || $self->redis->get($self->asset_key($slot, $id));

        my $range = $c->req->header('Range');
        if ( !$range ) {
            die Kossy::Exception->new(200, _response => sub {
                my $respond = shift;
                open my $fh, '<', \$data or die $!;
                my $writer = $respond->(
                    [ 200, [ 'Content-Length' => length($data) ] ]
                );
                while (my $len = read $fh, my $buf, 8192) {
                    $writer->write($buf);
                }
            });
        }
        elsif ( $range =~ /\Abytes=(\d+)?-(\d+)?\z/ )  {
            my ( $head, $tail ) = ( $1, $2 );

            if ( !defined($head) && !defined($tail) ) {
                $c->halt(416);
            }
            my $length = length($data);

            $head ||= 0;
            $tail ||= $length - 1;

            if ( $head < 0 || $head >= $length || $tail < 0 ) {
                $c->halt(416);
            }

            my $partial_body = substr($data, $head, $tail - $head + 1);

            $c->res->status(206);
            $c->res->header('Content-Range' => "bytes ${head}-${tail}/${length}", 'Content-Length' => length($partial_body));

            $c->res->body($partial_body);
            return $c->res;

        }
        else {
            $c->halt(416);
        }

    }
    else {
        $c->res->status(404);
        $c->res->content_type('application/json');
        $c->res->body(json->encode({ error => 'Not Found' }));
        return $c->res;
    }
};

post '/slots/{slot:[^/]+}/ads/{id:[0-9]+}/count' => sub {
    my ($self, $c) = @_;

    my $slot = $c->args->{slot};
    my $id   = $c->args->{id};

    my $key = $self->ad_key($slot, $id);

    unless ( $self->redis->exists($key) ) {
        $c->res->status(404);
        $c->res->content_type('application/json');
        $c->res->body(json->encode({ error => 'Not Found' }));
        return $c->res;
    }

    $self->redis->hincrby($key, 'impressions', 1);

    $c->res->status(204);
    return $c->res;
};

get '/slots/{slot:[^/]+}/ads/{id:[0-9]+}/redirect' => sub {
    my ($self, $c) = @_;

    my $slot = $c->args->{slot};
    my $id   = $c->args->{id};

    my $ad = $self->get_ad($c, $slot, $id);

   unless ( $ad ) {
        $c->res->status(404);
        $c->res->content_type('application/json');
        $c->res->body(json->encode({ error => 'Not Found' }));
        return $c->res;
    }

    my $value = join "\t",
        ($ad->{id} // ''),
        ($c->req->cookies->{isuad} // ''),
        ($c->req->env->{'HTTP_USER_AGENT'} // '');
    $self->redis->rpush($self->log_key($ad->{advertiser}), $value);

    $c->redirect($ad->{destination});
};

get '/me/report' => sub {
    my ($self, $c) = @_;

    my $advertiser_id = $self->advertiser_id($c);

    unless ( $advertiser_id ) {
        $c->halt(401);
    }

    my $ad_keys = $self->redis->smembers( $self->advertiser_key($advertiser_id) );

    my $report = {};
    for my $ad_key ( @$ad_keys ) {
        my %ad = $self->redis->hgetall($ad_key);
        next unless %ad;
        $ad{impressions} = int($ad{impressions});
        $report->{$ad{id}} = { ad => \%ad, clicks => 0, impressions => $ad{'impressions'} };
    }

    my $logs = $self->get_log($advertiser_id);

    for my $ad_id ( keys %$logs ) {
        $report->{$ad_id}->{clicks} = scalar @{$logs->{$ad_id}};
    }

    $c->render_json($report);
};

get '/me/final_report' => sub {
    my ($self, $c) = @_;

    my $advertiser_id = $self->advertiser_id($c);

    unless ( $advertiser_id ) {
        $c->halt(401);
    }

    my $reports = {};
    my $ad_keys = $self->redis->smembers( $self->advertiser_key($advertiser_id) );
    for my $ad_key ( @$ad_keys ) {
        my %ad = $self->redis->hgetall($ad_key);
        next unless %ad;
        $ad{impressions} = int($ad{impressions});
        $reports->{$ad{id}} = { ad => \%ad, clicks => 0, impressions => int($ad{'impressions'}) };
    }

    my $logs = $self->get_log($advertiser_id);

    for my $ad_id ( keys %$reports ) {
        my $report = $reports->{$ad_id};
        my $log    = $logs->{$ad_id} || [];

        $report->{clicks} = scalar @$log;

        my $breakdown = {};

        $breakdown->{gender}      = {};
        $breakdown->{agents}      = {};
        $breakdown->{generations} = {};

        for my $row ( @$log ) {
            my $gender = $row->{gender} || 'unknown';
            $breakdown->{gender}->{$gender}++;

            my $agent = $row->{agent} || 'unknown';
            $breakdown->{agents}->{"$agent"}++;

            my $generation = 'unknown';
            if ( $row->{age} ) {
                $generation = int($row->{age} / 10 );
            }
            $breakdown->{generations}->{$generation}++;
        };


        $report->{breakdown} = $breakdown;
    }

    $c->render_json($reports);
};

post '/initialize' => sub {
    my ($self, $c) = @_;

    my @keys = $self->redis->keys('isu4:*');

    for my $key ( @keys ) {
        $self->redis->del($key);
    }

    $c->res->content_type('text/plain');
    $c->res->body('OK');
    return $c->res;
};

use Kossy::Exception;
sub Kossy::Exception::response {
    my $self = shift;
    return $self->{_response} if $self->{_response};

    my $code = $self->{code} || 500;
    my $message = $self->{message};
    $message ||= HTTP::Status::status_message($code);

    my @headers = (
         'Content-Type' => q!text/html; charset=UTF-8!,
    );

    if ($code =~ /^3/ && (my $loc = eval { $self->{location} })) {
        push(@headers, Location => $loc);
    }

    return Kossy::Response->new($code, \@headers, [$self->html($code,$message)])->finalize;
}

1;
