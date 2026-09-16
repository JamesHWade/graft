# Shared laboratory vocabulary
Vocabulary release: urn:example:vocabulary:v1
Binding release: urn:example:bindings:v1
Vocabulary SHA-256: db149bbfd9cfebaef37d08ffa694bb16d116fa71b569188b9ab1f3eba5175bf7
Bindings SHA-256: d8aeab24cfddd34e3780d66ce1a2b27d6adfd1cbe754c675bc46d24cd420e13e
Mappings support discovery. They do not authorize joins, comparison, access, or execution.
Assertions retain direction and qualifiers. Retracted or negated assertions are not positive facts.
## Terms
{"id":"urn:example:sample","kind":"concept","definition":"A physical sample with a laboratory-local identifier.","aliases":["sample","specimen"]}
{"id":"urn:example:measurement","kind":"concept","definition":"One measurement event on a sample.","aliases":["measurement","assay"]}
{"id":"urn:example:temperature","kind":"concept","definition":"Measured temperature; units and conditions must be checked separately.","aliases":["temperature"]}
{"id":"urn:example:measurement-of-sample","kind":"relationship","definition":"A measurement event has the indicated physical sample as its subject.","aliases":[],"domain":"urn:example:measurement","range":"urn:example:sample"}
## Exact dictionary references
{"id":"urn:example:dictionary:lab-a:v1","workflow":"lab-a","path":"lab-a.yaml","sha256":"7e9840cd2d8fb6218da8169be133edf3ee7a234938ba5fb6e481ddcd42645ed4"}
{"id":"urn:example:dictionary:lab-b:v1","workflow":"lab-b","path":"lab-b.yaml","sha256":"120a7e88a76b031ef713fbdb2e251ede1ae6e40ee1d19ca510c29edf5c83de10"}
## Binding explanations
Binding `lab-a:reading_id`: `urn:example:dictionary:lab-a:v1` table `readings` (`reading_id`) maps to concept `urn:example:measurement`. Scope: lab-a; grain: one measurement event; condition: ambient.
Binding `lab-a:sample_id`: `urn:example:dictionary:lab-a:v1` table `readings` (`sample_id`) maps to concept `urn:example:sample`. Scope: lab-a; grain: one measurement event; condition: ambient.
Binding `lab-a:temperature_c`: `urn:example:dictionary:lab-a:v1` table `readings` (`temperature_c`) maps to concept `urn:example:temperature`. Scope: lab-a; grain: one measurement event; condition: ambient.
Binding `lab-a:measured-sample`: `urn:example:dictionary:lab-a:v1` table `readings` (`reading_id -> sample_id`) maps to relationship `urn:example:measurement-of-sample`. Scope: lab-a; grain: one measurement event; condition: ambient.
Binding `lab-b:assay_id`: `urn:example:dictionary:lab-b:v1` table `assays` (`assay_id`) maps to concept `urn:example:measurement`. Scope: lab-b; grain: daily mean per sample; condition: heated.
Binding `lab-b:specimen`: `urn:example:dictionary:lab-b:v1` table `assays` (`specimen`) maps to concept `urn:example:sample`. Scope: lab-b; grain: daily mean per sample; condition: heated.
Binding `lab-b:temperature_f`: `urn:example:dictionary:lab-b:v1` table `assays` (`temperature_f`) maps to concept `urn:example:temperature`. Scope: lab-b; grain: daily mean per sample; condition: heated.
Binding `lab-b:measured-sample`: `urn:example:dictionary:lab-b:v1` table `assays` (`assay_id -> specimen`) maps to relationship `urn:example:measurement-of-sample`. Scope: lab-b; grain: daily mean per sample; condition: heated.
## Assertion explanations
Assertion `assertion:1`: `lab-a:reading:r1` -> `urn:example:measurement-of-sample` -> `lab-a:sample:s1`. Status: accepted; negated: false; source: urn:example:source:worksheet-1; time: 2026-09-01; scope: lab-a.
Assertion `assertion:2`: `lab-b:assay:a1` -> `urn:example:measurement-of-sample` -> `lab-b:sample:s1`. Status: retracted; negated: true; source: urn:example:source:worksheet-2; time: 2026-09-02; scope: lab-b.
## Exact binding records
{"id":"lab-a:reading_id","kind":"concept","dictionary":"urn:example:dictionary:lab-a:v1","table":"readings","field":"reading_id","term":"urn:example:measurement","scope":"lab-a","grain":"one measurement event","condition":"ambient"}
{"id":"lab-a:sample_id","kind":"concept","dictionary":"urn:example:dictionary:lab-a:v1","table":"readings","field":"sample_id","term":"urn:example:sample","scope":"lab-a","grain":"one measurement event","condition":"ambient"}
{"id":"lab-a:temperature_c","kind":"concept","dictionary":"urn:example:dictionary:lab-a:v1","table":"readings","field":"temperature_c","term":"urn:example:temperature","scope":"lab-a","grain":"one measurement event","condition":"ambient"}
{"id":"lab-a:measured-sample","kind":"relationship","dictionary":"urn:example:dictionary:lab-a:v1","table":"readings","from":"reading_id","to":"sample_id","term":"urn:example:measurement-of-sample","scope":"lab-a","grain":"one measurement event","condition":"ambient"}
{"id":"lab-b:assay_id","kind":"concept","dictionary":"urn:example:dictionary:lab-b:v1","table":"assays","field":"assay_id","term":"urn:example:measurement","scope":"lab-b","grain":"daily mean per sample","condition":"heated"}
{"id":"lab-b:specimen","kind":"concept","dictionary":"urn:example:dictionary:lab-b:v1","table":"assays","field":"specimen","term":"urn:example:sample","scope":"lab-b","grain":"daily mean per sample","condition":"heated"}
{"id":"lab-b:temperature_f","kind":"concept","dictionary":"urn:example:dictionary:lab-b:v1","table":"assays","field":"temperature_f","term":"urn:example:temperature","scope":"lab-b","grain":"daily mean per sample","condition":"heated"}
{"id":"lab-b:measured-sample","kind":"relationship","dictionary":"urn:example:dictionary:lab-b:v1","table":"assays","from":"assay_id","to":"specimen","term":"urn:example:measurement-of-sample","scope":"lab-b","grain":"daily mean per sample","condition":"heated"}
## Exact qualified assertion records
{"id":"assertion:1","subject":"lab-a:reading:r1","predicate":"urn:example:measurement-of-sample","object":"lab-a:sample:s1","source":"urn:example:source:worksheet-1","status":"accepted","negated":false,"time":"2026-09-01","scope":"lab-a"}
{"id":"assertion:2","subject":"lab-b:assay:a1","predicate":"urn:example:measurement-of-sample","object":"lab-b:sample:s1","source":"urn:example:source:worksheet-2","status":"retracted","negated":true,"time":"2026-09-02","scope":"lab-b"}
