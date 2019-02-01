/*
This query returns two percentage values.
These are two of the metrics MBTA uses to measure system performance within the MBTA service area:
1. Population of dense areas near frequently served MBTA stops as a proportion of population of dense areas
2. Population near all MBTA stops as a proportion of total service area population.

Regarding the code itself, apologies for the very computationally inefficient style. Like any good software project
it was done incrementally and by the time it was completed there wasn't time for a full rewrite.

by Mark Perelmuter
*/
----------------
/*
This table contains all stops with frequent service. Regarding what counts as "frequent service:"
MBTA service delivery policy page 16 says the following:
	In this section, frequent transit service is defined to include all bus stops along key bus
	routes, all rapid transit stations, and any bus stop that receives frequent service during
	its span of service. 
	
For simplicity the last clause was ignored and only those bus stops with key routes
serving them were assumed to have frequent service. 
Rapid transit stations were included, as per the above definition, because they provide frequent
service to their users even though they are not bus stops.
*/
DROP TABLE IF EXISTS frequent_stops;
CREATE TABLE frequent_stops AS

SELECT DISTINCT s.stop_id, s.stop_name, s.the_geom, r.route_short_name 
FROM gtfs_routes AS r, gtfs_trips AS t, gtfs_stop_times AS st, gtfs_stops AS s
WHERE (route_desc = 'Key Bus' OR route_desc = 'Rapid Transit')
	AND r.route_id = t.route_id
	AND t.trip_id = st.trip_id
	AND st.stop_id = s.stop_id;

/*
This table contains all MBTA stops, with the exception of those serving rail replacement buses.
This exception was made because bustitutions are not 'typical' MBTA service and operate sporadically.
*/
DROP TABLE IF EXISTS all_stops;
CREATE TABLE all_stops AS

SELECT DISTINCT s.stop_id, s.stop_name, s.the_geom, r.route_short_name 
FROM gtfs_routes AS r, gtfs_trips AS t, gtfs_stop_times AS st, gtfs_stops AS s
WHERE route_desc NOT IN('Rail Replacement Bus')
	AND r.route_id = t.route_id
	AND t.trip_id = st.trip_id
	AND st.stop_id = s.stop_id;

/*
This table contains a single geometry that is the union of 800m (1/2-mile) radius circles around each frequent stop.
This is drawn from the previously created frequent_stops table.
*/
DROP TABLE IF EXISTS frequent_buffer;
CREATE TABLE frequent_buffer AS
SELECT ST_UNION(
	ST_BUFFER(
		ST_TRANSFORM(the_geom,2163) --The SRID must be set to 2163 to ensure compatibility with other datasets and good display properties.
	,800) --800m walking distance is about 0.5 miles.
) FROM frequent_stops;

/*
This table contains a single geometry that is the union of 800m (1/2-mile) radius circles around each MBTA stop.
This is drawn from the previously created all_stops table.
*/
DROP TABLE IF EXISTS all_buffer;
CREATE TABLE all_buffer AS
SELECT ST_UNION(
	ST_BUFFER(
		ST_TRANSFORM(the_geom,2163)--The SRID must be set to 2163 to ensure compatibility with other datasets and good display properties.
	,800) --800m walking distance is about 0.5 miles.
) FROM all_stops;

/*
This table contains a single geometry that is the union of the two provided shape files that make up the MBTA service area.
*/
DROP TABLE IF EXISTS service_area;
CREATE TABLE service_area AS
SELECT ST_UNION(hd.geom, ld.geom)
FROM gisdata_rtasmbtahigh_polypolygon AS hd, gisdata_rtasmbtasec_polypolygon AS ld;

/*
This is the critical table for the main computation.
This table contains one row for each block group, which contains:
1. bg.gid, the block group ID
2. bg.poptotal, the block group population
3. fbx, a boolean integer (0=false, 1=true) that describes whether the given block group intersects the frequent-stops buffer
4. abx, a boolean integer (0=false, 1=true) that describes whether the given block group intersects the all-stops buffer
5. sax, a boolean integer (0=false, 1=true) that describes whether the given block group intersects the MBTA service area
6. dense_area, a boolean that describes whether the given block group has more than 7000 ppl/sq mi of land

The following notes are relevant to the computations for fbx, abx, and sax:
a. The union operation that creates the buffer for fb, ab 'loses' the SRID, 
	which is 2163 as specified previously, so this must be assigned.
b. The block groups and service area come without an SRID but were created with SRID=4326, 
	so this must be assigned and then the geom transformed for compatibility.
c. ST_INTERSECTS considers whether the two elements intersect at any point. This is a
	known simplification which overcounts population slightly. Almost all block groups
	that are not mostly water are quite small, so the effect of this is believed to be
	insignificant.
*/
DROP TABLE IF EXISTS block_groups_intersects;
CREATE TABLE block_groups_intersects AS
SELECT bg.gid, bg.poptotal, 
		ST_INTERSECTS(ST_SETSRID(fb.st_union,2163),ST_TRANSFORM(ST_SETSRID(bg.geom,4326),2163))::int AS fbx,
		ST_INTERSECTS(ST_SETSRID(ab.st_union,2163),ST_TRANSFORM(ST_SETSRID(bg.geom,4326),2163))::int AS abx,
		ST_INTERSECTS(ST_TRANSFORM(ST_SETSRID(service_area.st_union,4326),2163),ST_TRANSFORM(ST_SETSRID(bg.geom,4326),2163))::int AS sax,
		bg.poptotal/bg.aland10*1609.34*1609.34 >= 7000 AS dense_area --MBTA specifies 7000 ppl/sq mi as the threshold for density.
																	  --The population is divided by land area (in sq m) and then
																	  --this number is converted to sq mi.
FROM frequent_buffer AS fb, all_buffer AS ab, block_groups_2010 AS bg, service_area 																		 
WHERE bg.aland10 > 0; --this avoids division by zero errors
																							 
/*
This returns the desired percentages.																							 
*/
SELECT round(sq.pop_nearallstops/sq.pop_svcarea * 100.0,2) AS base_metric,
		round(sq.pop_dense_nearfreqstops/sq.pop_dense_svcarea * 100.0,2) AS freq_metric
FROM (
	SELECT sum(bgi.poptotal * bgi.fbx * (bgi.dense_area::int)) AS pop_dense_nearfreqstops,
		sum(bgi.poptotal * bgi.abx * bgi.sax) AS pop_nearallstops,
		sum(bgi.poptotal * bgi.sax * (bgi.dense_area::int)) AS pop_dense_svcarea, 
		sum(bgi.poptotal * bgi.sax) AS pop_svcarea
	FROM block_groups_intersects AS bgi
) AS sq