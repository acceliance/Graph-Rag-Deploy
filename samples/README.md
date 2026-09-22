# Samples

Everything needed to see the product work in ten minutes, and to check that an
on-premises model behaves before trusting it.

| Path | What it is | Expected outcome |
|---|---|---|
| `model/billing-model.json` | A small billing model: `Customer`, `Invoice`, `InvoiceLine`, `Contract`, enumeration `InvoiceStatus`. Valid against the product's model schema | Loads from *Model ▸ Load the sample* or by upload |
| `model/billing-model-extension.json` | Its Graph-RAG extension: identity keys (`siret`, `number`, `contractNumber`), normalisation, fuzzy matching on customers, anchor classes, extraction hints, two extraction groups, gate thresholds | Loads with the model |
| `pdf/facture-2025-0042.pdf` | Text-layer invoice from *ACME SAS*, three lines, status *émise*, references contract **CT-77** | **Accepted**. Creates 1 `Invoice`, 1 `Customer`, 3 `InvoiceLine`, and a **stub** `Contract CT-77` (referenced, not documented) |
| `pdf/facture-2025-0057.pdf` | Second invoice, same customer written *ACME Services SAS* with the same SIRET | **Accepted**. Merges into the same `Customer` (identity on `siret`); the name difference is kept as a lower-confidence conflict in the ledger |
| `pdf/recette-tarte-aux-pommes.pdf` | An apple-pie recipe | **Rejected** by the relevance gate with a reason naming the missing billing classes. Force it from *Documents* to see what happens (nothing useful is extracted) |
| `profiles/financial-analyst.md` | Agent profile: role and persona of a financial analyst (French) | Import from *Admin ▸ Profiles*, select it in *Agent*, ask *"Quel est le total TTC facturé à ACME ?"* |
| `profiles/enterprise-architect.md` | Agent profile: enterprise architect, dependency-oriented, adds an optional *Cartographie* section | Ask *"Quelles entités dépendent du contrat CT-77 ?"* — the answer must flag CT-77 as referenced but undocumented |

## Suggested first questions

- *Combien de factures sont émises pour ACME et pour quel montant total HT ?* — graph aggregate.
- *Que dit la facture 2025-0042 sur les conditions de paiement ?* — evidence search.
- *Quels contrats sont référencés sans être présents dans le corpus ?* — stub listing.

## Checking an on-premises model

*About ▸ Benchmark* (or `POST /jobs/benchmark`) runs these samples with the
configured chat, extraction and embedding slots and reports precision and
recall per class, the gate decisions and the token usage. Run it after
switching any slot to a local model.
