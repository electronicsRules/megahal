megahal
=======

An IRC bot initially designed to proxy the eponymous conversational simulator.

Prerequisites
-------------
- Perl v5.16 recommended, v5.10 required.
<h3>Core</h3>
Perl modules:
- AnyEvent
- AnyEvent::IRC
- EV (AnyEvent does not provide EV::run EV::RUN_NOWAIT and a few other corner-case features - besides, EV is the fastest and most feature-complete event loop supported by AE.)
- Net::Async::HTTP
- YAML::Any (YAML::XS or YAML::Syck recommended)
- AnyEvent::ReadLine::Gnu
- Text::ParseWords
- Term::ANSIColor (latest - version bundled with perl may be out of date!)
- DBI, DBD::SQLite
- CHI, CHI::Driver::Memcached (and, preferably, a memcached daemon running on /tmp/memcached.sock - a small "L1" in-memory cache is also used and the memcached address/socket will be configurable later.)
<h3>Plugins</h3>
- XML::Bare
- JSON::Any (JSON::XS recommended)
- Date::Format
- AnyEvent::Handle::UDP

Other:
- ssl/megahal.cert, ssl/megahal.cert.key should contain an SSL certificate. The certificate does not need to be signed.

TLSTelnet (telnet.pl) prerequisites
-----------------------------------
Perl modules:
- AnyEvent
- AnyEvent::ReadLine::Gnu
- Term::InKey

telnet.pl also depends on MegaHAL::Filehandle which is included in the distribution.

Roadmap
=======
- Proper centralised command handling, including a (paged) help system
- Fix ACL/permissions! At the moment they're a patchwork mess (especially the server field, which at the moment stands for originating server, but we may need support for command-target servers later...)
