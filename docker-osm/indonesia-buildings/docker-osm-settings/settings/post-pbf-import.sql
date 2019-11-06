-- Updates for all tables
ALTER table osm_buildings add column building_type character varying (100);
ALTER table osm_buildings add column building_type_score numeric;
ALTER table osm_buildings add column building_area  numeric;
ALTER TABLE osm_buildings add column building_area_score numeric;
ALTER table osm_buildings add column building_material_score numeric;
ALTER table osm_buildings add column building_river_distance  numeric;
ALTER table osm_buildings add column building_distance_score numeric;
ALTER table osm_buildings add column vertical_river_distance numeric;
ALTER table osm_buildings add column building_elevation numeric;
ALTER TABLE osm_buildings add column building_road_length numeric;
ALTER TABLE osm_roads add column road_type character varying (50);
ALTER TABLE osm_buildings add column building_river_distance_score numeric;

-- Add a trigger function to notify QGIS of DB changes
CREATE FUNCTION public.notify_qgis() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        BEGIN NOTIFY qgis;
        RETURN NULL;
        END;
    $$;

-- Create  functions here

CREATE OR REPLACE FUNCTION building_types_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
    CASE
           WHEN new.amenity ILIKE '%school%' OR new.amenity ILIKE '%kindergarten%' THEN 'School'
           WHEN new.amenity ILIKE '%university%' OR new.amenity ILIKE '%college%' THEN 'University/College'
           WHEN new.amenity ILIKE '%government%' THEN 'Government'
           WHEN new.amenity ILIKE '%clinic%' OR new.amenity ILIKE '%doctor%' THEN 'Clinic/Doctor'
           WHEN new.amenity ILIKE '%hospital%' THEN 'Hospital'
           WHEN new.amenity ILIKE '%fire%' THEN 'Fire Station'
           WHEN new.amenity ILIKE '%police%' THEN 'Police Station'
           WHEN new.amenity ILIKE '%public building%' THEN 'Public Building'
           WHEN new.amenity ILIKE '%worship%' and (religion ILIKE '%islam' or religion ILIKE '%muslim%')
               THEN 'Place of Worship -Islam'
           WHEN new.amenity ILIKE '%worship%' and religion ILIKE '%budd%' THEN 'Place of Worship -Buddhist'
           WHEN new.amenity ILIKE '%worship%' and religion ILIKE '%unitarian%' THEN 'Place of Worship -Unitarian'
           WHEN new.amenity ILIKE '%mall%' OR new.amenity ILIKE '%market%' THEN 'Supermarket'
           WHEN new.landuse ILIKE '%residential%' OR new.use = 'residential' THEN 'Residential'
           WHEN new.landuse ILIKE '%recreation_ground%' OR (leisure IS NOT NULL AND leisure != '') THEN 'Sports Facility'
           -- run near the end
           WHEN new.use = 'government' AND new."type" IS NULL THEN 'Government'
           WHEN new.use = 'residential' AND new."type" IS NULL THEN 'Residential'
           WHEN new.use = 'education' AND new."type" IS NULL THEN 'School'
           WHEN new.use = 'medical' AND new."type" IS NULL THEN 'Clinic/Doctor'
           WHEN new.use = 'place_of_worship' AND new."type" IS NULL THEN 'Place of Worship'
           WHEN new.use = 'school' AND new."type" IS NULL THEN 'School'
           WHEN new.use = 'hospital' AND new."type" IS NULL THEN 'Hospital'
           WHEN new.use = 'commercial' AND new."type" IS NULL THEN 'Commercial'
           WHEN new.use = 'industrial' AND new."type" IS NULL THEN 'Industrial'
           WHEN new.use = 'utility' AND new."type" IS NULL THEN 'Utility'
           -- Add default type
           WHEN new."type" IS NULL THEN 'Residential'
        END
    INTO new.building_type
    FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;

