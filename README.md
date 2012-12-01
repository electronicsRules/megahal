megahal
=======

An IRC bot initially designed to proxy the eponymous conversational simulator.

Prerequisites
-------------
- Perl v5.16 recommended, v5.10 required.
Perl modules:
- AnyEvent
- AnyEvent::IRC
- EV
- YAML::Any (YAML::XS or YAML::Syck recommended)
- AnyEvent::ReadLine::Gnu
- Text::ParseWords
- Term::ANSIColor (latest - version bundled with perl may be out of date!)
- DBI, DBD::SQLite
- CHI, CHI::Driver::Memcached

Other:
- ssl/megahal.cert, ssl/megahal.cert.key should contain an SSL certificate. The certificate does not need to be signed.

TLSTelnet (telnet.pl) prerequisites
-----------------------------------
Perl modules:
- AnyEvent
- AnyEvent::ReadLine::Gnu
- Term::InKey
telnet.pl also depends on MegaHAL::Filehandle which is included in the distribution.