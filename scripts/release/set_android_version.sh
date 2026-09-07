#!/usr/bin/env bash
set -euo pipefail

manifest=${1:-once.toml}
version=${VERSION:?Set VERSION}
build_number=${BUILD_NUMBER:?Set BUILD_NUMBER}

perl -0pi -e '
  BEGIN { $found = 0 }
  s{(\[\[target\]\]\nname = "HiveAndroidRelease"\n.*?)(?=\n\[\[target\]\]|\z)}{
    my $target = $1;
    my $codes = ($target =~ s/version_code = \d+/version_code = $ENV{BUILD_NUMBER}/g);
    my $names = ($target =~ s/version_name = "[^"]*"/version_name = "$ENV{VERSION}"/g);
    die "Expected exactly one Android version code and name\n" unless $codes == 1 && $names == 1;
    $found = 1;
    $target;
  }gse;
  END { die "HiveAndroidRelease target not found\n" unless $found }
' "$manifest"

grep -A30 'name = "HiveAndroidRelease"' "$manifest" | grep -F "version_code = $build_number" >/dev/null
grep -A30 'name = "HiveAndroidRelease"' "$manifest" | grep -F "version_name = \"$version\"" >/dev/null
