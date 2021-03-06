﻿//////////////////////////////////////////////////////////////////////////////////////////////
// Neo4j Connector for Power BI
//   From: https://github.com/cskardon/Neo4jDataConnectorForPowerBi
//   License details all at the github page, but if you don't want to browse - it's MIT
section Neo4j;

//////////////////////////////////////////////////////////////////////////////////////////////
// Public Functions
//   This is badly titled, as technically, only the 'shared' function is public, but the other
//   2 are in this section as they are the 'meat' of the data connector.

//
// This is the _shared_ definition which exports the function to be visible to PowerBI
// NB. The `Value.ReplaceType` call is there to allow the UI to render the 'help' text defined in the `ExecuteCypherType`
//
[DataSource.Kind="Neo4j", Publish="Neo4j.Publish"]
shared Neo4j.ExecuteCypher = Value.ReplaceType(ExecuteCypherImpl, ExecuteCypherType);

//
// This is the type definition - providing hints on the PowerBI UI
//
ExecuteCypherType = type function (
    databaseName as (type text meta [
            Documentation.FieldCaption = "Nombre de base de datos",
            Documentation.FieldDescription = "El nombre de su base de datos (solo se usa para una base de datos 4.0, si no está seguro, use neo4j)",
            Documentation.SampleValues = {"neo4j", "hr"}
    ]),
    label as (type text meta [
            Documentation.FieldCaption = "Label",
            Documentation.FieldDescription = "Ingresa el label aqui",
            Documentation.SampleValues = {"AsientoContable"},
            Documentation.AllowedValues = {"AsientoContable"}
    ]),
     startdate as (type text meta [
            Documentation.FieldCaption = "fecha inicio",
            Documentation.FieldDescription = "Inserte su fecha inicio aqui formato AAAA-MM-DD",
            Documentation.SampleValues = {"2020-08-03"}
    ]),
     enddate as (type text meta [
            Documentation.FieldCaption = "fecha limite",
            Documentation.FieldDescription = "Inserte su fecha limite aqui formato AAAA-MM-DD",
            Documentation.SampleValues = {"2020-08-04"}
    ]),
    scheme as (type text meta [
		    Documentation.FieldDescription = "El esquema para conectarse a su instancia de Neo4j",
            Documentation.SampleValues = {"http", "https"},
		    Documentation.AllowedValues = { "http", "https" }
    ]),
    address as (type text meta [
            Documentation.FieldCaption = "Direccion",
            Documentation.FieldDescription = "La direccion de su instancia de Neo4j",
            Documentation.SampleValues = {"localhost.", "127.0.0.1"}
    ]),
    port as (type number meta [
            Documentation.FieldCaption = "Puerto",
            Documentation.FieldDescription = "El puerto de su instancia de Neo4j",
            Documentation.SampleValues = {"7474"}
    ]),
    limit as (type text meta [
            Documentation.FieldCaption = "Limite",
            Documentation.FieldDescription = "Limite de numero de filas que retorna la consulta",
            Documentation.SampleValues = {"25"}
    ]),
    neo4jVersion as (type number meta [
            Documentation.FieldCaption = "Version del Neo4j",
            Documentation.FieldDescription = "La version del servidor al cual se conecta",
            Documentation.SampleValues = {3.5, 4.0},
            Documentation.AllowedValues = {3.0, 3.1, 3.2, 3.3, 3.4, 3.5, 4.0}
    ]),
    timeout as (type number meta [
            Documentation.FieldCaption = "Tiempo de espera para consultas (segundos)",
            Documentation.FieldDescription = "Si está ejecutando una consulta larga, es posible que desee establecer este valor alto",
            Documentation.SampleValues = {30}
    ])
) as table meta [
		Documentation.Name = "Ejecutar Consulta Cypher - Output",
        Documentation.LongDescription = "Proporciona la respuesta de la consulta en un documento Json."];

///
/// This is based on the blog post at: http://xclave.co.uk/2017/06/22/using-powerbi-with-neo4j/ 
/// taking into account the comments from 'Will' - to get the column output using the names returned from the query
///
ExecuteCypherImpl = (
            databaseName as nullable text,
            label as nullable text,
            startdate as nullable text,
            enddate as nullable text,
            scheme as nullable text,
			address as nullable text, 
			port as nullable number,
            limit as nullable text,
            neo4jVersion as nullable number,
            timeout as nullable number) as table =>
