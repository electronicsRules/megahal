#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008-2013 -- leonerd@leonerd.org.uk

package Net::Async::HTTP::Protocol;

use strict;
use warnings;

our $VERSION = '0.25';

use Carp;

use base qw( IO::Async::Protocol::Stream );

use HTTP::Response;

my $CRLF = "\x0d\x0a"; # More portable than \r\n

# Indices into responder/ready queue elements
use constant ON_READ  => 0;
use constant ON_ERROR => 1;

# Detect whether HTTP::Message properly trims whitespace in header values. If
# it doesn't, we have to deploy a workaround to fix them up.
#   https://rt.cpan.org/Ticket/Display.html?id=75224
use constant HTTP_MESSAGE_TRIMS_LWS => HTTP::Message->parse( "Name:   value  " )->header("Name") eq "value";

=head1 NAME

C<Net::Async::HTTP::Protocol> - HTTP client protocol handler

=head1 DESCRIPTION

This class provides a connection to a single HTTP server, and is used
internally by L<Net::Async::HTTP>. It is not intended for general use.

=cut

sub _init
{
   my $self = shift;

   $self->{requests_in_flight} = 0;
}

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( pipeline max_in_flight ready_queue )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   if( my $on_closed = $params{on_closed} ) {
      $params{on_closed} = sub {
         my $self = shift;

         $self->debug_printf( "CLOSED" );

         $on_closed->( $self );
      };
   }

   croak "max_in_flight parameter required, may be zero" unless defined $self->{max_in_flight};

   $self->SUPER::configure( %params );
}

sub setup_transport
{
   my $self = shift;
   my ( $transport ) = @_;
   $self->SUPER::setup_transport( $transport );

   $self->debug_printf( "CONNECTED" );
   $self->ready;
}

sub should_pipeline
{
   my $self = shift;
   return $self->{pipeline} &&
          $self->{can_pipeline} &&
          ( !$self->{max_in_flight} || $self->{requests_in_flight} < $self->{max_in_flight} );
}

sub connect
{
   my $self = shift;
   my %args = @_;

   $self->debug_printf( "CONNECT $args{host}:$args{service}" );

   $self->SUPER::connect( %args );
}

sub ready
{
   my $self = shift;

   my $queue = $self->{ready_queue} or return;

   if( $self->should_pipeline ) {
      $self->debug_printf( "READY pipelined" );
      ( shift @$queue )->done( $self ) while @$queue && $self->should_pipeline;
   }
   elsif( @$queue and $self->is_idle ) {
      $self->debug_printf( "READY non-pipelined" );
      ( shift @$queue )->done( $self );
   }
   else {
      $self->debug_printf( "READY cannot-run queue=%d idle=%s",
         scalar @$queue, $self->is_idle ? "Y" : "N");
   }
}

sub is_idle
{
   my $self = shift;
   return $self->{requests_in_flight} == 0;
}

sub _request_done
{
   my $self = shift;
   $self->{requests_in_flight}--;
   $self->debug_printf( "DONE remaining in-flight=$self->{requests_in_flight}" );
   $self->ready;
}

sub on_read
{
   my $self = shift;
   my ( $buffref, $closed ) = @_;

   if( my $head = $self->{responder_queue}[0] ) {
      my $ret = $head->[ON_READ]->( $self, $buffref, $closed );

      if( defined $ret ) {
         return $ret if !ref $ret;

         $head->[ON_READ] = $ret;
         return 1;
      }

      shift @{ $self->{responder_queue} };
      return 1 if !$closed and length $$buffref;
      return;
   }

   # Reinvoked after switch back to baseline, but may be idle again
   return if $closed or !length $$buffref;

   croak "Spurious on_read of connection while idle\n";
}

sub on_write_eof
{
   my $self = shift;
   $self->error_all( "Connection closed" );
}

sub error_all
{
   my $self = shift;

   while( my $head = shift @{ $self->{responder_queue} } ) {
      $head->[ON_ERROR]->( @_ );
   }
}

