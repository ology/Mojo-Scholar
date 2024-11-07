#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

use_ok 'Bible';

subtest default => sub {
  ok 1, 'pass';
};

done_testing();
