# Schemas

JSON Schema for every file format this deployment kit's users create, upload or read.
This folder, including this README, is synced verbatim from `graph-rag-application\Schemas`
(the source of truth) by `Sync-SchemasToDeployKit.ps1`, which also copies the schemas into
the API image. Edit files there, not in `Graph-Rag-Deploy\schemas`; a re-sync overwrites any
local change. Relative links below resolve in the `Graph-Rag-Deploy` layout.

| File | Draft | Validates | Used for |
|---|---|---|---|
| `schema_uml_model.json` | 2020-12 | The data model JSON uploaded from *Model* (e.g. [`samples/model/billing-model-stereotyped.json`](../samples/model/billing-model-stereotyped.json)) | Classes, attributes, relations, enumerations, and stereotypes; the GraphRag stereotypes carry the Graph-RAG settings (identity keys, normalisation, fuzzy matching, anchor classes, extraction hints, extraction groups, indexed attributes) |
| `ingestion-ledger.schema.json` | 2020-12 | The per-document ledger the API writes to `./data/api/ingestion/<docId>.json` | Reading a ledger by hand — audit trail, retry/resume, and the input of re-index and rebuild jobs |
| `ai-prompt-markdown-schema.json` | Draft-07 | A Markdown prompt or profile file after `gray-matter` front-matter parsing (e.g. [`samples/profiles/`](../samples/profiles/)) | Front-matter structure of a custom agent profile or prompt override |

**Not published here:** `users.schema.json`, the application's internal account store.
It is an implementation detail of the API, never a file a deployment kit user authors.

## Editor support

Each schema is published at a stable URL (its `$id`), and the model schema accepts a
`$schema` key at the root. Put it first in your file and VS Code, JetBrains IDEs and most
JSON editors validate as you type and complete property names and enum values:

```json
{
  "$schema": "https://raw.githubusercontent.com/acceliance/Graph-Rag-Deploy/main/schemas/schema_uml_model.json",
  "classes": [ ]
}
```

The sample carries this key. The product ignores it.

## The model and its Graph-RAG settings

One file describes the model and how Graph-RAG treats it. The settings are stereotypes applied
to the model's classes and attributes, recognised by their **name**:

| Stereotype | On | Tagged values (`valueAsString`) |
|---|---|---|
| `GraphRagEntity` | a class | `graphRagMatch` (`exact` \| `fuzzy`), `graphRagFuzzyThreshold` and `graphRagReviewBand` (0–1), `graphRagAnchor` (`auto` \| `true` \| `false`), `graphRagExtractionHints` (text), `graphRagGroup` (extraction group) |
| `GraphRagIdentity` | an attribute of the identity key | `graphRagIdentityOrder` (1-based, composite keys), `graphRagNormalise` (`trim`, `casefold`, `digits`, `date`, `amount`, `none`) |
| `GraphRagEmbed` | a String attribute | — (indexed on its own for semantic search) |

A Modelio user installs the **GraphRag** module, applies these stereotypes, and uploads the
ModelioUtils JSON export as is. The *Model* screen reads the settings into its editor; what is
changed there is written back into the model as stereotypes, so the stored model stays the one
file that says everything. *Model ▸ Settings ▸ Download the model* returns it, ready for
ModelioUtils' import.

A model without stereotypes is valid too: every class is then a value object until identity
keys are set in the editor.

**Not in the model:** relevance-gate thresholds (`similarityFloor`, `coverageFloor`,
`confidenceThreshold`). They calibrate the embedding model rather than describe the domain, so
they are settings of each model version: *AI settings ▸ Relevance gate of model v<n>*, or
`PUT /model/gate`. They carry over to the next version on upgrade.

## Writing a model with an AI assistant

The model can be drafted by Claude, ChatGPT or any assistant that accepts file attachments. The
schema is self-contained and every property carries a description, so the assistant has what it
needs. What it does not know are the conventions listed in the prompt below; state them, or the
output will fail the checks of the *Model* screen.

