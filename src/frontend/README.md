# Frontend Service

This is the main frontend service for the Online Boutique application. It handles all web traffic and communicates with the backend microservices.

## Development

Run the following command to restore dependencies to `vendor/` directory:

```bash
dep ensure --vendor-only
```

## Running Locally

To run the frontend service locally, make sure you have Go installed and run:

```bash
go run main.go
```

The service will be available at http://localhost:8080