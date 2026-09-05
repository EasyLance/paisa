# Security policy

Financial records are sensitive. Do not report a suspected vulnerability through public issues or include transaction data, tokens, SMS bodies, bank account numbers, or credentials in bug reports.

## Operating requirements

- Production must use Firebase token verification and enforced Firebase App Check; development header authentication must remain disabled.
- MySQL, Redis, object storage, and backups must use encryption in transit and at rest in the selected India region.
- Logs must redact authorization, App Check, notes, and ingestion metadata. Raw SMS messages must never be uploaded.
- Book access is deny-by-default. Workspace administration does not grant access to a private book without a `BookMembership`.
- Imported amounts and transaction-source records are immutable. Corrections use categories, splits, comments, or exclusion states and create audit events.
- Rotate credentials after any suspected disclosure and revoke Firebase sessions for affected users.

Use the private security contact configured by the operator for disclosures. A public contact address must be added before commercial launch.