Only the model is authored. The ingestion ledger is written by the API and is never uploaded,
so its schema is a reading aid, not an input for generation. Agent profiles are Markdown files
with front-matter; start from [`samples/profiles/`](../samples/profiles/) rather than from the
prompt schema.

1. Attach two files: `schema_uml_model.json` and
   [`samples/model/billing-model-stereotyped.json`](../samples/model/billing-model-stereotyped.json).
2. Send the prompt below with your domain filled in.
3. Paste the answer into *Model* (file or text). The screen validates against the schema, then
   runs the checks a schema cannot express: names are unique, every `mother` and relation
   `target` resolves, no inheritance cycle, enumeration targets carry `OneToOne`, tagged values
   are well formed, identity attributes are not `Boolean`, `graphRagFuzzyThreshold` is above
   `graphRagReviewBand`. Errors come with a JSON path; paste them back to the assistant and
   iterate. The settings can also be finished in the screen's editor.
4. *Initialise* only when the screen reports no error. Warnings about value objects (classes
   without identity) are expected for classes that live inside one document, such as a line.

### Prompt

````text
You are helping me author a data model for Acceliance Graph-RAG, a product that extracts
typed entities from PDFs into a graph. Attached: the JSON Schema of the model file
(schema_uml_model.json) and a complete, valid example (billing-model-stereotyped.json).

Produce a model for this domain:
<the kinds of PDFs, their language, the entities I want to question, the identifiers
printed on the documents (numbers, codes, dates), and the questions I expect to ask>

Rules:
- Answer with one JSON code block and nothing else. It must validate against the schema.
  Set its "$schema" key to the URL in the schema's "$id".
- Attribute types are the primitives of ModelType only. A field with a fixed set of values
  is an enumeration: declare it under "enumerations" and reference it from the class with a
  relation whose target is {"name": "<EnumName>"} and cardinality "OneToOne". Never name an
  enumeration as an attribute type.
- Every class is written in full exactly once in the "classes" array. A relation target or a
  mother class is referenced by its name as a string, and that class must appear earlier in
  the array, so order the classes accordingly. Attributes and relations are declared only on
  the class that owns them, never repeated on a child class.
- Naming: PascalCase for classes and enumerations, camelCase for attributes and relation
  role names, SCREAMING_SNAKE_CASE for enumeration values. Give every class, attribute,
  relation, enumeration and literal a description written for someone who reads the documents.
- The Graph-RAG settings are stereotypes, as in the example. Declare the ones you use once, in
  full, in "modelStereotypes" (moduleName "LocalModule"), with the exact stereotype and
  property names of the example; then apply them by name in "stereotypeInstances", each value
  as a string in "valueAsString".
- For every class whose instances recur across documents: put GraphRagIdentity on each
  attribute printed on the document that identifies one instance, with graphRagNormalise
  ("digits" for identifiers printed with spaces, "casefold" for names, "date" for dates,
  "amount" for amounts) and graphRagIdentityOrder when the key has several attributes. Put
  GraphRagEntity on the class with graphRagAnchor "true" when the presence of this class
  proves a document belongs to the domain, and graphRagExtractionHints describing the labels,
  formats and position of the values on the page. Classes that exist only inside one document
  (a line, a row, a section) get no GraphRagIdentity.
- Use graphRagMatch "fuzzy" only for classes identified by a name that documents may spell
  differently; keep graphRagFuzzyThreshold above graphRagReviewBand.
- graphRagGroup batches classes into one extraction call per group. Set it only to group
  classes differently from their "domain"; leave it out and each class follows its domain,
  which is usually enough.
- Put GraphRagEmbed on String attributes holding long free text worth searching on its own
  (a clause, a scope, a description).
- Do not put relevance-gate thresholds in the model: they are set per model version in the
  product.
````

### Validating outside the product

Any validator of the listed draft works. With Python:

```bash
pip install check-jsonschema
check-jsonschema --schemafile schemas/schema_uml_model.json model.json
```

This is the schema layer only. The checks of the tagged values and of the references between
classes run in the product: *Model* screen or `POST /model/validate`.
