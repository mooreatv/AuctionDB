#! /usr/bin/bash
# Generate the base files for each locale

FILES=$(grep "Script file=" locale.xml | sed -e 's/^[^"]*"//g' -e 's/".*$//g')

echo "Creating $FILES"
for fn in $FILES; do
    l=${fn%%.*}
    echo "Working on $fn ($l)"
    echo "-- Generated file, do not edit." > $fn
    echo "if (GetLocale() ~= '$l') then return end" >> $fn
    echo "--@localization(locale=\"$l\", format=\"lua_additive_table\", same-key-is-true=true, handle-unlocalized=\"ignore\")@" >> $fn
done
