#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

use Capture::Tiny qw(capture_stdout);
use Crypt::Passphrase ();
use Crypt::Passphrase::Argon2 ();
use Data::Dumper::Compact qw(ddc);
use Encoding::FixLatin qw(fix_latin);
use JSON::MaybeXS qw(decode_json encode_json);
use Mojo::SQLite;

helper is_demo => sub ($c) { # for use in the template
  my $user = $c->session('user');
  return $user eq 'guest' ? 1 : 0;
};

helper fix_latin => sub ($c, $string) { # for use in the template
  return fix_latin($string);
};

helper auth => sub {
  my $c = shift;
  my $user = $c->param('username');
  my $pass = $c->param('password');
  return 0 unless $user && $pass;
  my $sql = Mojo::SQLite->new('sqlite:bible.db');
  my $record = $sql->db->query('select id, name, password from account where name = ?', $user)->hash;
  my $password = $record ? $record->{password} : undef;
  my $authenticator = Crypt::Passphrase->new(encoder => 'Argon2');
  if (!$authenticator->verify_password($pass, $password)) {
    return 0;
  }
  $c->session(auth => 1);
  $c->session(user => $record->{name});
  $c->session(user_id => $record->{id});
  return 1;
};

get '/' => sub { shift->redirect_to('login') } => 'index';

get '/signup' => sub { shift->render } => 'signup';

post '/signup' => sub {
  my $c = shift;
  my $user = $c->param('username');
  my $sql = Mojo::SQLite->new('sqlite:bible.db');
  my $record = $sql->db->query('select id from account where name = ?', $user)->hash;
  if ($record) {
    $c->flash('error' => 'Username unavailable');
    return $c->redirect_to('signup');
  }
  $c->redirect_to('login');
} => 'fresh';

get '/login' => sub { shift->render } => 'login';

post '/login' => sub {
  my $c = shift;
  if ($c->auth) {
    return $c->redirect_to('bible');
  }
  $c->flash('error' => 'Invalid login');
  $c->redirect_to('login');
} => 'auth';

get '/logout' => sub {
  my $c = shift;
  delete $c->session->{auth};
  delete $c->session->{user};
  delete $c->session->{user_id};
  $c->session(expires => 1);
  $c->cookie(choice => '', { samesite => 'Lax' });
  $c->cookie(crumbs => '', { samesite => 'Lax' });
  $c->redirect_to('login');
} => 'logout';

