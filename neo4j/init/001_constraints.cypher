// Carries forward the one constraint that already existed live on philia's
// Neo4j before this migration (verified via SHOW CONSTRAINTS), plus the two
// natural-key constraints that were missing despite being used as identity
// fields in code (Celestia's WeaponNode.weaponId and UIDNode.uid).
CREATE CONSTRAINT store_name IF NOT EXISTS
FOR (s:Store) REQUIRE s.name IS UNIQUE;

CREATE CONSTRAINT weapon_id_unique IF NOT EXISTS
FOR (w:WeaponNode) REQUIRE w.weaponId IS UNIQUE;

CREATE CONSTRAINT uid_node_uid_unique IF NOT EXISTS
FOR (u:UIDNode) REQUIRE u.uid IS UNIQUE;