sub request
{
   my $self = shift;
   my %args = @_;

   my $on_header = $args{on_header} or croak "Expected 'on_header' as a CODE ref";

   my $req = $args{request};
   ref $req and $req->isa( "HTTP::Request" ) or croak "Expected 'request' as a HTTP::Request reference";

   $self->debug_printf( "REQUEST %s", $req->uri );

   my $request_body = $args{request_body};
   my $expect_continue = !!$args{expect_continue};

   my $method = $req->method;

   if( $method eq "POST" or $method eq "PUT" or length $req->content ) {
      $req->init_header( "Content-Length", length $req->content );
   }

   if( $expect_continue ) {
      $req->init_header( "Expect", "100-continue" );
   }

   my $f = $self->loop->new_future;

   my $on_read = sub {
      my ( $self, $buffref, $closed ) = @_;

      unless( $$buffref =~ s/^(.*?$CRLF$CRLF)//s ) {
         if( $closed ) {
            $self->debug_printf( "ERROR closed" );
            $f->fail( "Connection closed while awaiting header" ) unless $f->is_cancelled || $f->is_ready;
         }
         return 0;
      }

      my $header = HTTP::Response->parse( $1 );

      unless( HTTP_MESSAGE_TRIMS_LWS ) {
         my @headers;
         $header->scan( sub {
            my ( $name, $value ) = @_;
            s/^\s+//, s/\s+$// for $value;
            push @headers, $name => $value;
         } );
         $header->header( @headers ) if @headers;
      }

      my $protocol = $header->protocol;
      if( $protocol =~ m{^HTTP/1\.(\d+)$} and $1 >= 1 ) {
         $self->{can_pipeline} = 1;
      }

      if( $header->code =~ m/^1/ ) { # 1xx is not a final response
         $self->debug_printf( "HEADER [provisional] %s", $header->status_line );
         $self->write( $request_body ) if $request_body and $expect_continue;
         return 1;
      }

      $header->request( $req );
      $header->previous( $args{previous_response} ) if $args{previous_response};

      $self->debug_printf( "HEADER %s", $header->status_line );

      my $on_body_chunk = $on_header->( $header );

      my $code = $header->code;

      # can_pipeline is set for HTTP/1.1 or above; presume it can keep-alive if set
      my $connection_close = lc( $header->header( "Connection" ) || ( $self->{can_pipeline} ? "keep-alive" : "close" ) )
                              eq "close";

      if( $connection_close ) {
         $self->{max_in_flight} = 1;
      }
      elsif( defined( my $keep_alive = lc( $header->header("Keep-Alive") || "" ) ) ) {
         my ( $max ) = ( $keep_alive =~ m/max=(\d+)/ );
         $self->{max_in_flight} = $max if $max && $max < $self->{max_in_flight};
      }

      # RFC 2616 says "HEAD" does not have a body, nor do any 1xx codes, nor
      # 204 (No Content) nor 304 (Not Modified)
      if( $method eq "HEAD" or $code =~ m/^1..$/ or $code eq "204" or $code eq "304" ) {
         $self->debug_printf( "BODY done" );
         $self->close if $connection_close;
         $f->done( $on_body_chunk->() ) unless $f->is_cancelled;
         $self->_request_done;
         return undef; # Finished
      }

      my $transfer_encoding = $header->header( "Transfer-Encoding" );
      my $content_length    = $header->content_length;

      if( defined $transfer_encoding and $transfer_encoding eq "chunked" ) {
         $self->debug_printf( "BODY chunks" );

         my $chunk_length;

         return sub {
            my ( $self, $buffref, $closed ) = @_;

            if( !defined $chunk_length and $$buffref =~ s/^([A-Fa-f0-9]+).*?$CRLF// ) {
               # Chunk header
               $chunk_length = hex( $1 );
               return 1 if $chunk_length;

               my $trailer = "";

               # Now the trailer
               return sub {
                  my ( $self, $buffref, $closed ) = @_;

                  if( $closed ) {
                     $self->debug_printf( "ERROR closed" );
                     $f->fail( "Connection closed while awaiting chunk trailer" ) unless $f->is_cancelled;
                  }

                  $$buffref =~ s/^(.*)$CRLF// or return 0;
                  $trailer .= $1;

                  return 1 if length $1;

                  # TODO: Actually use the trailer

                  $self->debug_printf( "BODY done" );
                  $f->done( $on_body_chunk->() ) unless $f->is_cancelled;
                  $self->_request_done;
                  return undef; # Finished
               }
            }

            # Chunk is followed by a CRLF, which isn't counted in the length;
            if( defined $chunk_length and length( $$buffref ) >= $chunk_length + 2 ) {
               # Chunk body
               my $chunk = substr( $$buffref, 0, $chunk_length, "" );
               undef $chunk_length;

               unless( $$buffref =~ s/^$CRLF// ) {
                  $self->debug_printf( "ERROR chunk without CRLF" );
                  $f->fail( "Chunk of size $chunk_length wasn't followed by CRLF" ) unless $f->is_cancelled;
                  $self->close;
               }

               $on_body_chunk->( $chunk );

               return 1;
            }

            if( $closed ) {
               $self->debug_printf( "ERROR closed" );
               $f->fail( "Connection closed while awaiting chunk" ) unless $f->is_cancelled;
            }
            return 0;
         };
      }
      elsif( defined $content_length ) {
         $self->debug_printf( "BODY length $content_length" );

         if( $content_length == 0 ) {
            $self->debug_printf( "BODY done" );
            $f->done( $on_body_chunk->() ) unless $f->is_cancelled;
            $self->_request_done;
            return undef; # Finished
         }

         return sub {
            my ( $self, $buffref, $closed ) = @_;

            # This will truncate it if the server provided too much
            my $content = substr( $$buffref, 0, $content_length, "" );

            $on_body_chunk->( $content );

            $content_length -= length $content;

            if( $content_length == 0 ) {
               $self->debug_printf( "BODY done" );
               $self->close if $connection_close;
               $f->done( $on_body_chunk->() ) unless $f->is_cancelled;
               $self->_request_done;
               return undef;
            }

            if( $closed ) {
               $self->debug_printf( "ERROR closed" );
               $f->fail( "Connection closed while awaiting body" ) unless $f->is_cancelled;
            }
            return 0;
         };
      }
      else {
         $self->debug_printf( "BODY until EOF" );

         return sub {
            my ( $self, $buffref, $closed ) = @_;

            $on_body_chunk->( $$buffref );
            $$buffref = "";

            return 0 unless $closed;

            # TODO: IO::Async probably ought to do this. We need to fire the
            # on_closed event _before_ calling on_body_chunk, to clear the
            # connection cache in case another request comes - e.g. HEAD->GET
            $self->close;

            $self->debug_printf( "BODY done" );
            $f->done( $on_body_chunk->() ) unless $f->is_cancelled;
            # $self already closed
            $self->_request_done;
            return undef;
         };
      }
   };

   # Unless the request method is CONNECT, the URL is not allowed to contain
   # an authority; only path
   # Take a copy of the headers since we'll be hacking them up
   my $headers = $req->headers->clone;
   my $path;
   if( $method eq "CONNECT" ) {
      $path = $req->uri->as_string;
   }
   else {
      my $uri = $req->uri;
      $path = $uri->path_query;
      $path = "/$path" unless $path =~ m{^/};
      $headers->init_header( Host => $uri->authority );
   }

   my $protocol = $req->protocol || "HTTP/1.1";
   my @headers = ( "$method $path $protocol" );
   $headers->scan( sub { push @headers, "$_[0]: $_[1]" } );

   $self->write( join( $CRLF, @headers ) .
                 $CRLF . $CRLF .
                 $req->content );

   $self->write( $request_body ) if $request_body and !$expect_continue;

   $self->{requests_in_flight}++;

   push @{ $self->{responder_queue} }, [ $on_read, $f->fail_cb ];

   return $f;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