CREATE OR REPLACE FUNCTION building_recode_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
     SELECT

        CASE
            WHEN new.building_type = 'Clinic/Doctor' THEN 0.7
            WHEN new.building_type = 'Commercial' THEN 0.7
            WHEN new.building_type = 'School' THEN 1
            WHEN new.building_type = 'Government' THEN 0.7
            WHEN new.building_type ILIKE 'Place of Worship%' THEN 0.5
            WHEN new.building_type = 'Residential' THEN 1
            WHEN new.building_type = 'Police Station' THEN 0.7
            WHEN new.building_type = 'Fire Station' THEN 0.7
            WHEN new.building_type = 'Hospital' THEN 0.7
            WHEN new.building_type = 'Supermarket' THEN 0.7
            WHEN new.building_type = 'Sports Facility' THEN 0.3
            WHEN new.building_type = 'University/College' THEN 1.0
            ELSE 0.3
        END
     INTO new.building_type_score
     FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;

CREATE FUNCTION building_area_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    NEW.building_area:=ST_Area(new.geometry::GEOGRAPHY) ;
  RETURN NEW;
  END
  $$;



CREATE OR REPLACE FUNCTION building_area_score_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
  SELECT
        CASE
            WHEN new.building_area <= 100 THEN 1
            WHEN new.building_area > 100 and new.building_area <= 300 THEN 0.7
            WHEN new.building_area > 300 and new.building_area <= 500 THEN 0.5
            WHEN new.building_area > 500 THEN 0.3
            ELSE 0.3
        END
  INTO new.building_area_score
  FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;


CREATE OR REPLACE FUNCTION building_materials_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT

    CASE
        WHEN new."building:material" = 'brick' THEN 0.5
        WHEN new."building:material" = 'glass' THEN 0.3
        ELSE 0.3
    END
    INTO new.building_material_score
    FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;

CREATE OR REPLACE FUNCTION river_distance_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
     SELECT ST_Distance(ST_Centroid(NEW.geometry)::GEOGRAPHY, rt.geometry::GEOGRAPHY)
         INTO   NEW.building_river_distance
         FROM   osm_waterways AS rt
         ORDER BY
                NEW.geometry <-> rt.geometry
         LIMIT  1;

     RETURN NEW;
   END
  $$;

CREATE OR REPLACE FUNCTION river_distance_recode_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        CASE
            WHEN new.building_river_distance > 0 and new.building_river_distance <= 100 THEN 1.0
            WHEN new.building_river_distance > 100 and new.building_river_distance <= 300  THEN 0.7
            WHEN new.building_river_distance > 300 and new.building_river_distance <= 500  THEN 0.5
            WHEN new.building_river_distance > 500 THEN 0.3
            ELSE 0.3
        END
    INTO new.building_river_distance_score
    FROM osm_buildings
    ;
  RETURN NEW;

  END
  $$;


CREATE OR REPLACE FUNCTION river_elevation_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
            ST_VALUE(rast, geom)
    INTO new.vertical_river_distance
    FROM (WITH location as (
        SELECT ST_X(st_centroid(new.geometry)) as latitude,ST_Y(st_centroid(new.geometry)) as longitude,
        ST_SetSRID(St_MakePoint(ST_X(st_centroid(new.geometry)),ST_Y(st_centroid(new.geometry))),4326) as geom
         FROM osm_buildings )
        SELECT st_line_interpolate_point(b.geometry, 0.5) as geom, e.rast from location as a , osm_waterways as b, dem as e
        WHERE ST_Intersects(e.rast, a.geom)
        ORDER BY a.geom <-> b.geometry
        LIMIT  1) foo;
  RETURN NEW;

  END
  $$;

CREATE OR REPLACE FUNCTION building_elevation_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
            height
    INTO new.building_elevation
    FROM (WITH centroid as (
 select ST_SetSRID(St_MakePoint(ST_X(st_centroid(new.geometry)),ST_Y(st_centroid(new.geometry))),4326) as geom FROM osm_buildings
 )
 SELECT ST_VALUE(e.rast, b.geom) as height
  FROM dem e , centroid as b
    WHERE ST_Intersects(e.rast, b.geom)) foo;
  RETURN NEW;

  END
  $$;

