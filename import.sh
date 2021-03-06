#!/bin/bash
set -e

gcc -Wall -Werror geosupport/blockface.c -L/opt/geosupport/lib/ -lgeo -lapequiv -ledequiv -lsan -lsnd -lstExcpt -lStdLast -lStdUniv -lstEnder -lstretch -lthined -lm -lc -lgcc_s -ldl -o blockface

dropdb --if-exists parking
createdb parking -T postgis_template

psql -v ON_ERROR_STOP=1 -f multiline_functions.sql parking

echo "import tables..."

ogr2ogr -f "PostgreSQL" PG:"dbname=parking" -overwrite -nln location -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES import/locations.csv
iconv -f latin1 -t utf-8 import/signs.csv | ogr2ogr -f "PostgreSQL" PG:"dbname=parking" -overwrite -nln import_sign -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES CSV:/vsistdin/
ogr2ogr import/lion.shp import/lion/lion.gdb lion
shp2pgsql -I -D -s 2263 import/lion.shp street_segment | psql -v ON_ERROR_STOP=1 parking
shp2pgsql -I -D -s 2263 import/nybb.shp borough | psql -v ON_ERROR_STOP=1 parking
shp2pgsql -I -D -s 2263 import/nyct2010wi.shp census_tract | psql -v ON_ERROR_STOP=1 parking
shp2pgsql -I -D -s 2263 import/nycb2010wi.shp census_block | psql -v ON_ERROR_STOP=1 parking
shp2pgsql -I -D -s 4326 -m import/columns.txt import/Parking_Regulation_Shapefile/Parking_Regulation_Shapefile.shp parking_regulation | psql -v ON_ERROR_STOP=1 parking
shp2pgsql -I -D -s 2263 import/DEPHydrants/DEPHYDRANTS.shp hydrant | psql -v ON_ERROR_STOP=1 parking

shp2pgsql -I -D -s 2263 import/MapPLUTO.shp pluto | psql -v ON_ERROR_STOP=1 parking
ogr2ogr -f "PostgreSQL" PG:"dbname=parking" -overwrite -nln import_garage -lco GEOMETRY_NAME=geom -oo X_POSSIBLE_NAMES=longitude -oo Y_POSSIBLE_NAMES=latitude -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES import/Active_DCA-Licensed_Garages_and_Parking_Lots.csv

ogr2ogr -f "PostgreSQL" PG:"dbname=parking" -overwrite -nln import_employment -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES import/census/NY_2012thru2016_A202105.csv
ogr2ogr -f "PostgreSQL" PG:"dbname=parking" -overwrite -nln import_vehicle_ownership -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES import/census/vehicle_ownership.csv

psql -v ON_ERROR_STOP=1 -f import.sql parking

echo "calculate blockface geometry..."

psql -v ON_ERROR_STOP=1 -f blockface_geom.sql parking

echo "hydrant positions..."

psql -v ON_ERROR_STOP=1 -f blockface_hydrant.sql parking

echo "map order_no to blockfaces..."

psql -v ON_ERROR_STOP=1 -f order_segment.sql parking
php -f index.php order_segment
# run this multiple times to try to get order_segment to be a one-to-one mapping 
psql -v ON_ERROR_STOP=1 -f order_segment_post.sql parking
psql -v ON_ERROR_STOP=1 -f order_segment_post.sql parking
psql -v ON_ERROR_STOP=1 -f order_segment_post.sql parking

echo "interpret signs..."

psql -v ON_ERROR_STOP=1 -f supersedes.sql parking
psql -v ON_ERROR_STOP=1 -f sign_regulation.sql parking
php -f index.php interpret_signs

echo "calculate garage spaces..."

psql -v ON_ERROR_STOP=1 -f offstreet_parking.sql parking

echo "calculate parking spaces..."

psql -v ON_ERROR_STOP=1 -f parking.sql parking
php -f index.php parking
psql -v ON_ERROR_STOP=1 -f spaces.sql parking

