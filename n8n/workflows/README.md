# n8n workflows

`workflows.json` is an n8n workflow-only export from the deployed PostgreSQL
database. It contains:

- `Form Submission to Google` — active at export time
- `Simple Chatbot` — inactive at export time

The export contains references to the configured Google Sheets and OpenAI
credentials, but it does not contain credential bodies, OAuth tokens, API
keys, passwords, or decrypted secrets. After importing into another n8n
instance, create or select the corresponding credentials in the n8n UI.

Import with:

```bash
n8n import:workflow --input=workflows.json
```