CREATE OR REPLACE FUNCTION elevation_recode_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        CASE
            WHEN (new.building_elevation - new.vertical_river_distance) <= 0  THEN 1.0
            WHEN (new.building_elevation - new.vertical_river_distance) > 0 and (new.building_elevation - new.vertical_river_distance) <= 1   THEN 0.8
            WHEN (new.building_elevation - new.vertical_river_distance) > 1 and (new.building_elevation - new.vertical_river_distance) <= 2  THEN 0.5
            WHEN (new.building_elevation - new.vertical_river_distance) > 2 THEN 0.1
            ELSE 0.3
        END
    INTO new.elevation_area_score
    FROM osm_buildings
    ;
  RETURN NEW;

  END
  $$;

CREATE OR REPLACE FUNCTION building_road_density_mapper () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
            total_length
    INTO new.building_road_length
    FROM (WITH clipping AS
            (SELECT
            ST_Intersection(v.geometry,m.geom) AS intersection_geom,
            v.*
            FROM
              osm_roads as v,
             (select gid,st_buffer(ST_SetSRID(ST_Extent(new.a.geometry),4326)::geography,1000) as geom
from osm_buildings as a   group by a.geom,gid )
             as m
            WHERE
              ST_Intersects(v.geometry, m.geom) and v.highway in ('trunk','road','secondary','trunk_link','secondary_link','tertiary_link', 'primary', 'residential', 'primary_link',
'motorway_link','motorway')    )
            (SELECT sum(st_length(intersection_geom)) as total_length FROM clipping)
             ) foo ;
  RETURN NEW;

  END
  $$;

CREATE FUNCTION refresh_osm_build_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  osm_buildings_mv ;
  RETURN NEW;
  END
  $$;


CREATE FUNCTION refresh_osm_roads_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  osm_roads_mv;
  RETURN NEW;
  END
  $$;

CREATE FUNCTION refresh_osm_waterways_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  osm_waterways_mv ;
  RETURN NEW;
  END
  $$;

CREATE OR REPLACE FUNCTION road_type_mapping () RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
    CASE
           WHEN new.type ILIKE 'motorway' OR new.type ILIKE 'highway' or new.type ILIKE 'trunk' then 'Motorway or highway'
           WHEN new.type ILIKE 'motorway_link' then 'Motorway link'
           WHEN new.type ILIKE 'primary' then 'Primary road'
           WHEN new.type ILIKE 'primary_link' then 'Primary link'
           WHEN new.type ILIKE 'tertiary' then 'Tertiary'
           WHEN new.type ILIKE 'tertiary_link' then 'Tertiary link'
           WHEN new.type ILIKE 'secondary' then 'Secondary'
           WHEN new.type ILIKE 'secondary_link' then 'Secondary link'
           WHEN new.type ILIKE 'living_street' OR new.type ILIKE 'residential' OR new.type ILIKE 'yes' OR new.type ILIKE 'road' OR new.type ILIKE 'unclassified' OR new.type ILIKE 'service'
           OR new.type ILIKE '' OR new.type IS NULL then 'Road, residential, living street, etc.'
           WHEN new.type ILIKE 'track' then "type" = 'Track'
           WHEN new.type ILIKE 'cycleway' OR new.type ILIKE 'footpath' OR new.type ILIKE 'pedestrian' OR new.type ILIKE 'footway' OR new.type ILIKE 'path' then  "type" = 'Cycleway, footpath, etc.'
        END
    INTO new.road_type
    FROM osm_roads
    ;
  RETURN NEW;
  END
  $$;

  -- Building roads event --

CREATE OR REPLACE FUNCTION flooded_waterways_function () RETURNS trigger LANGUAGE plpgsql
AS $$
declare
    name character varying;
BEGIN
    name := (SELECT new.name FROM osm_flood WHERE id = NEW.id);

     EXECUTE 'CREATE OR REPLACE VIEW flooded_waterways_' || quote_ident(new.name) || ' AS
        SELECT a.waterway FROM osm_waterways as a inner join osm_flood as b on ST_Within(a.geometry,b.geometry) where b.id = '|| new.id ||';';

  RETURN NEW;
  END;
  $$;

-- Building flood event --

CREATE OR REPLACE FUNCTION flooded_buildings_function () RETURNS trigger LANGUAGE plpgsql
AS $$
declare
    name character varying;
