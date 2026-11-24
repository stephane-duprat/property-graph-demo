-- Part A. One person row becomes one vertex; one knows row becomes one directed edge.
CREATE TABLE pgd_person (
  person_id NUMBER CONSTRAINT pgd_person_pk PRIMARY KEY,
  person_name VARCHAR2(50) NOT NULL,
  city VARCHAR2(50) NOT NULL
);

CREATE TABLE pgd_knows (
  edge_id NUMBER CONSTRAINT pgd_knows_pk PRIMARY KEY,
  src_id NUMBER NOT NULL,
  dst_id NUMBER NOT NULL,
  since_year NUMBER(4) NOT NULL,
  CONSTRAINT pgd_knows_src_fk FOREIGN KEY (src_id) REFERENCES pgd_person(person_id),
  CONSTRAINT pgd_knows_dst_fk FOREIGN KEY (dst_id) REFERENCES pgd_person(person_id)
);
CREATE INDEX pgd_knows_src_ix ON pgd_knows(src_id);
CREATE INDEX pgd_knows_dst_ix ON pgd_knows(dst_id);

INSERT INTO pgd_person VALUES (1, 'Alice', 'Madrid');
INSERT INTO pgd_person VALUES (2, 'Bob', 'Barcelona');
INSERT INTO pgd_person VALUES (3, 'Carla', 'Madrid');
INSERT INTO pgd_person VALUES (4, 'Diego', 'Valencia');
INSERT INTO pgd_person VALUES (5, 'Elena', 'Bilbao');
INSERT INTO pgd_knows VALUES (101, 1, 2, 2020);
INSERT INTO pgd_knows VALUES (102, 1, 3, 2021);
INSERT INTO pgd_knows VALUES (103, 2, 4, 2022);
INSERT INTO pgd_knows VALUES (104, 3, 4, 2023);
INSERT INTO pgd_knows VALUES (105, 4, 1, 2024);
INSERT INTO pgd_knows VALUES (106, 2, 5, 2022);
INSERT INTO pgd_knows VALUES (107, 5, 3, 2024);
COMMIT;

CREATE PROPERTY GRAPH pgd_rel_graph
  VERTEX TABLES (
    pgd_person AS people KEY (person_id)
      LABEL person PROPERTIES (person_id, person_name AS name, city)
  )
  EDGE TABLES (
    pgd_knows AS links KEY (edge_id)
      SOURCE KEY (src_id) REFERENCES people (person_id)
      DESTINATION KEY (dst_id) REFERENCES people (person_id)
      LABEL knows PROPERTIES (edge_id, since_year)
  )
  OPTIONS (ENFORCED MODE);

SELECT * FROM pgd_person ORDER BY person_id;
SELECT * FROM pgd_knows ORDER BY edge_id;
