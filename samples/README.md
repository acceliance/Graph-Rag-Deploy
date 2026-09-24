# Samples

Everything needed to see the product work in ten minutes, and to check that an
on-premises model behaves before trusting it.

| Path | What it is | Expected outcome |
|---|---|---|
| `model/billing-model-stereotyped.json` | A small billing model — `Customer`, `Invoice`, `InvoiceLine`, `Contract`, enumeration `InvoiceStatus` — whose GraphRag stereotypes carry its Graph-RAG settings: identity keys (`siret`, `number`, `contractNumber`), normalisation, fuzzy matching on customers, anchor classes, extraction hints, two extraction groups (`billing`, `contracts`), `Contract.scope` indexed on its own. Stereotypes declared in `LocalModule`, the default for a model written by hand or by an AI (Graph-RAG recognises them by name). Valid against `schemas/schema_uml_model.json` | Loads from *Model ▸ Load the sample* or by upload; the settings editor fills itself from the stereotypes |
| `pdf/facture-2025-0042.pdf` | Text-layer invoice from *ACME SAS*, three lines, status *émise*, references contract **CT-77** | **Accepted**. Creates 1 `Invoice`, 1 `Customer`, 3 `InvoiceLine`, and a **stub** `Contract CT-77` (referenced, not documented) |
| `pdf/facture-2025-0057.pdf` | Second invoice, same customer written *ACME Services SAS* with the same SIRET | **Accepted**. Merges into the same `Customer` (identity on `siret`); the name difference is kept as a lower-confidence conflict in the ledger |
| `pdf/recette-tarte-aux-pommes.pdf` | An apple-pie recipe | **Rejected** by the relevance gate with a reason naming the missing billing classes. Force it from *Documents* to see what happens (nothing useful is extracted) |
| `profiles/financial-analyst.md` | Agent profile: role and persona of a financial analyst (French) | Import from *Admin ▸ Profiles*, select it in *Agent*, ask *"Quel est le total TTC facturé à ACME ?"* |
| `profiles/enterprise-architect.md` | Agent profile: enterprise architect, dependency-oriented, adds an optional *Cartographie* section | Ask *"Quelles entités dépendent du contrat CT-77 ?"* — the answer must flag CT-77 as referenced but undocumented |

## Relevance-gate thresholds for the sample

The thresholds are not part of the model: they are settings of each model version. After
*Initialise*, enter these values in *AI settings ▸ Relevance gate of model v1* (or send them
to `PUT /model/gate`):

| Threshold | Value | Meaning |
|---|---|---|
| `similarityFloor` | 0.35 | Cosine similarity above which a chunk counts as covered by an anchor class |
| `coverageFloor` | 0.10 | Share of covered chunks below which a document is rejected without any LLM call |
| `confidenceThreshold` | 0.5 | Minimum confidence of the LLM triage for a document to be accepted |

Left empty, each field falls back to the AI-settings default; the only difference is the
similarity floor, which defaults to 0.30 with `text-embedding-3-large`.

## Suggested first questions

- *Combien de factures sont émises pour ACME et pour quel montant total HT ?* — graph aggregate.
- *Que dit la facture 2025-0042 sur les conditions de paiement ?* — evidence search.
- *Quels contrats sont référencés sans être présents dans le corpus ?* — stub listing.

## Checking an on-premises model

*About ▸ Benchmark* (or `POST /jobs/benchmark`) runs these samples with the
configured chat, extraction and embedding slots and reports precision and
recall per class, the gate decisions and the token usage. Run it after
switching any slot to a local model.