BEGIN
    name := (SELECT new.name FROM osm_flood WHERE id = NEW.id);

     EXECUTE 'CREATE OR REPLACE VIEW flooded_buildings_' || quote_ident(new.name) || ' AS
  SELECT a.building_type, a.building_type_score, a.building_material_score, a.low_lying_area_score
  FROM osm_buildings as a inner join osm_flood as b on ST_Within(a.geometry,b.geometry) where b.id = '|| new.id ||';';

  RETURN NEW;
  END;
  $$;

-- Building roads event --

CREATE OR REPLACE FUNCTION flooded_roads_function () RETURNS trigger LANGUAGE plpgsql
AS $$
declare
    name character varying;
BEGIN
    name := (SELECT new.name FROM osm_flood WHERE id = NEW.id);

    EXECUTE 'CREATE OR REPLACE VIEW flooded_roads_' || quote_ident(new.name) || ' AS
  SELECT a.type FROM osm_roads as a inner join osm_flood as b on ST_Within(a.geometry,b.geometry) where b.id = '|| new.id ||';';

  RETURN NEW;
  END;
  $$;

-- Vulnerability reporting and mapping for Buildings


-- Initial Updates for all tables

-- Initial update for osm_building_type
update osm_buildings set building_type = 'School'         WHERE amenity ILIKE '%school%' OR amenity ILIKE '%kindergarten%' ;
update osm_buildings set building_type = 'University/College'         WHERE amenity ILIKE '%university%' OR amenity ILIKE '%college%' ;
update osm_buildings set building_type = 'Government'        WHERE amenity ILIKE '%government%' ;
update osm_buildings set building_type = 'Clinic/Doctor'         WHERE amenity ILIKE '%clinic%' OR amenity ILIKE '%doctor%' ;
update osm_buildings set building_type = 'Hospital'         WHERE amenity ILIKE '%hospital%' ;
update osm_buildings set building_type = 'Fire Station'        WHERE amenity ILIKE '%fire%' ;
update osm_buildings set building_type = 'Police Station'        WHERE amenity ILIKE '%police%' ;
update osm_buildings set building_type = 'Public Building'         WHERE amenity ILIKE '%public building%' ;
update osm_buildings set building_type = 'Place of Worship -Islam'         WHERE amenity ILIKE '%worship%' and (religion ILIKE '%islam' or religion ILIKE '%muslim%');

update osm_buildings set building_type = 'Place of Worship -Buddhist'         WHERE amenity ILIKE '%worship%' and religion ILIKE '%budd%';
update osm_buildings set building_type = 'Place of Worship -Unitarian'         WHERE amenity ILIKE '%worship%' and religion ILIKE '%unitarian%' ;
update osm_buildings set building_type = 'Supermarket'          WHERE amenity ILIKE '%mall%' OR amenity ILIKE '%market%' ;
 update osm_buildings set building_type = 'Residential'          WHERE landuse ILIKE '%residential%' OR use = 'residential';
update osm_buildings set building_type = 'Sports Facility'          WHERE landuse ILIKE '%recreation_ground%' OR (leisure IS NOT NULL AND leisure != '') ;
           -- run near the end
update osm_buildings set building_type = 'Government'          WHERE use = 'government' AND "type" IS NULL ;
update osm_buildings set building_type = 'Residential'          WHERE use = 'residential' AND "type" IS NULL ;
 update osm_buildings set building_type = 'School'         WHERE use = 'education' AND "type" IS NULL ;
update osm_buildings set building_type = 'Clinic/Doctor'          WHERE use = 'medical' AND "type" IS NULL ;
 update osm_buildings set building_type = 'Place of Worship'         WHERE use = 'place_of_worship' AND "type" IS NULL ;
 update osm_buildings set building_type = 'School'         WHERE use = 'school' AND "type" IS NULL ;
 update osm_buildings set building_type = 'Hospital'         WHERE use = 'hospital' AND "type" IS NULL ;
 update osm_buildings set building_type = 'Commercial'         WHERE use = 'commercial' AND "type" IS NULL ;
 update osm_buildings set building_type = 'Industrial'         WHERE use = 'industrial' AND "type" IS NULL ;
 update osm_buildings set building_type = 'Utility'         WHERE use = 'utility' AND "type" IS NULL ;
           -- Add default type
 update osm_buildings set building_type = 'Residential'  WHERE "type" IS NULL ;



