# Architecture v0.1

```text
Flutter mobile application
        |
        | HTTPS / JSON
        v
FastAPI application
        |
        +-- Transaction service
        +-- Budget service
        +-- Email ingestion service (Milestone 3)
        +-- Classification service (Milestone 4)
        +-- Assistant service (Milestone 6)
        |
        v
PostgreSQL
```

## Design rules

1. Financial calculations are deterministic application code, not LLM output.
2. Gmail OAuth tokens are encrypted at rest.
3. Full bank account and card numbers are never stored.
4. Original email bodies are retained only when strictly necessary for debugging and only in a sanitized test environment.
5. User-defined merchant rules override built-in and AI classifications.
