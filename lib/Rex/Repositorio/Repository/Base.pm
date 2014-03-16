#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Repositorio::Repository::Base;

use Moose;
use Try::Tiny;
use common::sense;
use Carp;
use English;
use LWP::UserAgent;
use XML::LibXML;
use XML::Simple;
use Params::Validate qw(:all);
use IO::All;
use File::Path;
use File::Basename qw'dirname';
use File::Spec;
use File::Copy;

has app  => ( is => 'ro' );
has repo => ( is => 'ro' );

sub download_gzip {
  my ( $self, $url ) = @_;

  my $content = $self->download($url);

  require Compress::Zlib;

  $self->app->logger->debug("Starting uncompressing of: $url");

  my $un_content = Compress::Zlib::memGunzip($content);
  $self->app->logger->debug("Finished uncompressing of: $url");
  if ( !$un_content ) {
    $self->app->logger->error("Error uncompressing data.");
    confess "Error uncompressing data.";
  }

  return $un_content;
}

sub download {
  my ( $self, $url ) = @_;

  $self->app->logger->debug("Starting download of: $url");
  my $resp = $self->app->ua->get($url);
  $self->app->logger->debug("Finished download of: $url");

  if ( !$resp->is_success ) {
    $self->app->logger->error("Can't download $url.");
    $self->app->logger->error( "Status: " . $resp->status_line );
    confess "Error downloading $url.";
  }

  return $resp->content;
}

sub get_xml {
  my ( $self, $xml ) = @_;
  return XML::LibXML->load_xml( string => $xml );
}

sub decode_xml {
  my ( $self, $xml ) = @_;
  return XMLin( $xml, ForceArray => 1 );
}

sub download_package {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      name => {
        type => SCALAR
      },
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF,
        optional => 1,
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      }
    }
  );

  my $package_file =
    $self->app->config->{RepositoryRoot} . "/head/" . $option{dest};
  $self->_download_binary_file(
    dest  => $package_file,
    url   => $option{url},
    cb    => $option{cb},
    force => $option{force},
  );
}

sub download_metadata {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF,
        optional => 1,
      },
      force => {
        type     => BOOLEAN,
        optional => 1,
      }
    }
  );

  my $metadata_file =
    $self->app->config->{RepositoryRoot} . "/head/" . $option{dest};
  $self->_download_binary_file(
    dest  => $metadata_file,
    url   => $option{url},
    cb    => $option{cb},
    force => $option{force},
  );
}

sub _download_binary_file {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      url => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      },
      cb => {
        type     => CODEREF | UNDEF,
        optional => 1,
      },
      force => {
        type => BOOLEAN
      }
    }
  );

  $self->app->logger->debug("Downloading: $option{url} -> $option{dest}");

  mkpath( dirname( $option{dest} ) ) if ( !-d dirname $option{dest} );

  if ( -f $option{dest} && !$option{force} ) {
    $self->app->logger->debug("Skipping $option{url}. File aready exists.");
    return;
  }

  if ( !-w dirname( $option{dest} ) ) {
    $self->app->logger->error( "Can't write to " . dirname( $option{dest} ) );
    confess "Can't write to " . dirname( $option{dest} );
  }

  if ( -f $option{dest} && $option{force} ) {
    unlink $option{dest};
  }

  open my $fh, ">", $option{dest};
  binmode $fh;
  my $resp = $self->app->ua->get(
    $option{url},
    ':content_cb' => sub {
      my ( $data, $response, $protocol ) = @_;
      print $fh $data;
    }
  );
  close $fh;

  if ( !$resp->is_success ) {
    $self->app->logger->error("Can't download $option{url}.");
    $self->app->logger->error( "Status: " . $resp->status_line );
    confess "Error downloading $option{url}.";
  }

  $option{cb}->( $option{dest} ) if ( exists $option{cb} && $option{cb} );
}

sub add_file_to_repo {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      source => {
        type => SCALAR
      },
      dest => {
        type => SCALAR
      }
    }
  );

  if ( !-f $option{source} ) {
    $self->app->logger->error("Fild $option{source} not found.");
    confess "Fild $option{source} not found.";
  }

  $self->app->logger->debug("Copy $option{source} -> $option{dest}");
  my $ret = copy $option{source}, $option{dest};
  if ( !$ret ) {
    $self->app->logger->error(
      "Error copying file $option{source} to $option{dest}");
    confess "Error copying file $option{source} to $option{dest}";
  }
}

sub remove_file_from_repo {
  my $self   = shift;
  my %option = validate(
    @_,
    {
      file => {
        type => SCALAR
      }
    }
  );

  if ( !-f $option{file} ) {
    $self->app->logger->error("Fild $option{file} not found.");
    confess "Fild $option{file} not found.";
  }

  $self->app->logger->debug("Deleting $option{file}.");
  my $ret = unlink $option{file};
  if ( !$ret ) {
    $self->app->logger->error("Error deleting file $option{file}");
    confess "Error deleting file $option{file}";
  }
}

1;