-- reclassify road type for osm_roads

update osm_roads set road_type = 'Motorway or highway' where  type ILIKE 'motorway' OR type ILIKE 'highway' or type ILIKE 'trunk' ;
update osm_roads set road_type = 'Motorway link' where  type ILIKE 'motorway_link' ;
update osm_roads set road_type = 'Primary road' where  type ILIKE 'primary';
update osm_roads set road_type = 'Primary link' where  type ILIKE 'primary_link' ;
update osm_roads set road_type = 'Tertiary' where  type ILIKE 'tertiary';
update osm_roads set road_type = 'Tertiary link' where  type ILIKE 'tertiary_link';
update osm_roads set road_type = 'Secondary' where  type ILIKE 'secondary';
update osm_roads set road_type = 'Secondary link' where  type ILIKE 'secondary_link';
update osm_roads set road_type = 'Road, residential, living street, etc.' where  type ILIKE 'living_street' OR type ILIKE 'residential' OR type ILIKE 'yes' OR type ILIKE 'road' OR type ILIKE 'unclassified' OR type ILIKE 'service'
           OR type ILIKE '' OR type IS NULL;

update osm_roads set road_type = "type" = 'Track' where  type ILIKE 'track';
update osm_roads set road_type =  "type" = 'Cycleway, footpath, etc.' where  type ILIKE 'cycleway' OR type ILIKE 'footpath' OR type ILIKE 'pedestrian' OR type ILIKE 'footway' OR type ILIKE 'path';



-- Initial update to recode the building_type calculated above for osm_building_type

update osm_buildings set building_type_score =
  CASE
            WHEN building_type = 'Clinic/Doctor' THEN 0.7
            WHEN building_type = 'Commercial' THEN 0.7
            WHEN building_type = 'School' THEN 1
            WHEN building_type = 'Government' THEN 0.7
            WHEN building_type ILIKE 'Place of Worship%' THEN 0.5
            WHEN building_type = 'Residential' THEN 1
            WHEN building_type = 'Police Station' THEN 0.7
            WHEN building_type = 'Fire Station' THEN 0.7
            WHEN building_type = 'Hospital' THEN 0.7
            WHEN building_type = 'Supermarket' THEN 0.7
            WHEN building_type = 'Sports Facility' THEN 0.3
            WHEN building_type = 'University/College' THEN 1.0
            ELSE 0.3
        END;


-- Create a column to store the area for osm_buildings

update osm_buildings set building_area  =
         ST_Area(geometry::GEOGRAPHY) ;

-- Initial updates to update the building_area

update osm_buildings set building_area_score  =
        CASE
            WHEN building_area <= 100 THEN 1
            WHEN building_area > 100 and building_area <= 300 THEN 0.7
            WHEN building_area > 300 and building_area <= 500 THEN 0.5
            WHEN building_area > 500 THEN 0.3
            ELSE 0.3
        END;



-- reclassify building material to create building_material score

update osm_buildings set building_material_score =
  CASE
        WHEN "building:material" = 'brick' THEN 0.5
        WHEN "building:material" = 'glass' THEN 0.3
        ELSE 0.3
    END;





-- Function to update the distance from a river to the centroid of the building

update osm_buildings set building_river_distance =foo.distance FROM (SELECT ST_Distance(ST_Centroid(geometry)::GEOGRAPHY, rt.geometry::GEOGRAPHY) as distance

         FROM   osm_waterways AS rt
         ORDER BY
               geometry <-> rt.geometry
         LIMIT  1) foo;



--- Reclassify building_river_distance to create building_river_distance_score

update osm_buildings set building_river_distance_score =
CASE
            WHEN building_river_distance > 0 and building_river_distance <= 100 THEN 1.0
            WHEN building_river_distance > 100 and building_river_distance <= 300  THEN 0.7
            WHEN building_river_distance > 300 and building_river_distance <= 500  THEN 0.5
            WHEN building_river_distance > 500 THEN 0.3
            ELSE 0.3
        END;



-- update to calculate the elevation of the nearest river in relation to  building centroid

