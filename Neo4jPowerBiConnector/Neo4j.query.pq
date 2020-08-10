// Use this file to write queries to test your data connector
/*
let
    result = Neo4j.Count()
in
    result
*/
/*
let 
	result = Neo4j.GetCountOfNodes()
in
	result
*/

let 
	result = Neo4j.ExecuteCypher("baltic", "AsientoContable", "2010-01-01", "2020-01-31", "http", "gbneo4j.grupobaudelet.com", 7474, "1000000", 4, 90 )
in
	result