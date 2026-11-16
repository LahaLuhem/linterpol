#!/bin/sh
# Silences the sun.misc.Unsafe warnings detekt's bundled Kotlin compiler prints on every run.
exec java --sun-misc-unsafe-memory-access=allow -jar /opt/detekt/detekt-cli.jar "$@"