update osm_buildings set vertical_river_distance =ST_VALUE(foo.rast, foo.geom)
    FROM (WITH location as (
        SELECT ST_X(st_centroid(geometry)) as latitude,ST_Y(st_centroid(geometry)) as longitude,
        ST_SetSRID(St_MakePoint(ST_X(st_centroid(geometry)),ST_Y(st_centroid(geometry))),4326) as geom
         FROM osm_buildings )
        SELECT ST_LineInterpolatePoint(b.geometry, 0.5) as geom, e.rast from location as a , osm_waterways as b, dem as e
        WHERE ST_Intersects(e.rast, a.geom)
        ORDER BY a.geom <-> b.geometry
        LIMIT  1) foo;



-- update to calculate the elevation of a building's centroid from a raster cell

update osm_buildings set building_elevation =foo.height

    FROM (WITH centroid as (
 select ST_SetSRID(St_MakePoint(ST_X(st_centroid(geometry)),ST_Y(st_centroid(geometry))),4326) as geom FROM osm_buildings
 )
 SELECT ST_VALUE(e.rast, b.geom) as height
  FROM dem e , centroid as b
    WHERE ST_Intersects(e.rast, b.geom)) foo;




-- create a function that recodes the values of the building elevation against the river elevation (low_lying_area_score)

UPDATE osm_buildings set low_lying_area_score =
        CASE
            WHEN (building_elevation - vertical_river_distance) <= 0  THEN 1.0
            WHEN (building_elevation - vertical_river_distance) > 0 and (building_elevation - vertical_river_distance) <= 1   THEN 0.8
            WHEN (building_elevation - vertical_river_distance) > 1 and (building_elevation - vertical_river_distance) <= 2  THEN 0.5
            WHEN (building_elevation - vertical_river_distance) > 2 THEN 0.1
            ELSE 0.3
        END;



-- Update to calculate the road density length (still to write the recoding function )

update osm_buildings set building_road_length =foo.total_length

    FROM (
         WITH clipping AS
            (SELECT
            ST_Intersection(v.geometry,m.geom) AS intersection_geom,
            v.*
            FROM
              osm_roads as v,
             (select osm_id,st_buffer(ST_SetSRID(ST_Extent(a.geometry),4326)::geography,1000) as geom
from osm_buildings as a   group by a.geometry,osm_id )
             as m
            WHERE
              ST_Intersects(v.geometry, m.geom) and v.type in ('trunk','road','secondary','trunk_link','secondary_link','tertiary_link', 'primary', 'residential', 'primary_link',
'motorway_link','motorway')    )
            (SELECT sum(st_length(intersection_geom)) as total_length FROM clipping)
             ) foo ;




-- SQL functions for DB reporting

-- count number or roads intersecting Surabaya
CREATE VIEW osm_roads_surabaya_stats as
SELECT type, COUNT(osm_id) FROM (
    SELECT DISTINCT ON (a.osm_id) a.osm_id, a.type
    FROM osm_roads as a
    INNER JOIN osm_admin as b ON ST_Intersects(a.geometry, b.geometry) where b.name = 'Surabaya'
) subquery
GROUP BY type order by count;


-- count number of rivers intersecting surabaya
CREATE OR REPLACE VIEW osm_rivers_surabaya_stats as
SELECT waterway, COUNT(osm_id) FROM (
    SELECT DISTINCT ON (a.osm_id) a.osm_id, a.waterway
    FROM osm_waterways as a
    INNER JOIN osm_admin as b ON ST_Intersects(a.geometry, b.geometry) where b.name = 'Surabaya'
) subquery
GROUP BY waterway order by count;

-- count number of buildings intersecting surabaya
CREATE OR REPLACE VIEW osm_buildings_surabaya_stats as
SELECT building_type, COUNT(osm_id) FROM (
    SELECT DISTINCT ON (a.osm_id) a.osm_id, a.building_type
    FROM osm_buildings as a
    INNER JOIN osm_admin as b ON ST_Intersects(a.geometry, b.geometry) where b.name = 'Surabaya'
) subquery
GROUP BY building_type order by count;


-- Create Mviews or views for FBIS dashboards

-- count number or buildings by building_type

CREATE MATERIALIZED VIEW osm_buildings_mv as
SELECT building_type , COUNT (building_type)
FROM osm_buildings
GROUP BY building_type;

