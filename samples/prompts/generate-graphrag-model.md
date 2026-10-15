# Prompt: generate a Graph-RAG model (stereotyped `schema_uml_model.json`)

Use this prompt with Claude, ChatGPT or any assistant that accepts attachments. Attach
[`schemas/schema_uml_model.json`](../../schemas/schema_uml_model.json) and
[`samples/model/billing-model-stereotyped.json`](../model/billing-model-stereotyped.json), paste
everything between the two `PROMPT` markers, and fill in the domain block at the end.

Each rule below matches a check the product runs: the JSON Schema, then `POST /model/validate`,
which runs the same checks as the *Model* screen. The sources are
`graphrag-api/graphrag/model/validation.py` and `stereotypes.py`, and the stereotype definitions come
from the GraphRag Modelio module (`modelio.graphrag/src/main/conf/module.xml`).

<!-- PROMPT -->
````text
You are authoring a data model for Acceliance Graph-RAG, a product that extracts typed entities
from PDF documents into a knowledge graph. Attached: the JSON Schema of the model file
(schema_uml_model.json) and a complete valid example (billing-model-stereotyped.json).
Follow the rules below exactly. The output is validated by a program; any deviation is rejected.

══ 1. OUTPUT ═══════════════════════════════════════════════════════════════════════════════
- Answer with ONE ```json code block and nothing else: no comments inside the JSON, no trailing
  commas, no text before or after.
- The root object has exactly these keys, in this order:
    "$schema", "modelStereotypes", "classes", "enumerations"
  No other root key. "$schema" is
  "https://raw.githubusercontent.com/acceliance/Graph-Rag-Deploy/main/schemas/schema_uml_model.json".
- No key anywhere may hold null. Leave out an optional key rather than writing null or "".
- Only the keys defined in the schema are allowed (additionalProperties is false everywhere).

══ 2. THE ENVELOPE: "modelStereotypes" (copy verbatim) ═════════════════════════════════════
Copy this array as-is. Do not rename, retype, reorder, translate or add properties. Its
"moduleName" is "GraphRag" (not "LocalModule"): that is the Modelio module that owns these
stereotypes.

"modelStereotypes": [
  {"name": "GraphRagEntity", "moduleName": "GraphRag",
   "description": "Graph-RAG settings of a class: match strategy, relevance anchor, extraction hints and group.",
   "stereotypeProperties": [
     {"name": "graphRagMatch", "type": "ENUMERATE", "description": "exact | fuzzy: how an extracted instance is matched to existing entities"},
     {"name": "graphRagFuzzyThreshold", "type": "FLOAT", "description": "Score (0-1) at or above which a fuzzy match merges automatically; empty = 0.92"},
     {"name": "graphRagReviewBand", "type": "FLOAT", "description": "Score (0-1) at or above which, below the threshold, a pair goes to review; empty = 0.75"},
     {"name": "graphRagAnchor", "type": "ENUMERATE", "description": "auto | true | false: whether the relevance gate uses this class; auto = when identified"},
     {"name": "graphRagExtractionHints", "type": "TEXT", "description": "Free text appended to the extraction prompt: labels, formats, where values appear"},
     {"name": "graphRagGroup", "type": "STRING", "description": "Extraction group; empty = the class's domain"}]},
  {"name": "GraphRagIdentity", "moduleName": "GraphRag",
   "description": "The attribute is part of the class's identity key.",
   "stereotypeProperties": [
     {"name": "graphRagIdentityOrder", "type": "INTEGER", "description": "Position in a composite identity key (1-based); empty = declaration order"},
     {"name": "graphRagNormalise", "type": "ENUMERATE", "description": "trim | casefold | digits | date | amount | none; empty = the default of the type"}]},
  {"name": "GraphRagEmbed", "moduleName": "GraphRag",
   "description": "The String attribute is indexed on its own in the vector store.",
   "stereotypeProperties": []}
]

══ 3. APPLYING A STEREOTYPE (references by name only) ══════════════════════════════════════
Everywhere else, a stereotype and its properties are referenced by their NAME as a plain string,
never re-declared as an object. The only shape allowed:

"stereotypeInstances": [
  {"modelStereotype": "<GraphRagEntity|GraphRagIdentity|GraphRagEmbed>",
   "stereotypePropertyInstances": [
     {"stereotypeProperty": "<property name from section 2>", "valueAsString": "<value as a string>"}
   ]}
]

- Every value is a JSON string: "0.92" not 0.92, "true" not true, "2" not 2.
- Write only the properties you set. Leave out a property rather than giving it "".
- One property appears at most once in an instance, and a stereotype at most once per artefact.
- A stereotype's properties belong to that stereotype only: graphRagNormalise goes under
  GraphRagIdentity, never under GraphRagEntity.
- GraphRagEmbed has no properties: "stereotypePropertyInstances": [].

Where each stereotype may be applied (anything else is an error):
| Stereotype        | Allowed on                                   | Never on                     |
|-------------------|----------------------------------------------|------------------------------|
| GraphRagEntity    | a class (classes[i].stereotypeInstances)     | attributes, relations, enums |
| GraphRagIdentity  | an attribute (…attributes[j].stereotypeInstances) | classes, relations, enums |
| GraphRagEmbed     | an attribute of type "String"                | anything else                |
Relations, enumerations and enumeration literals carry no GraphRag stereotype.

══ 4. ALLOWED VALUES ═══════════════════════════════════════════════════════════════════════
| Property                 | valueAsString                                              |
|--------------------------|------------------------------------------------------------|
| graphRagMatch            | "exact" or "fuzzy" (lowercase)                             |
| graphRagFuzzyThreshold   | decimal between "0" and "1", dot separator, e.g. "0.92"    |
| graphRagReviewBand       | decimal between "0" and "1", dot separator, e.g. "0.75"    |
| graphRagAnchor           | "true" or "false" (omit it for the default "auto")         |
| graphRagExtractionHints  | free text in the documents' language: labels, formats, position on the page |
| graphRagGroup            | a short lowercase group name, e.g. "billing"               |
| graphRagIdentityOrder    | integer "1", "2", … (only for a key of 2+ attributes)      |
| graphRagNormalise        | "trim" | "casefold" | "digits" | "date" | "amount" | "none"  |

══ 5. MODEL STRUCTURE ══════════════════════════════════════════════════════════════════════
Names
- Class and enumeration names: PascalCase, matching ^[A-Za-z][A-Za-z0-9_]*$. A class and an
  enumeration never share a name. Every name is unique.
- Attribute and relation names: camelCase, matching ^[a-z][A-Za-z0-9]*$ (no "_", no "-").
- Enumeration literals ("value"): SCREAMING_SNAKE_CASE, matching ^[A-Z][A-Z0-9_]*$, unique within
  their enumeration; each enumeration has at least one literal.
- Every class, attribute, relation, enumeration and literal has a "description" written for
  someone reading the documents (include the labels printed on them, in their language).
- Every class and enumeration has a "domain".

Attributes
- "type" is one of: Boolean, Byte, Char, Date, Double, Float, Integer, Long, Short, String.
  Amounts use Double. Identifiers use String even when made of digits (they may have leading
  zeros, spaces or letters).
- A field with a fixed set of values is NOT an attribute. Declare an enumeration under
  "enumerations" and a relation to it:
    {"name": "status", "target": {"name": "InvoiceStatus"}, "cardinality": "OneToOne", "description": "…"}
  The target is the object {"name": …}, never the bare string, and the cardinality is always
  "OneToOne".
- Declare an attribute or relation only on the class that owns it, never again on a subclass.
  Within a class and its ancestors, an attribute and a relation never share a name.

Classes and relations
- Every class is written in full exactly once in "classes". Elsewhere (a relation "target"
  between classes, a "mother") it is referenced by its name as a string.
- Order "classes" so that a class comes after every class it references by string (mother
  class, relation targets). Relations are directed: declare each association once, on the side
  that reads naturally (Invoice → customer, ManyToOne), which avoids reference cycles.
- "mother" means single inheritance; no inheritance cycles.
- Cardinalities: "OneToMany" (the class owns a list: invoice → lines), "ManyToOne" (many point
  to one: invoice → customer), "OneToOne", "ManyToMany".

══ 6. GRAPH-RAG SETTINGS: DECISION RULES ═══════════════════════════════════════════════════
For each class, decide whether it is an ENTITY or a VALUE OBJECT:

A. ENTITY: its instances recur across documents (a customer, a contract, an invoice, a person, a
   site). Each entity:
   - carries GraphRagIdentity on each attribute that identifies one instance and is printed on the
     document. The attribute is declared on THIS class (not inherited) and is not Boolean;
   - uses graphRagNormalise by kind of value:
       identifier printed with spaces/dots (SIRET, IBAN, phone) → "digits"
       code or reference (CT-77, INV-2024-001)                  → "trim" or "casefold"
       person or company name                                    → "casefold"
       date                                                      → "date"
       amount                                                    → "amount";
   - adds graphRagIdentityOrder "1", "2", … on each part when the key has several attributes
     (e.g. lastName + birthDate), and leaves it out for a single-attribute key;
   - carries GraphRagEntity with at least graphRagExtractionHints;
   - gets graphRagAnchor "true" when finding this class proves a document belongs to the domain
     (typically the document's main subject: Invoice, Contract). An anchor always has an identity
     key.
B. VALUE OBJECT: it exists only inside one document (a line, a row, an address block, a
   section). It gets NO GraphRagIdentity and must be owned by an entity through a "OneToMany"
   relation (Invoice.lines → InvoiceLine). It may carry GraphRagEntity for its hints and group.

Matching
- graphRagMatch "fuzzy" only for an entity identified by a name that documents may spell
  differently (companies, people). Fuzzy requires an identity key. When you set the thresholds,
  graphRagFuzzyThreshold is strictly greater than graphRagReviewBand (defaults: 0.92 and 0.75).
- Otherwise leave graphRagMatch out ("exact" by default).

Extraction groups
- Each distinct graphRagGroup value is one LLM extraction call. A class without it follows its
  "domain". Set it only to batch classes differently from their domain. Put a value object in the
  same group as its owner, and each class in the group of the documents that actually print it.

Semantic indexing
- GraphRagEmbed goes on String attributes holding long free text worth searching on its own
  (clause, scope, observation, description of work), on the class that declares them. Never
  repeat it on a subclass.

Do not put relevance-gate thresholds (similarityFloor, coverageFloor, confidenceThreshold) in the
model: they are not stereotype properties.

══ 7. SELF-CHECK BEFORE ANSWERING ══════════════════════════════════════════════════════════
Verify each point and fix any failure silently:
[ ] Root keys: $schema, modelStereotypes (verbatim from section 2), classes, enumerations.
[ ] No null, no number or boolean inside valueAsString, no unknown key.
[ ] Every modelStereotype / stereotypeProperty reference is a name from section 2, used on the
    artefact kind allowed in section 3.
[ ] Every relation target and mother resolves; enum targets are {"name": …} + "OneToOne".
[ ] Every class referenced by string appears earlier in "classes".
[ ] No attribute typed with an enumeration name; identity attributes are not Boolean; embed
    attributes are String.
[ ] Every class without an identity key is the target of a OneToMany relation.
[ ] Every fuzzy class has an identity key and threshold > review band; every anchor has an
    identity key.
[ ] Names match the patterns of section 5; literals are SCREAMING_SNAKE_CASE and unique.

══ 8. MY DOMAIN ════════════════════════════════════════════════════════════════════════════
Documents (kind, language, issuer):            <…>
Entities I want to question:                   <…>
Identifiers printed on the documents
  (numbers, codes, names, dates, and formats): <…>
Fixed lists of values (statuses, types…):      <…>
Long texts worth searching semantically:       <…>
Questions I expect to ask:                     <…>
````
<!-- PROMPT -->

## After generation

1. Validate the schema layer locally:

   ```bash
   check-jsonschema --schemafile schemas/schema_uml_model.json model.json
   ```

2. Upload the file on the *Model* screen, or send it to `POST /model/validate`. Errors come with
   a JSON path. Paste them back to the assistant with "fix these errors and return the whole
   file".
3. A warning that a class *has no identity key and no OneToMany owner* means a value object has
   no owner. Either add the owning relation or give the class an identity key.