let
      Cypher = Neo4j.CreateCypher(startdate, enddate, limit, label),
    _source = Web.Contents(Neo4j.DefaultUri(scheme, address, port, neo4jVersion, databaseName), [
        Headers = if Extension.CurrentCredential()[AuthenticationKind] = "Implicit" then ImplicitRequestHeaders else DefaultRequestHeaders,
        Content = Neo4j.CypherToM(Cypher),
        Timeout=#duration(0,0,0,Neo4j.GetTimeout(timeout))
    ]),
    _json = Json.Document(_source),
	_results = _json[results],
	_results1 = _results{0},
	_data = _results1[data],
	_columns = _results1[columns],
	_tabledResults = Table.FromList(_data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
	_rows = Table.ExpandRecordColumn(_tabledResults, "Column1", {"row"}, {"Column1.row"}),
	_column1Row = _rows[Column1.row],
	table = Table.FromRows(_column1Row, _columns)
in 
	table;

//////////////////////////////////////////////////////////////////////////////////////////////
// Private Functions

//
// Generates the default request headers needed for Neo4j to work
//
DefaultRequestHeaders = [
    #"Authorization" = "Basic " & Neo4j.Encode(Extension.CurrentCredential()[Username], Extension.CurrentCredential()[Password]),
	#"Content-Type"="application/json"
];

ImplicitRequestHeaders = [
	#"Content-Type"="application/json"
];

//
// Generates the URI to connect to, taking the scheme, address and port - if these aren't supplied, defaults will be used.
//  scheme: 'http'
//  address: 'localhost'
//  port: 7474
//  version: 3.5
//  databaseName: neo4j
//
Neo4j.DefaultUri = (optional scheme as nullable text, optional address as nullable text, optional port as nullable number, optional neo4jVersion as nullable number, optional databaseName as nullable text) =>
	let
        _version = if(neo4jVersion) is null then 3.5 else neo4jVersion,
        _databaseName = if(databaseName) is null then "neo4j" else databaseName,
        _transactionEndPoint = if(_version) < 4.0 then "db/data/transaction/commit" else "db/" & _databaseName & "/tx",
		_port = if (port) is null then 7474 else port,
		_address = if address is null then "localhost." else address,
		_scheme = if scheme is null then "http" else scheme,
		uri = _scheme & "://" & _address & ":" & Text.From(_port) & "/" & _transactionEndPoint
	in
		uri;

//
// Encodes a username/password into a combined base64 string of {user}:{password}
//
Neo4j.Encode = (user as text, password as text) =>
    let
        encoded = Binary.ToText(Text.ToBinary(user & ":" & password), 0)
    in
        encoded;

//
// constructs cypher query based on inputs
//
Neo4j.CreateCypher = (startdate as text, enddate as text, limit as text, label as text) =>
    let 
        _startdate = if (startdate) is null then "2010-01-01" else startdate,
        _enddate = if (enddate) is null then "2020-12-31" else enddate,
        _limit = if (limit) is null then "25" else limit,
        _label = if label =  "AsientoContable" then "MATCH(acc:AsientoContableCabecera)-[r]->(acd:AsientoContableDetalle) " else "MATCH(n) ",
        cypher = _label & "where date(acc.TransDate) = date(" & _startdate & ") or date(acc.TransDate) < date(" & _enddate & ") return acc,acd"  
    in 
        cypher;

// example: 
// match(acc:AsientoContableCabecera)-[r]->(acd:AsientoContableDetalle) where date(acc.TransDate)=date('2010-01-01') or date(acc.TransDate)< date('2010-01-31') return acc, acd

//
// Takes the cypher given and converts it into a structure Neo4j expects at the Transaction Endpoint
//
Neo4j.CypherToM = (cypher as text) =>
    let 
        binary = Text.ToBinary("{
                    ""statements"" : [ {
                    ""statement"" : "" " & cypher & " ""} ]
                    }")
    in
        binary;

Neo4j.GetTimeout = (timeout as nullable number) =>
    let 
        _timeout = if(timeout) is null then 30 else timeout
    in
        _timeout;

//////////////////////////////////////////////////////////////////////////////////////////////
// Connector Definitions

//
// Connector definition, allows access via User/Password combinations and Anonymous (Implicit)
//
Neo4j = [
    Authentication = [
        UsernamePassword = [
            Label = "Neo4j Authentication",
            UsernameLabel = "Username",
            PasswordLabel = "Password"
        ],
		Anonymous = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

//
// The UI Publishing definition, i.e. where it shows in the UI, whether it's beta etc
//
Neo4j.Publish = [
    Beta = true,
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/cskardon/Neo4jDataConnectorForPowerBi/",
    SourceImage = Neo4j.Icons,
    SourceTypeImage = Neo4j.Icons
];

// 
// Various sized icons for UI display
//
Neo4j.Icons = [
    Icon16 = { Extension.Contents("Neo4j16.png"), Extension.Contents("Neo4j20.png"), Extension.Contents("Neo4j24.png"), Extension.Contents("Neo4j32.png") },
    Icon32 = { Extension.Contents("Neo4j32.png"), Extension.Contents("Neo4j40.png"), Extension.Contents("Neo4j48.png"), Extension.Contents("Neo4j64.png") }
];