CREATE UNIQUE INDEX un_idx_type ON osm_buildings_mv (building_type);


-- count number or roads by road_type
CREATE MATERIALIZED VIEW osm_roads_mv as
SELECT road_type , COUNT (road_type)
FROM osm_roads
GROUP BY road_type;

CREATE UNIQUE INDEX un_idx_roads_type ON osm_roads_mv (road_type);




-- count number or waterways by waterway

CREATE MATERIALIZED VIEW osm_waterways_mv as
SELECT waterway as type, COUNT (waterway)
FROM osm_waterways
GROUP BY waterway;

CREATE UNIQUE INDEX  un_idx_wt_way on osm_waterways_mv ("type");

-- Create OSM Flood layer for inserting from dashboard

CREATE TABLE public.osm_flood (
    id SERIAL,
    geometry public.geometry(MultiPolygon,4326),
    name character varying(80)
);

CREATE INDEX idx_osm_flood on osm_flood using gist (geometry);
CREATE INDEX id_osm_flood_name on osm_flood (name);
CREATE INDEX idx_osm_road on osm_roads (road_type);
CREATE INDEX idx_osm_building on osm_buildings (building_type);
CREATE INDEX idx_osm_waterway on osm_waterways (waterway);
CREATE INDEX idx_osm_bd_score on osm_buildings (building_type_score);




-- All triggers will come in the last part
-- Based on the tables defined in the mapping.yml create triggers

CREATE TRIGGER flooded_buildings BEFORE INSERT OR UPDATE ON osm_flood FOR EACH ROW EXECUTE PROCEDURE
    flooded_buildings_function ();

CREATE TRIGGER flooded_roads BEFORE INSERT OR UPDATE ON osm_flood FOR EACH ROW EXECUTE PROCEDURE
    flooded_roads_function ();

CREATE TRIGGER flooded_waterways BEFORE INSERT OR UPDATE ON osm_flood FOR EACH ROW EXECUTE PROCEDURE
    flooded_waterways_function ();

CREATE TRIGGER notify_admin
  AFTER INSERT OR UPDATE OR DELETE  ON public.osm_admin
    FOR EACH STATEMENT EXECUTE PROCEDURE public.notify_qgis();

    CREATE TRIGGER notify_buildings
  AFTER INSERT OR UPDATE OR DELETE  ON public.osm_buildings
    FOR EACH STATEMENT EXECUTE PROCEDURE public.notify_qgis();


    CREATE TRIGGER notify_roads
  AFTER INSERT OR UPDATE OR DELETE  ON public.osm_roads
    FOR EACH STATEMENT EXECUTE PROCEDURE public.notify_qgis();

    CREATE TRIGGER notify_waterways
  AFTER INSERT OR UPDATE OR DELETE  ON public.osm_waterways
    FOR EACH STATEMENT EXECUTE PROCEDURE public.notify_qgis();

CREATE TRIGGER building_type_mapper BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_types_mapper ();

CREATE TRIGGER st_building_recoder BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_recode_mapper();

CREATE TRIGGER area_recode_mapper BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_area_mapper();

CREATE TRIGGER building_material_mapper BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_materials_mapper();

CREATE TRIGGER river_distance_mapper BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    river_distance_mapper ();

CREATE TRIGGER st_river_recode BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    river_distance_recode_mapper ();

CREATE TRIGGER river_elevation_calc BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    river_elevation_mapper () ;

CREATE TRIGGER building_elevation_calc BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_elevation_mapper () ;

CREATE TRIGGER st_elevation_recoder BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    elevation_recode_mapper () ;

CREATE TRIGGER buildings_stats_rf BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE refresh_osm_build_stats();

CREATE TRIGGER roads_stats_rf BEFORE INSERT OR UPDATE ON osm_roads FOR EACH ROW EXECUTE PROCEDURE refresh_osm_roads_stats();

CREATE TRIGGER waterways_stats_rf BEFORE INSERT OR UPDATE ON osm_waterways FOR EACH ROW EXECUTE PROCEDURE refresh_osm_waterways_stats();

CREATE TRIGGER road_length_calc BEFORE INSERT OR UPDATE ON osm_buildings FOR EACH ROW EXECUTE PROCEDURE
    building_road_density_mapper () ;

