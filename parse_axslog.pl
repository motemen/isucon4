#!/usr/bin/env perl
use utf8;
use strict;
use warnings;

my $logfile = $ARGV[0] or die "log file reuqire";
my $taken_key = $ARGV[1] || 'taken';

open(my $logfh, '<', $logfile);

my $kv_array = [];
while (my $line = readline $logfh) {
    chomp $line;
    my $kv = {};
    for my $item (split '\t', $line) {
        my ($k, $v) = split ':', $item;
        if ($k eq 'req') {
            $v =~ s</\d+/></*/>;
            $v =~ s</\d+ ></* >;
            $v =~ s<([A-Z]+ /slots/)[^/]+(/\w+)><$1*$2>;
        }
        $kv->{$k} = $v;
    }
    push @$kv_array, $kv;
}

my $req_to_taken = {};
my $req_to_count = {};
for my $kv (@$kv_array) {
    $req_to_count->{$kv->{req}} //= 0;
    $req_to_count->{$kv->{req}} += 1;
    $req_to_taken->{$kv->{req}} //= 0;
    $req_to_taken->{$kv->{req}} += $kv->{$taken_key};
}

my @req_to_takens = map { {
    req   => $_,
    taken => sprintf('%.2f', $req_to_taken->{$_}),
    count => $req_to_count->{$_},
} } keys %$req_to_taken;

for my $row (sort { $b->{taken} <=> $a->{taken} } @req_to_takens) {
    my $avg_taken = sprintf('%.2f', $row->{taken} / $row->{count});
    print "req:$row->{req} taken_sum:$row->{taken} req_count:$row->{count} avg_taken:$avg_taken\n";
}
