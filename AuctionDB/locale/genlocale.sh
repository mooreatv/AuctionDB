#! /usr/bin/bash
# Generate the base files for each locale

FILES=$(grep "Script file=" locale.xml | sed -e 's/^[^"]*"//g' -e 's/".*$//g')

echo "Creating $FILES"
for fn in $FILES; do
    l=${fn%%.*}
    echo "Working on $fn ($l)"
    cat > $fn <<__END__
-- Generated file, do not edit.
local addon, _ns = ...

if (GetLocale() ~= '$l') then return end

local L = _G[addon].L
--@localization(locale="$l", format="lua_additive_table", same-key-is-true=true, handle-unlocalized="ignore")@
__END__
done