under sub {
  my $c = shift;
  return 1 if ($c->session('auth') // '') eq '1';
  $c->redirect_to('login');
  return undef;
};

get '/bible' => sub ($c) {
  my $action = $c->param('action') || '';  # user action
  my $seek   = $c->param('seek') || 'love';    # user seeking
  my $interp = $c->param('interp') || '';  # interpretation
  my $version = $c->param('version') || 'New International Version';  # bible version

  my $user_id = $c->session('user_id');
  my $sql = Mojo::SQLite->new('sqlite:bible.db');

  my $interpretation = ''; # AI interpretation

  my $responses = [];
  unless ($c->is_demo) {
    $interpretation = _interpret($seek, $version)
      if $action eq 'interp';
  }

  my @versions = (
    '1611 King James Version',
    '1789 King James Version',
    'Douay-Rheims Version',
    'English Standard Version',
    "Erasmus' second edition of the Latin New Testament",
    'Geneva',
    'Hebrew',
    "Jerome's 4th-century Latin Vulgate Version",
    'Latter-day Saint edition of the King James Version',
    'New American Standard',
    'New English',
    'New International Version',
    'New King James Version',
    'New Revised Standard Version',
    'New Revised Standard Version, Catholic Edition',
    'New World Translation of the Holy Scriptures',
    'The original Greek New Testament',
    'The Revised English',
    'Revised Version',
    'The Septuagint',
    'Tyndale',
    "Wyclif's",
  );

  $c->render(
    template => 'bible',
    interp   => $interpretation,
    can_chat => $ENV{OPENAI_API_KEY} ? 1 : 0,
    seek     => $seek,
    mobile   => $c->browser->mobile ? 1 : 0,
    version  => $version,
    versions => \@versions,
  );
} => 'bible';

sub _interpret ($seeking, $version) {
  my $prompt = "You are a Bible scholar. Generate a high quality $version Bible reading concerning '$seeking', quoting specific verses.";
  $prompt .= <<"PROMPT";

VOICE RULES:
- Skip ALL standard AI openings ('let's dive in, delve into' etc.)
- Jump straight into the bible-verse advice
- Talk like a traditional bible scholar, not a corporate chatbot

READING STRUCTURE:
- Build a flowing narrative between verses
- Balance mystery with clear insights

ALWAYS INCLUDE:
- Verses from the $version Bible only

ABSOLUTELY AVOID:
- Using any preamble or introductory text
- Academic language
- Customer service politeness
- Meta-commentary about the advice
- Fancy vocabulary
- Cookie-cutter transitions
- Hedging words (perhaps/maybe/might)
- ANY intro phrases or other narrative devices common to AI
- Suggesting the creation of a vision board, list, or journal.
PROMPT
  my $response = _get_response('user', $prompt);
  $response =~ s/\*\*//g;
  $response =~ s/##+//g;
  $response =~ s/\n+/<p><\/p>/g;
  return $response;
}

sub _get_response ($role, $prompt) {
  return unless $prompt;
  my @message = { role => $role, content => $prompt };
  my $json_string = encode_json([@message]);
  my @cmd = (qw(python3 chat.py), $json_string);
  my $stdout = capture_stdout { system(@cmd) };
  chomp $stdout;
  return $stdout;
}

app->plugin('browser_detect');
app->log->level('debug');

app->start;

__DATA__

@@ signup.html.ep
% layout 'default';
% title 'Bible Signup';
% if (flash('error')) {
  <h2 style="color:red"><%= flash('error') %></h2>
% }
<p></p>
<form action="<%= url_for('fresh') %>" method="post">
  <div class="form-check">
    <input class="form-check-input" type="radio" name="plan" id="plan1">
    <label class="form-check-label" for="plan1">
      One day for $5 USD
    </label>
  </div>
  <div class="form-check">
    <input class="form-check-input" type="radio" name="plan" id="plan2">
    <label class="form-check-label" for="plan2">
      One week for $14 USD
    </label>
  </div>
  <div class="form-check">
    <input class="form-check-input" type="radio" name="plan" id="plan3" checked>
    <label class="form-check-label" for="plan3">
      One month for $30 USD
    </label>
  </div>
  <div class="form-check">
    <input class="form-check-input" type="radio" name="plan" id="plan4">
    <label class="form-check-label" for="plan4">
      One year for $200 USD
    </label>
  </div>
  <p></p>
  <input class="form-control" type="email" name="email" placeholder="Email address" required>
  <p></p>
  <input class="form-control" type="text" name="username" placeholder="Desired username" required>
  <p></p>
  <input class="form-control" type="password" name="password" placeholder="Desired password" required>
  <p></p>
  <input class="form-control" type="password_again" name="password" placeholder="Retype password" required>
  <p></p>
  <input class="form-control btn btn-sm btn-primary" type="submit" name="submit" value="Submit">
</form>

@@ login.html.ep
% layout 'default';
% title 'Login';
% if (flash('error')) {
  <h2 style="color:red"><%= flash('error') %></h2>
% }
<p></p>
<form action="<%= url_for('auth') %>" method="post">
  <input class="form-control" type="text" name="username" placeholder="Username">
  <br>
  <input class="form-control" type="password" name="password" placeholder="Password">
  <br>
  <input class="form-control btn btn-sm btn-primary" type="submit" name="submit" value="Login">
</form>

@@ bible.html.ep
% layout 'default';
% title 'Bible Scholar AI';

<p></p>

% # Interpret
%   if ($can_chat) {
  <form method="get">
    <select name="version" class="form-control">
      <option value="">Bible version...</option>
%     for my $v (@$versions) {
      <option value="<%= $v %>" <%= $v eq $version ? 'selected' : '' %>><%= $v %></option>
%     }
    </select>
    <p></p>
    <textarea class="form-control" name="seek" placeholder="What biblical concepts do you have questions about?"><%= $seek %></textarea>
    <p></p>
%     if (is_demo()) {
    <a type="button" href="<%= url_for('signup') %>" title="Interpret this reading" class="btn btn-sm btn-info">Interpret</a>
%     }
%     else {
    <button type="submit" name="action" title="Interpret this reading" value="interp" class="btn btn-sm btn-info" id="interp">
      Ask</button>
%     }
  </form>
%   }
<p></p>

% # Response
% if ($interp) {
    <%== fix_latin($interp) %>
% }

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/png" href="/favicon.ico">
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css" integrity="sha384-Gn5384xqQ1aoWXA+058RXPxPg6fy4IWvTNh0E263XmFcJlSAwiGgFAW/dAiS6JXm" crossorigin="anonymous" onerror="this.onerror=null;this.href='/css/bootstrap.min.css';" />
    <script src="https://cdn.jsdelivr.net/npm/jquery@3.7.0/dist/jquery.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@4.6.2/dist/js/bootstrap.min.js" integrity="sha384-+sLIOodYLS7CIrQpBjl+C7nPvqq+FbNUBDunl/OZv93DB7Ln/533i8e/mZXLi/P+" crossorigin="anonymous"></script>
    <link rel="stylesheet" href="/css/style.css">
    <title><%= title %></title>
    <script>
    $(document).ready(function() {
      $("#interp").click(function() {
        $('#loading').show();
      });
    });
    $(window).on('load', function() {
        $('#loading').hide();
    })
    </script>
  </head>
  <body>
    <div id="loading">
      <img id="loading-image" src="/loading.gif" alt="Loading..." />
    </div>

    <div class="container padpage">
      <h3><a href="<%= url_for('bible') %>"><%= title %></a></h3>
      <%= content %>
      <p></p>
      <div id="footer" class="small">
        <hr>
        Built by <a href="http://gene.ology.net/">Gene</a>
        with <a href="https://www.perl.org/">Perl</a> and
        <a href="https://mojolicious.org/">Mojolicious</a>
        |
% if (session('user')) {
        <a href="<%= url_for('logout') %>">Logout</a>
% }
% else {
        <a href="<%= url_for('signup') %>">Signup</a>
% }
      </div>
      <p></p>
    </div>
  </body>
</html>
