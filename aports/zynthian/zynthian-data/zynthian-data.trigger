#!/bin/sh
# A plugin package installed or upgraded its bundle (and replaced an adjusted TTL): apply
# zynthian-data's lv2-custom TTLs again, to the changed bundles only
zynthian-lv2-custom -q "$@" || echo "zynthian-lv2-custom failed (plugins keep their own TTLs)"
exit 0
