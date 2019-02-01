/*
This query returns a 4x3 array.
The first column lists the four major types of bus service operated by the MBTA.
The second and third columns contain the total revenue vehicle hours operated on weekdays and Saturdays.

by Mark Perelmuter
*/
-----------------------------
/*
is_weekday is 1 if the trip runs on a weekday and 0 otherwise.
is_saturday works the same for Saturdays.
Thus the two sum(products) return the sum of weekday rev_hrs and Saturday rev_hrs respectively.

trip_duration_sec is calculated by taking the difference in latest arrival time
(i.e. arrival at terminus) and earliest departure time (i.e. departure from origin) for a given trip
and converting the string timestamps to seconds-after-midnight.
*/

SELECT subquery.route_desc,
		sum(subquery.trip_duration_sec*subquery.is_weekday)/3600 AS total_rev_hrs_wkdy,
		sum(subquery.trip_duration_sec*subquery.is_saturday)/3600 AS total_rev_hrs_sat
FROM (
	/*
	This subquery creates a table with a row for each trip,
	which has the calculated duration,
	several characteristics from GTFS,
	and two boolean integers to determine day of week.
	*/
	SELECT gr.route_desc,
		gt.route_id,
		gt.service_id,
		gst.trip_id,
		
		(substring(max(gst.arrival_time),1,2)::int*3600 + substring(max(gst.arrival_time),4,2)::int*60 + substring(max(gst.arrival_time),7,2)::int) -
		(substring(min(gst.departure_time),1,2)::int*3600 + substring(min(gst.departure_time),4,2)::int*60 + substring(min(gst.departure_time),7,2)::int) 
		AS trip_duration_sec, --trip duration calculation described in the header.
		
		(gt.service_id LIKE '%Weekday%')::int AS is_weekday, --1 if weekday, 0 otherwise
		(gt.service_id LIKE '%Saturday%')::int AS is_saturday--1 if Saturday,0 otherwise
	
	FROM gtfs_stop_times AS gst, gtfs_routes AS gr, gtfs_trips AS gt
	
	WHERE gst.trip_id = gt.trip_id AND 
		gt.route_id = gr.route_id AND 
		gr.route_desc LIKE '%Bus%' AND --this includes: Key Bus, Commuter Bus, Local Bus, Community Bus
		gr.route_desc NOT IN ('Rail Replacement Bus', 'Supplemental Bus')
			--Bustitutions are sporadic and change from weekend to weekend so are excluded.
			--Supplemental Bus is excluded per MBTA Service Delivery Guidelines.
	
	GROUP BY gst.trip_id, gt.route_id, gr.route_desc, gt.service_id
	
) AS subquery
GROUP BY subquery.route_desc