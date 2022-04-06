#! /usr/bin/perl

    
    require 5;
    use strict;
    use warnings;
    use utf8;


    package HDiet::trendfit;

    require Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw(new start addPoint fitSlope);
    1;

    sub new {
        my $self = {};
        my ($invocant) = @_;
        my $class = ref($invocant) || $invocant;

        bless($self, $class);

        $self->start();

        return $self;
    }

    sub start {
        my $self = shift;

        $self->{n} = 0;
        $self->{s1} = $self->{s2} = $self->{s3} = $self->{s4} = 0;
        $self->{min} = 1E308;
        $self->{max} = -1E308;
    }

    sub addPoint {
        my $self = shift;

        my $v;
        foreach $v (@_) {
            $self->{s1} += ($self->{n} + 1) * $v;
            $self->{s2} += ($self->{n} + 1);
            $self->{s3} += $v;
            $self->{s4} += ($self->{n} + 1) ** 2;
            $self->{n}++;
            $self->{min} = ::min($self->{min}, $v);
            $self->{max} = ::max($self->{max}, $v);
        }
    }

    sub fitSlope {
        my $self = shift;

        my $denom = (($self->{s4} * $self->{n}) - ($self->{s2} ** 2));
        return 0 if $denom == 0;
        return (($self->{s1} * $self->{n}) - ($self->{s2} * $self->{s3})) /
                $denom;
    }

    sub minMaxMean {
        my $self = shift;

        return ($self->{min}, $self->{max}, ($self->{s3} / $self->{n}));
    }
