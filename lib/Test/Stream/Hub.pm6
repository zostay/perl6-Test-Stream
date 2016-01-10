use v6;

unit class Test::Stream::Hub;

use Test::Stream::Listener;
use Test::Stream::Suite;

has Test::Stream::Listener @.listeners;
# This is the current suite stack. We push and pop onto this as we go.
has Test::Stream::Suite @!suites;
# As we pop suites off @!suites we unshift them onto this so we always have
# access to them.
has Test::Stream::Suite @!finished-suites;

# My current thinking is that there should really just be one Hub per process
# in most scenarios. Different event producers and listeners can all attach to
# the one hub.
method instance ($class: |c) {
    return state $instance //= $class.new(|c);
}

method add-listener (Test::Stream::Listener:D $listener) {
    @.listeners.append($listener);
}

method remove-listener (Test::Stream::Listener:D $listener) {
    @.listeners = @.listeners.grep( { $_ !=== $listener } );
}

method start-suite (Str:D :$name) {
    self.send-event(
        Test::Stream::Event::Suite::Start.new(
            name => $name,
        )
    );

    my $suite = Test::Stream::Suite.new( name => $name );
    self.add-listener($suite);
    @!suites.append($suite);
}

method end-suite (Str:D :$name) {
    die "Attempted to end a suite ($name) before any suites were started"
        unless @!suites.elems;

    my $current = @!suites[*-1];
    die "Attempted to end a suite ($name) that is not the currently running suite ({$current.name})"
        unless $current.name eq $name;

    self.remove-listener($current);

    self.send-event(
        Test::Stream::Event::Suite::End.new(
            name          => $name,
            tests-planned => $current.tests-planned,
            tests-run     => $current.tests-run,
            tests-failed  => $current.tests-failed,
            passed        => $current.passed,
        )
    );

    @!suites.pop;
    @!finished-suites.append($current);

    return $current;
}

method send-event (Test::Stream::Event:D $event) {
    unless self!in-a-suite || $event.isa(Test::Stream::Event::Suite::Start) {
        die "Attempted to send a {$event.^name} event before any suites were started";
    }

    $event.set-source( Test::Stream::EventSource.new );

    .accept-event($event) for @.listeners;
}

method !in-a-suite (--> Bool:D) {
    return ?@!suites.elems;
}

class Status {
    has Int:D $.exit-code = 0;
    has Str:D $.error     = q{};
}

method finalize (--> Status:D) {
    # my $unfinished-suites = @!suites.elems;
    # self!end-current-suite while @!suites;

    # my $top-suite = @!finished-suites[0];

    # # The exit-code is going to be used as an actual process exit code so it
    # # cannot be greater than 254.

    # if $.bailed {
    #     return Status.new(
    #         exit-code => 255,
    #         error     => 'Bailed out' ~ ( $.bailed-reason ?? qq{ - $.bailed-reason} !! q{} ),
    #     );
    # }
    # elsif $top-suite.real-failure-count > 0 {
    #     my $failed = maybe-plural( $top-suite.real-failure-count, 'test' );
    #     my $error = "failed {$top-suite.real-failure-count} $failed";
    #     return Status.new(
    #         exit-code => min( 254, $top-suite.real-failure-count ),
    #         error     => $error,
    #     );

    # }
    # elsif $top-suite.planned
    #       && ( $top-suite.planned != $top-suite.tests-run ) {

    #     my $planned = maybe-plural( $top-suite.planned, 'test' );
    #     my $ran     = maybe-plural( $top-suite.tests-run, 'test' );
    #     return Status.new(
    #         exit-code => 255,
    #         error     => "planned {$top-suite.planned} $planned but ran {$top-suite.tests-run} $ran",
    #     );
    # }
    # elsif $unfinished-suites {
    #     my $unfinished = maybe-plural( $unfinished-suites, 'suite' );
    #     return Status.new(
    #         exit-code => 1,
    #         error     => "finalize was called but {@!suites.elems} $unfinished are still in process",
    #     );
    # }

    return Status.new(
        exit-code => 0,
        error     => q{},
    );
}
